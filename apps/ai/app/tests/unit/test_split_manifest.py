# apps/ai/app/tests/unit/test_split_manifest.py
import json
from datetime import datetime, timedelta
from pathlib import Path

import pytest

from training.data.make_split_manifest import build_manifest, split_external

AI_ROOT = Path(__file__).resolve().parents[3]  # apps/ai


def _items(n_col=12, per=40):
    out = []
    for c in range(n_col):
        t0 = datetime(2023, 8, 20, 9, 0, 0)
        for i in range(per):
            out.append({"image": f"/d/{c:03d}/{i}.jpg", "colony": f"{c:03d}", "device": "소비판촬영기" if c % 2 else "플레이트촬영기",
                        "ts": t0 + timedelta(seconds=4 * i if i % 5 else 900 * i), "has_varroa_adult": i % 7 == 0, "n_adult": 4, "source": "71667-val"})
    return out


def test_manifest_colony_disjoint():
    m = build_manifest(_items(), seed=42)
    g, a, b = (set(m["frozen_colonies"][k]) for k in ("golden", "cal_a", "cal_b"))
    assert not (g & a) and not (g & b) and not (a & b)
    trainval = {v["colony"] for v in m["images"].values() if v["split"] in ("train", "val")}
    assert not (trainval & (g | a | b))


def test_golden_dedupes_10min_bursts():
    m = build_manifest(_items(), seed=42)
    kept = [v for v in m["images"].values() if v["split"] == "golden"]
    by = {}
    for v in kept:
        by.setdefault((v["colony"], v["device"]), []).append(datetime.fromisoformat(v["ts"]))
    for ts in by.values():
        ts.sort()
        assert all((ts[i + 1] - ts[i]).total_seconds() >= 600 for i in range(len(ts) - 1))


def test_frozen_colonies_stable_when_superset_added():
    base = build_manifest(_items(), seed=42)["frozen_colonies"]
    more = _items() + [dict(i, image=i["image"].replace("/d/", "/e/"), source="71667-train") for i in _items(n_col=12, per=5)]
    again = build_manifest(more, seed=42, frozen=base)["frozen_colonies"]
    assert again == base


def _video_id(image: Path) -> str:
    return image.name.split(".MTS")[0]


def test_split_external_ev2_by_video_no_leak():
    frames = [3, 7, 12, 20, 5, 9]
    rows = []
    for v, n in enumerate(frames):
        for f in range(n):
            folder = "dataset_infested" if f % 2 else "dataset_free"  # 같은 영상이 두 폴더에 걸침
            rows.append({"source": "ev2", "image": Path(f"{folder}/{v}_0095{v}.MTS_frame{f}.png"), "split": "unsplit"})
    rows.append({"source": "varroadataset", "image": Path("test/videos/d/a.png"), "split": "test"})
    rows.append({"source": "varroadataset", "image": Path("train/videos/d/b.png"), "split": "train"})
    out = split_external(rows, seed=42)
    assert out[str(Path("test/videos/d/a.png"))] == "test"
    assert out[str(Path("train/videos/d/b.png"))] == "train"
    ev2 = [r for r in rows if r["source"] == "ev2"]
    sides: dict[str, set] = {}
    for r in ev2:
        sides.setdefault(_video_id(r["image"]), set()).add(out[str(r["image"])])
    assert all(len(s) == 1 for s in sides.values())
    assert {s for ss in sides.values() for s in ss} == {"train", "holdout"}
    held = sum(out[str(r["image"])] == "holdout" for r in ev2)
    assert held / len(ev2) >= 0.15
    assert split_external(rows, seed=42) == out  # 결정적


def test_committed_manifest_frozen_colonies_unchanged():
    manifest = AI_ROOT / "training" / "split_manifest.json"
    frozen = AI_ROOT / "training" / "data" / "frozen_colonies.json"
    if not (manifest.exists() and frozen.exists()):
        pytest.skip("split_manifest.json / frozen_colonies.json 미커밋 (71667 Validation 도착 전)")
    m = json.loads(manifest.read_text(encoding="utf-8"))
    assert m["frozen_colonies"] == json.loads(frozen.read_text(encoding="utf-8"))
