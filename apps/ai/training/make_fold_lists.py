"""split_manifest.json → Stage-1 학습 이미지 리스트 (colony 기준 2-fold + all).

Usage (apps/ai 에서):
    python -m training.make_fold_lists --manifest training/split_manifest.json \\
        --labels-root <aihub_to_yolo --manifest output>/labels/all --out training/lists

산출물 (training/lists/, gitignored):
    stage1_{A,B,all}_{train,val}.txt  — 한 줄 = 원본 이미지 절대경로 (정렬, 재실행 byte-identical)
    stage1_{A,B,all}.yaml             — path(절대)/train/val/nc=1/names=[bee]/label_root

fold 정의 (out-of-fold 크롭용, 스펙 §4): manifest split 이 train/val 인 이미지만 대상.
colony 를 sha1 안정 해시로 A/B 에 배정 (Python hash() 는 프로세스마다 랜덤이라 금지).
fold A 모델은 A colony 의 train 으로 학습·A colony 의 val 로 검증하고, B colony 이미지를 out-of-fold 예측한다
(B 는 반대). all = 전체 train/val.
라벨 파일이 없는 이미지(외부 소스 등)는 제외하고 개수를 보고한다 — 라벨 없는 이미지를 넣으면
Ultralytics 가 배경(음성)으로 학습하기 때문. 라벨 경로 규칙은 yolo_list_dataset.label_path_for.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import yaml

from training.data.yolo_list_dataset import label_path_for

FOLDS = ("A", "B")


def colony_fold(colony: str) -> str:
    return FOLDS[int(hashlib.sha1(str(colony).encode("utf-8")).hexdigest(), 16) % 2]


def make_fold_lists(manifest: Path, labels_root: Path, out: Path, max_skip_frac: float = 0.05) -> dict:
    m = json.loads(Path(manifest).read_text(encoding="utf-8"))
    labels_root = Path(labels_root).resolve()
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    lists: dict[str, list[str]] = {f"{f}_{s}": [] for f in (*FOLDS, "all") for s in ("train", "val")}
    skipped = 0
    for img, meta in sorted(m["images"].items()):
        split = meta.get("split")
        if split not in ("train", "val"):
            continue
        if not label_path_for(img, labels_root).exists():
            skipped += 1
            continue
        lists[f"all_{split}"].append(img)
        lists[f"{colony_fold(meta.get('colony'))}_{split}"].append(img)
    for key, items in lists.items():
        (out / f"stage1_{key}.txt").write_text("".join(f"{i}\n" for i in items), encoding="utf-8")
    for f in (*FOLDS, "all"):
        data = {"path": str(out.resolve()), "train": f"stage1_{f}_train.txt", "val": f"stage1_{f}_val.txt",
                "nc": 1, "names": ["bee"], "label_root": str(labels_root)}
        (out / f"stage1_{f}.yaml").write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False),
                                              encoding="utf-8")
    stats = {k: len(v) for k, v in lists.items()}
    stats["skipped_no_label"] = skipped
    n = skipped + len(lists["all_train"]) + len(lists["all_val"])
    if n and skipped / n > max_skip_frac:
        raise ValueError(f"라벨 없는 train/val 이미지 {skipped}/{n} > {max_skip_frac:.0%} — --labels-root 확인. "
                         "Validation+Training 을 함께 쓸 땐 두 aihub_to_yolo 변환이 같은 --output 에 써야 한다")
    return stats


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", type=Path, default=Path("training/split_manifest.json"))
    p.add_argument("--labels-root", type=Path, required=True)
    p.add_argument("--out", type=Path, default=Path("training/lists"))
    a = p.parse_args()
    try:
        print(make_fold_lists(a.manifest, a.labels_root, a.out))
    except ValueError as e:
        p.error(str(e))


if __name__ == "__main__":
    main()
