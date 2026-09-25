# apps/ai/app/tests/unit/test_eval_stage2.py
import numpy as np
import pytest
import pandas as pd

from training.eval_stage2 import (by_group, lodo_probe, overall_metrics, recall_by_size_tercile, size_only_auroc,
                                  size_only_auroc_by_source, source_probe_acc)


def test_size_only_auroc_detects_size_shortcut_and_chance_without_it():
    rng = np.random.default_rng(0)
    y = np.array([0, 1] * 200)
    w = np.where(y == 1, 300, 150) + rng.normal(0, 10, len(y))
    h = w * 1.1
    assert size_only_auroc(w, h, y) > 0.95
    w2 = rng.normal(200, 30, len(y))
    assert abs(size_only_auroc(w2, w2 * 1.1, y) - 0.5) < 0.12


def test_source_probe_acc_high_when_embedding_encodes_source():
    rng = np.random.default_rng(1)
    src = np.array(["71667", "vd2"] * 100)
    emb = rng.normal(0, 1, (200, 16))
    emb[:, 0] += np.where(src == "vd2", 4.0, -4.0)
    assert source_probe_acc(emb, src) > 0.95
    assert source_probe_acc(rng.normal(0, 1, (200, 16)), src) < 0.7


def test_by_group_recall_specificity():
    df = pd.DataFrame({"device": ["a", "a", "a", "b", "b", "b"]})
    y = np.array([1, 1, 0, 1, 0, 0])
    p = np.array([0.9, 0.2, 0.1, 0.8, 0.7, 0.1])
    g = by_group(df, "device", p, y, tau=0.5)
    assert g["a"] == {"recall": 0.5, "specificity": 1.0, "n_pos": 2, "n_neg": 1}
    assert g["b"] == {"recall": 1.0, "specificity": 0.5, "n_pos": 1, "n_neg": 2}


def test_by_group_missing_class_is_none():
    g = by_group(pd.DataFrame({"colony": ["c"]}), "colony", np.array([0.1]), np.array([0]), tau=0.5)
    assert g["c"]["recall"] is None and g["c"]["specificity"] == 1.0


def test_overall_metrics_keys_and_values():
    y = np.array([0, 0, 1, 1])
    p = np.array([0.1, 0.4, 0.6, 0.9])
    m = overall_metrics(p, y, tau=0.5)
    assert set(m) == {"recall", "specificity", "auroc", "ece"}
    assert m["recall"] == 1.0 and m["specificity"] == 1.0 and m["auroc"] == 1.0


def test_lodo_probe_reports_each_device():
    rng = np.random.default_rng(2)
    dev = np.array(["d1", "d2", "d3"] * 60)
    y = np.array([0, 1] * 90)
    emb = rng.normal(0, 1, (180, 8))
    emb[:, 0] += np.where(y == 1, 3.0, -3.0)
    r = lodo_probe(emb, y, dev)
    assert set(r) == {"d1", "d2", "d3"}
    assert all(v["auroc"] > 0.9 and v["n"] == 60 for v in r.values())


def test_size_only_auroc_by_source_per_group_and_skips_small_or_single_class():
    rng = np.random.default_rng(7)
    y1 = np.array([0, 1] * 100)
    w1 = np.where(y1 == 1, 300, 150) + rng.normal(0, 10, len(y1))  # 71667: 크기 지름길 있음
    y2 = np.array([0, 1] * 100)
    w2 = rng.normal(200, 30, len(y2))  # varroadataset: 없음
    y3 = np.array([0, 1] * 5)  # ev2: 10행 < 20 → 생략
    w3 = rng.normal(200, 30, len(y3))
    y4 = np.zeros(30, int)  # extra: 단일 클래스 → 생략
    w4 = rng.normal(200, 30, len(y4))
    w = np.r_[w1, w2, w3, w4]
    y = np.r_[y1, y2, y3, y4]
    src = ["71667-val"] * 100 + ["71667-train"] * 100 + ["varroadataset"] * 200 + ["ev2"] * 10 + ["extra"] * 30
    r = size_only_auroc_by_source(w, w * 1.1, y, src)
    assert set(r) == {"71667", "varroadataset"}
    assert r["71667"] > 0.95 and abs(r["varroadataset"] - 0.5) < 0.15


def test_recall_by_size_tercile_per_source():
    n = 60
    size = np.tile(np.arange(1, 31, dtype=float), 2)  # 1..30 × 2
    y = np.r_[np.ones(30), np.zeros(30)].astype(int)
    # 양성: 작은 벌(≤10)은 놓치고 큰 벌은 잡는다
    p = np.where((y == 1) & (size > 10), 0.9, 0.1)
    src = ["71667-val"] * n
    # 작은 소스(행 < 20) 는 생략
    size2, y2, p2 = np.r_[size, [5.0] * 10], np.r_[y, [1] * 10], np.r_[p, [0.9] * 10]
    src2 = src + ["ev2"] * 10
    r = recall_by_size_tercile(size2, size2 * 0.5, y2, p2, 0.5, src2)
    assert set(r) == {"71667"}  # 71667-val → 71667 그룹, ev2(10행) 생략
    t = r["71667"]["terciles"]
    assert [b["n_pos"] for b in t] == [10, 10, 10]
    assert [b["recall"] for b in t] == [0.0, 1.0, 1.0]
    assert r["71667"]["edges"][0] == pytest.approx(10.666, abs=0.01)
    assert t[0]["size_lo"] == 1.0 and t[2]["size_hi"] == 30.0
    # max(native_w, native_h) 사용: h 가 더 크면 h 기준
    r2 = recall_by_size_tercile(size * 0.5, size, y, p, 0.5, src)
    assert [b["recall"] for b in r2["71667"]["terciles"]] == [0.0, 1.0, 1.0]
