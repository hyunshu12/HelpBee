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
    """디듀프 키 = (colony, device, has_varroa_adult). 음성 10분, 양성 1분 창."""
    m = build_manifest(_items(), seed=42)
    kept = [v for v in m["images"].values() if v["split"] == "golden"]
    by = {}
    for v in kept:
        by.setdefault((v["colony"], v["device"], v["has_varroa_adult"]), []).append(datetime.fromisoformat(v["ts"]))
    assert any(k[2] for k in by) and any(not k[2] for k in by)
    for (_, _, pos), ts in by.items():
        ts.sort()
        gap = 60 if pos else 600
        assert all((ts[i + 1] - ts[i]).total_seconds() >= gap for i in range(len(ts) - 1))


def test_golden_positive_burst_keeps_one_per_minute():
    """양성 버스트(4초 간격 3분) → 1분 창이라 3~4장 유지 (10분 창이면 1장)."""
    items = []
    for c in range(12):
        t0 = datetime(2023, 8, 20, 9, 0, 0)
        for i in range(46):  # 0..180초
            items.append({"image": f"/d/{c:03d}/{i}.jpg", "colony": f"{c:03d}", "device": "소비판촬영기",
                          "ts": t0 + timedelta(seconds=4 * i), "has_varroa_adult": True, "n_adult": 3, "source": "71667-val"})
    m = build_manifest(items, seed=42)
    per_col: dict[str, int] = {}
    for v in m["images"].values():
        if v["split"] == "golden":
            per_col[v["colony"]] = per_col.get(v["colony"], 0) + 1
    assert per_col and all(3 <= n <= 4 for n in per_col.values())


def _varroa_items():
    """30 colony. 001/002/003 에 응애 대부분 (120/70/60), 나머지 0~5."""
    varroa = {0: 120, 1: 70, 2: 60, 3: 5, 4: 3, 5: 2}
    out = []
    for c in range(30):
        t0 = datetime(2023, 8, 20, 9, 0, 0)
        nv = varroa.get(c, 0)
        for i in range(200):
            out.append({"image": f"/d/{c:03d}/{i}.jpg", "colony": f"{c + 1:03d}", "device": "소비판촬영기",
                        "ts": t0 + timedelta(minutes=15 * i), "has_varroa_adult": i < nv, "n_adult": 4,
                        "source": "71667-val"})
    return out


def _varroa_by_split(m):
    out: dict[str, int] = {}
    for v in m["images"].values():
        if v["has_varroa_adult"]:
            out[v["split"]] = out.get(v["split"], 0) + 1
    return out


def test_varroa_aware_draw_meets_targets():
    items = _varroa_items()
    m = build_manifest(items, seed=42)
    fz = m["frozen_colonies"]
    assert "001" in fz["golden"]
    assert "002" in fz["cal_a"] + fz["cal_b"] and "003" in fz["cal_a"] + fz["cal_b"]
    raw = {}
    col_split = {c: s for s in ("golden", "cal_a", "cal_b") for c in fz[s]}
    for it in items:
        if it["has_varroa_adult"] and it["colony"] in col_split:
            raw[col_split[it["colony"]]] = raw.get(col_split[it["colony"]], 0) + 1
    assert raw["golden"] >= 100 and raw["cal_a"] >= 50 and raw["cal_b"] >= 50
    n_g, half = 3, 2  # max(3, round(30*.1)), max(1, round(30*.15)//2)
    assert len(fz["golden"]) == n_g and len(fz["cal_a"]) == half and len(fz["cal_b"]) == half
    g, a, b = (set(fz[k]) for k in ("golden", "cal_a", "cal_b"))
    assert not (g & a) and not (g & b) and not (a & b)
    assert build_manifest(items, seed=42)["frozen_colonies"] == fz  # 결정적


def test_varroa_aware_draw_unreachable_targets_takes_best():
    items = [dict(it, has_varroa_adult=it["has_varroa_adult"] and int(it["image"].split("/")[-1][:-4]) < 10)
             for it in _varroa_items()]  # 001~006 모두 응애 ≤10 → 목표 불가
    m = build_manifest(items, seed=42)
    fz = m["frozen_colonies"]
    held = set(fz["golden"]) | set(fz["cal_a"]) | set(fz["cal_b"])
    assert {"001", "002", "003"} <= held
    assert "001" in fz["golden"]


def test_holdout_share_cap_respected():
    items = _varroa_items()
    m = build_manifest(items, seed=42, max_holdout_share=0.1)  # 6000*0.1 = 600장 = 3 colony
    n_held = sum(v["split"] in ("golden", "cal_a", "cal_b", "dropped_dup") for v in m["images"].values())
    assert n_held <= 600


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


def test_main_prints_split_summary(tmp_path, monkeypatch, capsys):
    import training.data.make_split_manifest as msm

    monkeypatch.setattr(msm, "load_items_from_aihub", lambda roots, tags: _varroa_items())
    out, fz = tmp_path / "split_manifest.json", tmp_path / "frozen_colonies.json"
    assert msm.main(["--roots", str(tmp_path), "--tags", "71667-val", "--output", str(out),
                     "--frozen-colonies", str(fz), "--dedupe-min-pos", "2", "--golden-varroa-target", "50"]) == 0
    lines = [ln for ln in capsys.readouterr().out.splitlines() if ln.startswith("[split]")]
    splits = {ln.split()[1] for ln in lines}
    assert {"train", "val", "golden", "cal_a", "cal_b"} <= splits
    assert all("images=" in ln and "varroa=" in ln and "n_adult>0=" in ln for ln in lines)


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
