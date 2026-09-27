"""
Stage-1(성충 1-class `bee`) golden 평가 — 모델 버전 비교 + 스펙 §7 Stage-1 게이트.

Usage (apps/ai 에서):
    python -m training.eval \\
        --weights training/runs/yolo/v0.2.0-stage1/weights/best.pt \\
        --golden training/golden.json \\
        --label-root <aihub_to_yolo --mapping adult1 --manifest 산출>/labels/all \\
        [--imgsz 1024] [--output training/eval_history/v0.2.0-stage1.json]

golden.json (golden_holdout.py 산출) = {"varroa": [이미지 경로], "normal": [이미지 경로]} 두 목록을 합쳐
1-class 검출 평가 셋으로 쓴다. 라벨은 manifest 모드(이미지 미복사) 라벨 루트에서
yolo_list_dataset.label_path_for 규칙으로 찾는다 (patch_label_lookup).

⚠️ imgsz 는 학습값(stage1.yaml=1024)과 일치해야 한다.
mAP 는 conf=0.001 로 계산한다 (PR 곡선 전 구간 — 높은 conf 로 자르면 mAP 가 과소평가된다).
recall 은 Ultralytics 가 보고하는 max-F1 지점의 `bee` recall.

게이트 (스펙 §7 Stage-1): mAP@0.5 ≥ 0.85 AND bee recall ≥ 0.90. 미달 시 종료코드 1 (JSON 은 항상 기록).
출력 JSON: {weights, golden, n_images, imgsz, conf, iou, mAP@0.5, mAP@0.5:0.95, precision, recall, gate}.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import tempfile
from pathlib import Path

import yaml

logger = logging.getLogger(__name__)

MIN_MAP50 = 0.85
MIN_RECALL = 0.90


def golden_images(golden: Path) -> list[str]:
    g = json.loads(Path(golden).read_text(encoding="utf-8"))
    return sorted({*g.get("varroa", []), *g.get("normal", [])})


def write_golden_data_yaml(images: list[str], out_dir: Path) -> Path:
    """golden 이미지 목록 → Ultralytics 1-class data yaml (train/val 모두 같은 목록 — val 만 쓰임)."""
    out_dir = Path(out_dir)
    (out_dir / "golden.txt").write_text("".join(f"{i}\n" for i in images), encoding="utf-8")
    data = {"path": str(out_dir.resolve()), "train": "golden.txt", "val": "golden.txt", "nc": 1, "names": ["bee"]}
    path = out_dir / "golden_data.yaml"
    path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")
    return path


def stage1_gate(map50: float, recall: float, min_map50: float = MIN_MAP50, min_recall: float = MIN_RECALL) -> dict:
    ok_map, ok_rec = map50 >= min_map50, recall >= min_recall
    return {"min_map50": min_map50, "min_recall": min_recall, "map50_ok": ok_map, "recall_ok": ok_rec,
            "pass": ok_map and ok_rec}


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    p = argparse.ArgumentParser()
    p.add_argument("--weights", type=Path, required=True, help="Stage-1 best.pt 경로")
    p.add_argument("--golden", type=Path, default=Path("training/golden.json"), help="golden_holdout.py 산출 JSON")
    p.add_argument("--label-root", dest="label_root", type=Path, required=True,
                   help="aihub_to_yolo --mapping adult1 --manifest 산출 labels/all")
    p.add_argument("--imgsz", type=int, default=1024)  # 학습(stage1.yaml)과 일치 필수
    p.add_argument("--conf", type=float, default=0.001)  # mAP 계산용 — 올리지 말 것
    p.add_argument("--iou", type=float, default=0.7)  # Ultralytics val 기본값
    p.add_argument("--min-map50", dest="min_map50", type=float, default=MIN_MAP50)
    p.add_argument("--min-recall", dest="min_recall", type=float, default=MIN_RECALL)
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
        raise SystemExit(f"golden.json 없음: {args.golden}")
    images = golden_images(args.golden)
    if not images:
        raise SystemExit(f"golden.json 이 비어 있음: {args.golden}")

    from ultralytics import YOLO  # type: ignore

    from training.data.yolo_list_dataset import patch_label_lookup

    patch_label_lookup(args.label_root)
    model = YOLO(str(args.weights))

    with tempfile.TemporaryDirectory() as td:
        data_yaml = write_golden_data_yaml(images, Path(td))
        logger.info(f"=== golden mAP 평가 (n={len(images)}, imgsz={args.imgsz}, conf={args.conf}) ===")
        metrics = model.val(
            data=str(data_yaml),
            imgsz=args.imgsz,
            conf=args.conf,
            iou=args.iou,
            max_det=1500,
            split="val",
            plots=False,
        )

    map50 = float(metrics.box.map50)
    recall = float(metrics.box.r[0]) if len(metrics.box.r) else 0.0
    result = {
        "weights": str(args.weights),
        "golden": str(args.golden),
        "n_images": len(images),
        "imgsz": args.imgsz,
        "conf": args.conf,
        "iou": args.iou,
        "mAP@0.5": round(map50, 4),
        "mAP@0.5:0.95": round(float(metrics.box.map), 4),
        "precision": round(float(metrics.box.p[0]), 4) if len(metrics.box.p) else None,
        "recall": round(recall, 4),
        "gate": stage1_gate(map50, recall, args.min_map50, args.min_recall),
    }

    out_path = args.output or args.weights.parent / "eval_golden.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")

    print("\n===== Stage-1 Golden Eval =====")
    for k, v in result.items():
        print(f"  {k}: {v}")
    print(f"\n결과 JSON: {out_path}")
    if not result["gate"]["pass"]:
        print(f"게이트 FAIL: mAP@0.5 ≥ {args.min_map50} AND recall ≥ {args.min_recall}")
        sys.exit(1)


if __name__ == "__main__":
    main()
