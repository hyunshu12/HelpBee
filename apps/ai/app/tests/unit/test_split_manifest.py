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


# ---- 최종 리뷰 I3: 동결 강제 / I4: 이미지 누락 집계 ----

def _write_tree(root: Path, n: int, n_missing: int) -> None:
    """가짜 71667 트리 — 01.원천데이터/02.라벨링데이터 형제. 앞 n_missing 개는 이미지 없음."""
    for i in range(n):
        lab = root / "02.라벨링데이터" / "성충" / "성충_응애" / f"{i % 12:03d}"
        img = root / "01.원천데이터" / "성충" / "성충_응애" / f"{i % 12:03d}"
        lab.mkdir(parents=True, exist_ok=True)
        img.mkdir(parents=True, exist_ok=True)
        fn = f"C_{i:04d}.jpg"
        d = {"image": {"width": 1920, "height": 1080, "filename": fn},
             "annotations": [{"category_id": 5 if i % 3 == 0 else 4, "bbox": [0, 0, 10, 10], "area": 100}],
             "collection": {"device": "소비판촬영기", "datetime": f"202308{10 + i // 100:02d}_{9 + (i % 100) // 10:02d}{i % 10:02d}00_001"},
             "colony": {"id": f"{i % 12:03d}"}}
        (lab / f"C_{i:04d}.json").write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")
        if i >= n_missing:
            (img / fn).write_bytes(b"x")


def test_load_items_counts_missing_and_fails_over_5pct(tmp_path, capsys):
    from training.data.aihub_to_yolo import MissingImagesError
    from training.data.make_split_manifest import load_items_from_aihub

    ok = tmp_path / "ok"
    _write_tree(ok, 100, 3)  # 3% 누락 — 허용, 로그
    items = load_items_from_aihub([ok], ["71667-val"])
    assert len(items) == 97
    assert "missing_image=3" in capsys.readouterr().out
    bad = tmp_path / "bad"
    _write_tree(bad, 100, 10)  # 10% 누락 — 레이아웃 오류
    with pytest.raises(MissingImagesError):
        load_items_from_aihub([bad], ["71667-val"])


def test_collect_samples_fails_over_5pct_missing(tmp_path):
    from training.data.aihub_to_yolo import MissingImagesError, collect_samples

    _write_tree(tmp_path / "ok", 40, 1)
    assert len(collect_samples(tmp_path / "ok", mapping="adult1")) == 39
    _write_tree(tmp_path / "bad", 40, 10)
    with pytest.raises(MissingImagesError):
        collect_samples(tmp_path / "bad", mapping="adult1")


def test_main_refuses_to_refreeze_without_flag(tmp_path, monkeypatch):
    import training.data.make_split_manifest as msm

    monkeypatch.setattr(msm, "load_items_from_aihub", lambda roots, tags: _items())
    out, fz = tmp_path / "split_manifest.json", tmp_path / "frozen_colonies.json"
    base = ["--roots", str(tmp_path), "--tags", "71667-val", "--output", str(out), "--frozen-colonies", str(fz)]
    assert msm.main(base) == 0  # 동결 파일 없음 → 최초 생성
    first = json.loads(fz.read_text(encoding="utf-8"))
    assert json.loads(out.read_text(encoding="utf-8"))["frozen_colonies"] == first

    with pytest.raises(SystemExit) as e:  # 동결 파일 있음 + 플래그 없음 → 거부
        msm.main(base + ["--seed", "7"])
    assert e.value.code == 2
    assert json.loads(fz.read_text(encoding="utf-8")) == first  # 안 바뀜

    assert msm.main(base + ["--seed", "7", "--frozen", str(out)]) == 0  # --frozen → 동결 유지
    assert json.loads(fz.read_text(encoding="utf-8")) == first
    assert json.loads(out.read_text(encoding="utf-8"))["frozen_colonies"] == first

    other = tmp_path / "other.json"  # 커밋 파일과 다른 frozen 입력 → 거부
    other.write_text(json.dumps({"frozen_colonies": {"golden": ["x"], "cal_a": [], "cal_b": []}}), encoding="utf-8")
    with pytest.raises(SystemExit):
        msm.main(base + ["--frozen", str(other)])

    assert msm.main(base + ["--seed", "7", "--refreeze"]) == 0  # 명시적 재동결만 허용
