"""
YOLO 학습 진입점 — 이어 학습(resume) 지원.

사용 시나리오:
    1) 첫 학습 (5,000장):
        python -m training.train --config training/configs/yolo.yaml --name v0.1.0-baseline

    2) 같은 데이터 / 같은 run 이어 학습 (중단 후 재개):
        python -m training.train --config training/configs/yolo.yaml \\
            --resume runs/yolo/v0.1.0-baseline/weights/last.pt
       → optimizer state, lr schedule, epoch counter까지 그대로 이어감

    3) 데이터 추가 후 다시 학습 (5k → 50k 확장):
        python -m training.train --config training/configs/yolo.yaml \\
            --pretrained runs/yolo/v0.1.0-baseline/weights/best.pt \\
            --name v0.1.1-50k
       → weight만 가져오고 optimizer는 새로 시작. epoch 0부터.
       → 데이터셋 분포가 달라졌으므로 fresh schedule이 옳음

    4) Hyperparameter 오버라이드:
        python -m training.train --config ... --epochs 50 --batch 8 --imgsz 960

Overfit 감지:
    - patience (yolo.yaml) 만큼 val mAP 정체 시 자동 종료 (Ultralytics early stopping)
    - W&B 로그에서 train_loss vs val_loss 발산 모니터링
    - close_mosaic 마지막 N epoch에서 mosaic off → val 회복 자동
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

import yaml

logger = logging.getLogger(__name__)


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

    p = argparse.ArgumentParser()
    p.add_argument("--config", type=Path, required=True, help="training/configs/yolo.yaml 경로")
    p.add_argument(
        "--resume",
        type=Path,
        default=None,
        help="last.pt 경로. optimizer state까지 정확히 이어 학습",
    )
    p.add_argument(
        "--pretrained",
        type=Path,
        default=None,
        help="weight만 가져와 새 run 시작 (resume 아님). 데이터 추가 시 권장",
    )
    p.add_argument("--epochs", type=int, default=None, help="config 오버라이드")
    p.add_argument("--batch", type=int, default=None)
    p.add_argument("--imgsz", type=int, default=None)
    p.add_argument("--device", type=str, default=None, help="'0' / 'cpu' / '0,1'")
    p.add_argument("--name", type=str, default=None, help="run 이름 오버라이드")
    p.add_argument("--workers", type=int, default=None)
    args = p.parse_args()

    if args.resume and args.pretrained:
        sys.exit("--resume 과 --pretrained 는 동시 사용 불가. 둘 중 하나만.")

    cfg = yaml.safe_load(args.config.read_text())

    # CLI 오버라이드
    for key in ("epochs", "batch", "imgsz", "device", "name", "workers"):
        v = getattr(args, key)
        if v is not None:
            cfg[key] = v

    # ultralytics는 lazy import (로깅 깔끔)
    from ultralytics import YOLO  # type: ignore

    if args.resume:
        if not args.resume.exists():
            sys.exit(f"resume 경로 없음: {args.resume}")
        logger.info(f"=== RESUME from {args.resume} (optimizer state 포함) ===")
        model = YOLO(str(args.resume))
        cfg["resume"] = True
    elif args.pretrained:
        if not args.pretrained.exists():
            sys.exit(f"pretrained 경로 없음: {args.pretrained}")
        logger.info(f"=== PRETRAINED weights from {args.pretrained} (fresh run) ===")
        model = YOLO(str(args.pretrained))
        # 새 run으로 시작 — name 충돌 방지 권장
        if args.name is None:
            logger.warning(
                "데이터 추가 학습 시 --name 으로 새 run 이름 지정 권장 (충돌 방지)"
            )
    else:
        model_arg = cfg.pop("model", "yolo11s.pt")
        pretrained = cfg.pop("pretrained", None)
        logger.info(f"=== FRESH train: model={model_arg}, pretrained={pretrained} ===")
        # 모델 yaml + ImageNet pretrained 결합 — Ultralytics 패턴:
        #   YOLO(model_yaml).load(pretrained_pt)
        model = YOLO(model_arg)
        if pretrained:
            try:
                model.load(pretrained)
                logger.info(f"loaded pretrained weights: {pretrained}")
            except Exception as e:
                logger.warning(f"pretrained load 실패 (무시): {e}")

    # 'model'/'pretrained' 키는 train()에 전달하지 않음 (이미 인스턴스에 반영)
    cfg.pop("model", None)
    cfg.pop("pretrained", None)

    logger.info(f"train kwargs (요약): epochs={cfg.get('epochs')}, "
                f"batch={cfg.get('batch')}, imgsz={cfg.get('imgsz')}, "
                f"name={cfg.get('name')}")

    results = model.train(**cfg)
    save_dir = getattr(results, "save_dir", None) or model.trainer.save_dir
    print(f"\n[OK] best.pt: {save_dir}/weights/best.pt")
    print(f"[OK] last.pt: {save_dir}/weights/last.pt")


if __name__ == "__main__":
    main()
