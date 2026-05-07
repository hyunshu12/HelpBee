"""
Golden holdout 평가 — 모델 버전 비교용.

Usage:
    python -m training.eval \\
        --weights runs/yolo/v0.1.0-baseline/weights/best.pt \\
        --golden training/datasets/golden/data.yaml \\
        --imgsz 1280

출력 (콘솔 + JSON):
    - mAP@0.5
    - mAP@0.5:0.95 (엄격)
    - Precision, Recall (전체 + 클래스별)
    - Recall@varroa (양봉가 입장 핵심: 응애 놓침 = false negative 비율)
    - VMIR MAE (이미지별 추정 VMIR vs 라벨 VMIR 평균 절대 오차)
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


def compute_vmir_from_label(label_path: Path, varroa_id: int = 1, normal_id: int = 0) -> float | None:
    """라벨 파일 → VMIR (mites per 100 bees)."""
    if not label_path.exists():
        return None
    counts = Counter()
    for line in label_path.read_text().splitlines():
        if line.strip():
            counts[int(line.split()[0])] += 1
    bees = counts.get(normal_id, 0) + counts.get(varroa_id, 0)
    # NB: bee_count 분모를 어떻게 잡을지는 라벨 매핑(Q3) 결과에 따라 다름.
    #     케이스 A (응애 자체 bbox)에서는 normal 만 분모. 케이스 B/C는 다름.
    if bees == 0:
        return None
    return counts.get(varroa_id, 0) / max(1, counts.get(normal_id, 0)) * 100


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    p = argparse.ArgumentParser()
    p.add_argument("--weights", type=Path, required=True, help="best.pt 경로")
    p.add_argument("--golden", type=Path, required=True, help="golden data.yaml")
    p.add_argument("--imgsz", type=int, default=1280)
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

    # ===== 2. VMIR MAE — golden val 셋에서 이미지별 비교 =====
    logger.info("=== VMIR MAE 계산 ===")
    golden_root = args.golden.parent
    img_dir = golden_root / "images" / "val"
    lbl_dir = golden_root / "labels" / "val"

    vmir_diffs: list[float] = []
    if img_dir.exists():
        # 모델 추론 + 라벨 VMIR 비교
        for img_path in sorted(img_dir.iterdir()):
            if not img_path.is_file():
                continue
            lbl_path = lbl_dir / img_path.with_suffix(".txt").name
            label_vmir = compute_vmir_from_label(lbl_path)
            if label_vmir is None:
                continue
            preds = model.predict(
                source=str(img_path), imgsz=args.imgsz, conf=args.conf, verbose=False
            )
            if not preds:
                continue
            cls_tensor = preds[0].boxes.cls.cpu().numpy() if preds[0].boxes else []
            counts = Counter(int(c) for c in cls_tensor)
            normal_n = counts.get(0, 0)
            varroa_n = counts.get(1, 0)
            pred_vmir = (varroa_n / max(1, normal_n)) * 100 if normal_n > 0 else 0.0
            vmir_diffs.append(abs(pred_vmir - label_vmir))

    vmir_mae = sum(vmir_diffs) / len(vmir_diffs) if vmir_diffs else None

    # ===== 3. 결과 요약 =====
    result = {
        "weights": str(args.weights),
        "golden": str(args.golden),
        "imgsz": args.imgsz,
        "mAP@0.5": round(map50, 4),
        "mAP@0.5:0.95": round(map5095, 4),
        "per_class": per_class,
        "varroa_recall": per_class.get("varroa_mite", {}).get("recall"),
        "vmir_mae": round(vmir_mae, 3) if vmir_mae is not None else None,
        "vmir_n_images": len(vmir_diffs),
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
