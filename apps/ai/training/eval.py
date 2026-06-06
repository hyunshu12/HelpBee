"""
Golden holdout 평가 — 모델 버전 비교용.

Usage:
    python -m training.eval \\
        --weights runs/yolo/v0.1.0-baseline/weights/best.pt \\
        --golden training/datasets/golden/data.yaml \\
        --imgsz 640

출력 (콘솔 + JSON):
    - mAP@0.5
    - mAP@0.5:0.95 (엄격)
    - Precision, Recall (전체 + 클래스별)
    - Recall@varroa = bee_with_varroa 클래스 recall (양봉가 입장 핵심: 응애 놓침 비율)
    - infestation_rate MAE (이미지별 추정 vs 라벨 감염률 평균 절대 오차, 분모=전체 벌)
    - Confusion matrix (저장: weights와 같은 디렉토리)

회귀 게이트 (apps/ai/CLAUDE.md §13):
    - 새 버전이 이전 버전 대비 mAP 동등 이상이어야 PR merge.
    - JSON 결과를 git에 커밋해 비교 추적 (training/eval_history/v0.X.Y.json).
"""

from __future__ import annotations

import argparse
import json
import logging
from collections import Counter, defaultdict
from pathlib import Path

logger = logging.getLogger(__name__)


def compute_infestation_rate_from_label(
    label_path: Path,
    varroa_id: int = 1,
    bee_class_ids: tuple[int, ...] = (0, 1, 2),
) -> float | None:
    """라벨 파일 → infestation_rate (%).

    infestation_rate = (bee_with_varroa 인스턴스) / (전체 벌 인스턴스) * 100
    분모 = bee_normal(0) + bee_with_varroa(1) + bee_other_disease(2)
    (risk.yaml / AIHUB_71667.md §10 정의. 71667 Q3=B → 표준 VMIR 계산 불가하므로 infestation_rate 사용.)
    """
    if not label_path.exists():
        return None
    counts = Counter()
    for line in label_path.read_text().splitlines():
        if line.strip():
            counts[int(line.split()[0])] += 1
    total_bees = sum(counts.get(c, 0) for c in bee_class_ids)
    if total_bees == 0:
        return None
    return counts.get(varroa_id, 0) / total_bees * 100


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    p = argparse.ArgumentParser()
    p.add_argument("--weights", type=Path, required=True, help="best.pt 경로")
    p.add_argument("--golden", type=Path, required=True, help="golden data.yaml")
    p.add_argument("--imgsz", type=int, default=640)
    p.add_argument("--conf", type=float, default=0.25)
    p.add_argument("--iou", type=float, default=0.5)
    p.add_argument(
        "--output",
        type=Path,
        default=None,
        help="결과 JSON 저장 경로. 미지정 시 weights 같은 폴더에 eval_golden.json",
    )
    args = p.parse_args()

    if not args.weights.exists():
        raise SystemExit(f"weights 없음: {args.weights}")
    if not args.golden.exists():
        raise SystemExit(f"golden data.yaml 없음: {args.golden}")

    from ultralytics import YOLO  # type: ignore

    model = YOLO(str(args.weights))

    # ===== 1. Ultralytics val: mAP, P, R 자동 =====
    logger.info(f"=== mAP 평가 시작 (imgsz={args.imgsz}) ===")
    metrics = model.val(
        data=str(args.golden),
        imgsz=args.imgsz,
        conf=args.conf,
        iou=args.iou,
        save_json=True,
        plots=True,
    )

    map50 = float(metrics.box.map50)  # mAP@0.5
    map5095 = float(metrics.box.map)  # mAP@0.5:0.95
    p_per_class = list(map(float, metrics.box.p))  # precision per class
    r_per_class = list(map(float, metrics.box.r))  # recall per class

    # 클래스 인덱스 → 이름 (data.yaml의 names)
    import yaml as _yaml

    data_cfg = _yaml.safe_load(args.golden.read_text())
    names: dict[int, str] = (
        data_cfg["names"]
        if isinstance(data_cfg["names"], dict)
        else {i: n for i, n in enumerate(data_cfg["names"])}
    )

    per_class = {}
    for idx, cls_name in names.items():
        per_class[cls_name] = {
            "precision": p_per_class[idx] if idx < len(p_per_class) else None,
            "recall": r_per_class[idx] if idx < len(r_per_class) else None,
        }

    # ===== 2. infestation_rate MAE — golden val 셋에서 이미지별 비교 =====
    logger.info("=== infestation_rate MAE 계산 ===")
    golden_root = args.golden.parent
    img_dir = golden_root / "images" / "val"
    lbl_dir = golden_root / "labels" / "val"

    rate_diffs: list[float] = []
    if img_dir.exists():
        # 모델 추론 + 라벨 infestation_rate 비교 (분모 = 전체 벌, AIHUB §10)
        for img_path in sorted(img_dir.iterdir()):
            if not img_path.is_file():
                continue
            lbl_path = lbl_dir / img_path.with_suffix(".txt").name
            label_rate = compute_infestation_rate_from_label(lbl_path)
            if label_rate is None:
                continue
            preds = model.predict(
                source=str(img_path), imgsz=args.imgsz, conf=args.conf, verbose=False
            )
            if not preds:
                continue
            cls_tensor = preds[0].boxes.cls.cpu().numpy() if preds[0].boxes else []
            counts = Counter(int(c) for c in cls_tensor)
            total_bees = counts.get(0, 0) + counts.get(1, 0) + counts.get(2, 0)
            varroa_n = counts.get(1, 0)
            pred_rate = (varroa_n / total_bees * 100) if total_bees > 0 else 0.0
            rate_diffs.append(abs(pred_rate - label_rate))

    rate_mae = sum(rate_diffs) / len(rate_diffs) if rate_diffs else None

    # ===== 3. 결과 요약 =====
    result = {
        "weights": str(args.weights),
        "golden": str(args.golden),
        "imgsz": args.imgsz,
        "mAP@0.5": round(map50, 4),
        "mAP@0.5:0.95": round(map5095, 4),
        "per_class": per_class,
        "varroa_recall": per_class.get("bee_with_varroa", {}).get("recall"),
        "infestation_rate_mae": round(rate_mae, 3) if rate_mae is not None else None,
        "infestation_rate_n_images": len(rate_diffs),
    }

    out_path = args.output or args.weights.parent / "eval_golden.json"
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=2))

    print("\n===== Golden Eval =====")
    for k, v in result.items():
        if k == "per_class":
            print(f"  per_class:")
            for cls, m in v.items():
                print(f"    {cls}: P={m['precision']}, R={m['recall']}")
        else:
            print(f"  {k}: {v}")
    print(f"\n결과 JSON: {out_path}")


if __name__ == "__main__":
    main()
