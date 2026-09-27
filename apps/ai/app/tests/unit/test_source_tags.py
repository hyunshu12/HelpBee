# apps/ai/app/tests/unit/test_source_tags.py
"""최종 리뷰 C1 — manifest 태그(`71667-val`)가 tasks.py split → manifest → crops.csv → select_splits 까지
그대로 흘러도 71667 로 인식돼야 한다 (이전엔 리터럴 "71667" 비교라 cal/val 이 통째로 사라졌다)."""
import csv
import sys
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd

from training.data.make_crops import CSV_COLUMNS, count_crop, row_71667
from training.data.make_split_manifest import build_manifest, is_71667, source_group
from training.train_stage2 import read_crops, select_splits

AI_ROOT = Path(__file__).resolve().parents[3]  # apps/ai


def _tasks_split_tag(monkeypatch) -> str:
    monkeypatch.syspath_prepend(str(AI_ROOT))
    sys.modules.pop("tasks", None)
    import tasks

    seen: list[list[str]] = []
    monkeypatch.setattr(tasks, "_run", lambda cmd: seen.append(cmd) or 0)
    tasks.split([])
    cmd = seen[0]
    return cmd[cmd.index("--tags") + 1]


def test_is_71667_prefix():
    assert is_71667("71667") and is_71667("71667-val") and is_71667("71667-train")
    assert not is_71667("varroadataset") and not is_71667("ev2")
    assert source_group("71667-train") == "71667" and source_group("ev2") == "ev2"


def test_tasks_split_tag_flows_through_crops_csv_to_select_splits(tmp_path, monkeypatch):
    tag = _tasks_split_tag(monkeypatch)
    assert tag == "71667-val"
    items = []
    for c in range(12):
        t0 = datetime(2023, 8, 20, 9, 0, 0)
        for i in range(20):
            items.append({"image": f"/d/{c:03d}/{i}.jpg", "colony": f"{c:03d}", "device": "소비판촬영기",
                          "ts": t0 + timedelta(minutes=15 * i), "has_varroa_adult": i % 3 == 0, "n_adult": 3,
                          "source": tag})
    m = build_manifest(items, seed=42)
    counter: dict = {}
    with (tmp_path / "crops.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(CSV_COLUMNS)
        for k, (image, meta) in enumerate(sorted(m["images"].items())):
            if meta["split"] == "dropped_dup":
                continue
            label = k % 2
            row = row_71667(f"{meta['split']}/{label}/{k}.png", label, meta, 5 if label else 4, image, 100, 120)
            assert len(row) == len(CSV_COLUMNS)
            w.writerow(row)
            count_crop(counter, meta["source"], meta["split"], label)
    rows = read_crops(tmp_path)
    assert {r["source"] for r in rows} == {"71667-val"}  # 태그는 CSV 에 그대로 보존
    sp = select_splits(rows)
    n_by_split = {s: sum(r["split"] == s for r in rows) for s in ("train", "val", "cal_a", "cal_b")}
    for s in ("train", "val", "cal_a", "cal_b"):
        assert n_by_split[s] > 0
        assert len(sp[s]) == n_by_split[s]  # 하나도 안 빠짐
    assert all(k.startswith("71667/") for k in counter)  # stats 집계는 71667 한 그룹


def test_eval_e2e_frame_crops_keeps_tagged_71667_only():
    from training.eval_e2e import frame_crops

    rows = [{"split": "golden", "source": "71667-val", "label": "1", "path": "a"},
            {"split": "golden", "source": "71667-train", "label": "0", "path": "b"},
            {"split": "golden", "source": "ev2", "label": "0", "path": "c"},
            {"split": "val", "source": "71667-val", "label": "0", "path": "d"}]
    df = frame_crops(rows, "golden")
    assert list(df.path) == ["a", "b"] and df.label.tolist() == [1, 0]


def test_eval_stage2_by_source_groups_71667_tags():
    import numpy as np
    import pytest

    pytest.importorskip("sklearn")
    from training.eval_stage2 import build_report

    n = 40
    df = pd.DataFrame({"source": ["71667-val"] * 10 + ["71667-train"] * 10 + ["ev2"] * 20,
                       "device": ["d"] * n, "colony": ["c"] * n, "native_w": [100.0] * n,
                       "native_h": np.linspace(90, 130, n), "label": [0, 1] * (n // 2)})
    rng = np.random.default_rng(0)
    rep = build_report(df, rng.normal(0, 1, n), rng.normal(0, 1, (n, 8)), 0.5, (1.0, 0.0))
    assert set(rep["by_source"]) == {"71667", "ev2"}
