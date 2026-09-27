# apps/ai/app/tests/unit/test_make_fold_lists.py
import json
from pathlib import Path

import yaml

from training.make_fold_lists import colony_fold, make_fold_lists


def _img(tmp_path, colony, i):
    return tmp_path / "src" / colony / f"{colony}_img{i}.jpg"


def _fake(tmp_path):
    labels = tmp_path / "labels/all"
    labels.mkdir(parents=True)
    images = {}
    colonies = [f"{n:03d}" for n in range(1, 9)]
    for c in colonies:
        for i, split in enumerate(["train", "train", "val", "golden", "cal_a", "dropped_dup"]):
            p = _img(tmp_path, c, i)
            images[str(p)] = {"split": split, "colony": c, "device": "d", "ts": "t",
                              "source": "71667", "has_varroa_adult": False, "n_adult": 1}
            (labels / f"{c}_{p.stem}.txt").write_text("0 0.5 0.5 0.1 0.1\n", encoding="utf-8")
    # 라벨 없는 train 이미지 (외부 소스 등) → 제외
    ext = tmp_path / "ext/x.jpg"
    images[str(ext)] = {"split": "train", "colony": "ext", "source": "varroa_dataset"}
    mf = tmp_path / "split_manifest.json"
    mf.write_text(json.dumps({"seed": 42, "frozen_colonies": {}, "images": images}), encoding="utf-8")
    return mf, labels, colonies


def test_colony_fold_is_stable():
    assert colony_fold("007") == colony_fold("007")
    assert {colony_fold(f"{n:03d}") for n in range(1, 30)} == {"A", "B"}


def test_make_fold_lists(tmp_path):
    mf, labels, colonies = _fake(tmp_path)
    out = tmp_path / "lists"
    stats = make_fold_lists(mf, labels, out)
    read = lambda n: [l for l in (out / n).read_text(encoding="utf-8").splitlines() if l]
    all_tr, all_va = read("stage1_all_train.txt"), read("stage1_all_val.txt")
    assert len(all_tr) == 2 * len(colonies) and len(all_va) == len(colonies)
    assert stats["skipped_no_label"] == 1
    for f in ("A", "B"):
        tr = read(f"stage1_{f}_train.txt")
        for line in tr + read(f"stage1_{f}_val.txt"):
            assert colony_fold(Path(line).parent.name) == f
        y = yaml.safe_load((out / f"stage1_{f}.yaml").read_text(encoding="utf-8"))
        assert y["nc"] == 1 and y["names"] == ["bee"] and y["label_root"] == str(labels.resolve())
        assert Path(y["path"]).is_absolute() and y["train"] == f"stage1_{f}_train.txt"
    a = set(read("stage1_A_train.txt")) | set(read("stage1_A_val.txt"))
    b = set(read("stage1_B_train.txt")) | set(read("stage1_B_val.txt"))
    assert not (a & b) and a | b == set(all_tr) | set(all_va)
    # 재실행 byte-identical
    before = (out / "stage1_A_train.txt").read_bytes()
    make_fold_lists(mf, labels, out)
    assert (out / "stage1_A_train.txt").read_bytes() == before


def test_make_fold_lists_fails_when_most_labels_missing(tmp_path):
    import pytest

    mf, labels, _ = _fake(tmp_path)
    empty = tmp_path / "wrong_labels"
    empty.mkdir()
    with pytest.raises(ValueError, match="같은 --output"):
        make_fold_lists(mf, empty, tmp_path / "lists")


def test_make_fold_lists_ignores_larvae_only_images(tmp_path):
    """n_adult==0 이미지는 라벨이 없어도 '누락'으로 세지 않는다 (71667 Validation 의 70% 가 유충 전용)."""
    import json
    mf, labels, _ = _fake(tmp_path)
    m = json.loads(mf.read_text(encoding="utf-8"))
    for i in range(40):
        m["images"][str(tmp_path / f"larvae_{i}.jpg")] = {"split": "train", "colony": "L", "device": "d",
                                                           "ts": "2023-08-20T09:00:00", "source": "71667-val",
                                                           "has_varroa_adult": False, "n_adult": 0}
    mf.write_text(json.dumps(m), encoding="utf-8")
    stats = make_fold_lists(mf, labels, tmp_path / "lists")   # 예외 없어야 한다
    assert stats["skipped_no_label"] == 1

