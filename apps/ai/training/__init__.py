"""HelpBee YOLO training package.

Entry points:
    python -m training.train --config training/configs/yolo.yaml
    python -m training.eval --weights runs/yolo/v0.1.0-baseline/weights/best.pt
    python -m training.data.aihub_to_yolo --source ... --output ...

See apps/ai/CLAUDE.md §8 for YOLO pipeline policy.
"""
