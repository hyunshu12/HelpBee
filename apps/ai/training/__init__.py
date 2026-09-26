"""HelpBee YOLO training package.

Entry points:
    python -m training.train --config training/configs/yolo.yaml
    python -m training.eval --weights training/runs/yolo/v0.2.0-stage1/weights/best.pt \\
        --golden training/golden.json --label-root <aihub_to_yolo --mapping adult1 --manifest 산출>/labels/all
    python -m training.data.aihub_to_yolo --source ... --output ...

See apps/ai/CLAUDE.md §8 for YOLO pipeline policy.
"""
