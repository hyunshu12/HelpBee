# apps/ai/app/tests/unit/test_eval_e2e.py
from pathlib import Path

import pandas as pd
import yaml

from app.services.vdi import VdiConfig
from training.eval_e2e import (
    build_pseudo_frames,
    frame_tiers,
    make_single2_data_yaml,
    tier_agreement,
    tier_confusion,
    trivial_baseline,
    true_tier,
    vdi_mae,
)


def _df():
    return pd.DataFrame([{"path": f"p{i}", "label": int(i < 60), "colony": "g1"} for i in range(1000)])  # 6% 양성


def test_pseudo_frames_hit_targets():
    frames = build_pseudo_frames(_df(), targets=(0, 5, 12), n_bees=300, n_frames=5, seed=0)
    assert len(frames) == 15 and all(len(f["labels"]) == 300 for f in frames)
    for f in frames:
        assert abs(sum(f["labels"]) / 3 - f["target"]) <= 0.5


def test_trivial_baseline_and_agreement():
    truth = ["low"] * 7 + ["elevated"] * 2 + ["high"]
    assert trivial_baseline(truth) == 0.7 and tier_agreement(truth, truth) == 1.0


def test_pseudo_frames_deterministic_and_labels_match_paths():
    a = build_pseudo_frames(_df(), targets=(5,), n_bees=100, n_frames=3, seed=7)
    b = build_pseudo_frames(_df(), targets=(5,), n_bees=100, n_frames=3, seed=7)
    assert a == b
    lab = dict(zip(_df().path, _df().label))
    assert all(lab[p] == y for f in a for p, y in zip(f["paths"], f["labels"]))


def test_true_tier_ignores_rogan_gladen_correction():
    cfg = VdiConfig(tau=0.5, tpr=0.9, fpr=0.02, corrected=True)
    # 참 5% 는 보정 없이 elevated. 보정(ra=(5-2)/0.88=3.4)이 끼면 결과가 달라지는 경계로 확인.
    assert true_tier(15, 300, cfg) == "elevated"
    assert true_tier(8, 300, cfg) == "low"  # 2.666.. → "2.7" low (보정 시 0.75 → low 이지만 raw 기준)
    assert true_tier(9, 300, cfg) == "elevated"  # 3.0 → elevated (보정하면 1.1 → low 로 틀어짐)


def test_frame_tiers_uses_platt_and_tau():
    cfg = VdiConfig(tau=0.5, tpr=0.9, fpr=0.0, corrected=False, platt=(1.0, 0.0))
    frames = [{"target": 0, "paths": ["a", "b"] * 50, "labels": [0] * 100},
              {"target": 12, "paths": ["c"] * 12 + ["a"] * 88, "labels": [1] * 12 + [0] * 88}]
    logits = {"a": -5.0, "b": -5.0, "c": 5.0}
    rows = frame_tiers(frames, logits, cfg)
    assert [r["pred_tier"] for r in rows] == ["low", "high"]
    assert [r["true_tier"] for r in rows] == ["low", "high"]
    assert rows[0]["vdi"] == 0.0
    conf = tier_confusion([r["true_tier"] for r in rows], [r["pred_tier"] for r in rows])
    assert conf["low"]["low"] == 1 and conf["high"]["high"] == 1 and conf["elevated"]["low"] == 0


def test_make_single2_data_yaml(tmp_path: Path):
    src = tmp_path / "stage1_all.yaml"
    src.write_text(yaml.safe_dump({"path": "/x", "train": "t.txt", "val": "v.txt", "nc": 1, "names": ["bee"],
                                   "label_root": "/labels"}), encoding="utf-8")
    out = make_single2_data_yaml(src, tmp_path / "baseline_single_all.yaml")
    d = yaml.safe_load(out.read_text(encoding="utf-8"))
    assert d["nc"] == 2 and d["names"] == ["bee_normal", "bee_varroa"]
    assert (d["path"], d["train"], d["val"], d["label_root"]) == ("/x", "t.txt", "v.txt", "/labels")


def test_vdi_mae_overall_and_by_target():
    rows = [{"target": 0, "n": 100, "k_true": 0, "vdi": 1.0},
            {"target": 0, "n": 100, "k_true": 0, "vdi": 0.0},
            {"target": 5, "n": 200, "k_true": 10, "vdi": 7.0},   # 참 5% → 오차 2
            {"target": 5, "n": 200, "k_true": 10, "vdi": 4.0}]   # 오차 1
    m = vdi_mae(rows)
    assert m["vdi_mae"] == (1 + 0 + 2 + 1) / 4
    assert m["vdi_mae_by_target"] == {"0": 0.5, "5": 1.5}


def test_pseudo_frames_clear_error_without_positives():
    import pytest

    from training.eval_e2e import build_pseudo_frames

    df = pd.DataFrame({"path": ["a", "b"], "label": [0, 0]})
    with pytest.raises(ValueError, match="양성 크롭 0개"):
        build_pseudo_frames(df, targets=(0, 5), n_bees=10, n_frames=1)
    assert len(build_pseudo_frames(df, targets=(0,), n_bees=10, n_frames=2)) == 2
