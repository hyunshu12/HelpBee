# apps/ai/app/tests/unit/test_refreeze_splits.py
"""홀드아웃 재동결 도구 (training/data/refreeze_splits.py) — 순수 테스트 (합성 manifest + crops.csv)."""
import csv
import io
import json
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

import pytest

from training.data.make_split_manifest import build_manifest
from training.data.refreeze_splits import (BACKUP_SUFFIX, RefreezeError, crops_counts, format_count_table, main,
                                           manifest_counts, reassign_crops, reassign_manifest, validate_refreeze)

AI_ROOT = Path(__file__).resolve().parents[3]  # apps/ai
OLD = {"golden": ["001"], "cal_a": ["002"], "cal_b": ["010"]}
NEW = {"golden": ["001"], "cal_a": ["002", "008"], "cal_b": ["010", "003"]}
HEADER = ["path", "label", "source", "colony", "device", "split", "native_w", "native_h", "cat71667", "image",
          "varroa_visible", "ext_box"]


def _img(split, colony, source="71667-val", varroa=False):
    return {"split": split, "colony": colony, "device": "소비판촬영기", "ts": "2023-08-20T09:00:00",
            "source": source, "has_varroa_adult": varroa, "n_adult": 3}


def _manifest():
    images = {
        "/d/001/a.jpg": _img("golden", "001", varroa=True),
        "/d/001/b.jpg": _img("dropped_dup", "001"),
        "/d/002/a.jpg": _img("cal_a", "002", varroa=True),
        "/d/010/a.jpg": _img("cal_b", "010"),
        "/d/008/a.jpg": _img("train", "008", "71667-train", varroa=True),
        "/d/008/b.jpg": _img("val", "008"),
        "/d/003/a.jpg": _img("train", "003"),
        "/d/005/a.jpg": _img("train", "005"),  # 새 맵에 없음 → 그대로
        "/d/005/b.jpg": _img("val", "005"),
    }
    return {"seed": 42, "frozen_colonies": OLD, "images": images}


def _crop_rows():
    rows = [HEADER]
    for i, (label, src, col, split) in enumerate([
        (1, "71667-val", "001", "golden"), (0, "71667-val", "002", "cal_a"), (1, "71667-val", "002", "cal_a"),
        (0, "71667-val", "010", "cal_b"), (1, "71667-train", "008", "train"), (0, "71667-val", "008", "val"),
        (0, "71667-val", "003", "train"), (0, "71667-val", "005", "train"), (1, "71667-val", "005", "val"),
        (1, "varroadataset", "", "train"), (0, "ev2", "", "holdout"), (1, "varroadataset", "", "val"),
    ]):
        rows.append([f"{split}/{label}/c{i}.png", str(label), src, col, "소비판촬영기", split, "300", "280", "5",
                     f"D:\\data\\{i}.jpg", "", "0.1 0.2 0.3 0.4" if src == "ev2" else ""])
    return rows


def _write_csv(path: Path, rows, newline="\r\n", bom=False):
    buf = io.StringIO(newline="")
    csv.writer(buf, lineterminator=newline).writerows(rows)
    path.write_bytes((b"\xef\xbb\xbf" if bom else b"") + buf.getvalue().encode("utf-8"))


def _read_csv(path: Path):
    raw = path.read_bytes()
    text = raw[3:].decode("utf-8") if raw.startswith(b"\xef\xbb\xbf") else raw.decode("utf-8")
    return list(csv.reader(io.StringIO(text, newline="")))


# ── 순수 함수 ────────────────────────────────────────────────────────────────
def test_reassign_manifest_moves_only_listed_71667_colonies():
    m = _manifest()
    m2, n = reassign_manifest(m, NEW)
    s = {k: v["split"] for k, v in m2["images"].items()}
    assert s["/d/008/a.jpg"] == "cal_a" and s["/d/008/b.jpg"] == "cal_a"  # train·val 모두 cal 로
    assert s["/d/003/a.jpg"] == "cal_b"
    assert s["/d/001/a.jpg"] == "golden" and s["/d/001/b.jpg"] == "dropped_dup"  # golden 불변
    assert s["/d/002/a.jpg"] == "cal_a" and s["/d/010/a.jpg"] == "cal_b"
    assert s["/d/005/a.jpg"] == "train" and s["/d/005/b.jpg"] == "val"  # 새 맵에 없음 → 그대로
    assert n == 3
    assert m2["frozen_colonies"] == NEW
    assert m["images"]["/d/008/a.jpg"]["split"] == "train" and m["frozen_colonies"] == OLD  # 원본 불변
    # split 말고 다른 필드는 그대로
    assert {k: {kk: vv for kk, vv in v.items() if kk != "split"} for k, v in m2["images"].items()} == \
        {k: {kk: vv for kk, vv in v.items() if kk != "split"} for k, v in m["images"].items()}


def test_reassign_manifest_leaves_external_sources():
    m = _manifest()
    m["images"]["/ext/x.png"] = _img("train", "008", source="varroadataset")
    m2, _ = reassign_manifest(m, NEW)
    assert m2["images"]["/ext/x.png"]["split"] == "train"


def test_reassign_is_idempotent():
    m2, _ = reassign_manifest(_manifest(), NEW)
    m3, n = reassign_manifest(m2, NEW)
    assert n == 0 and m3 == m2


@pytest.mark.parametrize("new, msg", [
    ({"golden": ["001", "005"], "cal_a": ["002"], "cal_b": ["010"]}, "golden"),
    ({"golden": ["001"], "cal_a": ["008"], "cal_b": ["010"]}, "002"),  # 이전 cal_a colony 누락
    ({"golden": ["001"], "cal_a": ["002", "999"], "cal_b": ["010"]}, "999"),  # 모르는 colony
    ({"golden": ["001"], "cal_a": ["002", "010"], "cal_b": ["010"]}, "중복"),
    ({"golden": ["001"], "cal_a": ["002"]}, "키"),
])
def test_validate_refreeze_rejects(new, msg):
    with pytest.raises(RefreezeError, match=msg):
        validate_refreeze(OLD, new, {"001", "002", "003", "005", "008", "010"})


def test_validate_refreeze_accepts_superset():
    validate_refreeze(OLD, NEW, {"001", "002", "003", "005", "008", "010"})
    validate_refreeze(NEW, NEW, {"001", "002", "003", "005", "008", "010"})  # 이미 재동결 → 통과


def test_reassign_crops_split_column_only():
    rows = _crop_rows()
    out, n = reassign_crops(rows, NEW)
    assert n == 3  # 008 train·val → cal_a, 003 train → cal_b
    assert out[0] == HEADER
    i = HEADER.index("split")
    by = {(r[3], r[2], r[5]) for r in out[1:]}
    assert ("008", "71667-train", "cal_a") in by and ("008", "71667-val", "cal_a") in by
    assert ("003", "71667-val", "cal_b") in by
    for a, b in zip(rows[1:], out[1:]):
        assert a[:i] + a[i + 1:] == b[:i] + b[i + 1:]  # split 외 열 불변 (path 포함)
        if a[2] in ("varroadataset", "ev2"):
            assert a == b
    assert rows[5][i] == "train"  # 원본 불변


def test_reassign_crops_rejects_dropped_holdout_and_golden_move():
    with pytest.raises(RefreezeError, match="002"):
        reassign_crops(_crop_rows(), {"golden": ["001"], "cal_a": ["008"], "cal_b": ["010"]})
    rows = _crop_rows()
    rows[1][HEADER.index("split")] = "train"  # golden colony 크롭이 train 이면 오류
    with pytest.raises(RefreezeError, match="golden"):
        reassign_crops(rows, NEW)


def test_count_tables():
    before, after = crops_counts(_crop_rows()), crops_counts(reassign_crops(_crop_rows(), NEW)[0])
    assert before["train"] == {"crops": 4, "pos": 2, "neg": 2}
    assert after["train"] == {"crops": 2, "pos": 1, "neg": 1}  # 008·003 train 크롭이 빠짐, 외부·005 남음
    assert after["cal_a"] == {"crops": 4, "pos": 2, "neg": 2} and after["cal_b"] == {"crops": 2, "pos": 0, "neg": 2}
    lines = format_count_table(before, after, ("crops", "pos", "neg"), "crops.csv")
    assert any(ln.split()[1] == "cal_a" and "2→4 (+2)" in ln for ln in lines)
    assert any(ln.split()[1] == "holdout" for ln in lines)  # 순서 밖 split 도 표에
    mc = manifest_counts(reassign_manifest(_manifest(), NEW)[0])
    assert mc["cal_a"] == {"images": 3, "varroa": 2} and mc["train"] == {"images": 1, "varroa": 0}


def test_refreeze_matches_build_manifest_with_new_frozen():
    """재동결 결과 = make_split_manifest --frozen <새 맵> 으로 처음부터 만든 manifest (cal colony 디듀프 없음)."""
    items = []
    t0 = datetime(2023, 8, 20, 9, 0, 0)
    for c in range(8):
        for i in range(20):
            items.append({"image": f"/d/{c:03d}/{i}.jpg", "colony": f"{c:03d}", "device": "소비판촬영기",
                          "ts": t0 + timedelta(seconds=30 * i), "has_varroa_adult": i % 5 == 0, "n_adult": 2,
                          "source": "71667-val"})
    old = {"golden": ["000"], "cal_a": ["001"], "cal_b": ["002"]}
    new = {"golden": ["000"], "cal_a": ["001", "004"], "cal_b": ["002", "006"]}
    m_old = build_manifest(items, 42, frozen=old)
    refrozen, n = reassign_manifest(m_old, new)
    assert n == 40
    assert refrozen == build_manifest(items, 42, frozen=new)


# ── CLI ──────────────────────────────────────────────────────────────────────
def _setup(tmp_path, bom=False):
    mf, fz, cc = tmp_path / "split_manifest.json", tmp_path / "frozen.json", tmp_path / "crops.csv"
    mf.write_bytes(json.dumps(_manifest(), ensure_ascii=False, indent=1).replace("\n", "\r\n").encode("utf-8"))
    fz.write_text(json.dumps(NEW), encoding="utf-8")
    _write_csv(cc, _crop_rows(), bom=bom)
    return mf, fz, cc


def test_cli_requires_refreeze_flag(tmp_path):
    mf, fz, cc = _setup(tmp_path)
    before = (mf.read_bytes(), cc.read_bytes())
    with pytest.raises(SystemExit) as e:
        main(["--frozen", str(fz), "--manifest", str(mf), "--crops-csv", str(cc)])
    assert e.value.code == 2
    assert (mf.read_bytes(), cc.read_bytes()) == before
    assert not Path(str(cc) + BACKUP_SUFFIX).exists()


def test_cli_dry_run_writes_nothing(tmp_path, capsys):
    mf, fz, cc = _setup(tmp_path)
    before = (mf.read_bytes(), cc.read_bytes())
    assert main(["--frozen", str(fz), "--manifest", str(mf), "--crops-csv", str(cc), "--dry-run"]) == 0
    out = capsys.readouterr().out
    assert "[manifest]" in out and "[crops.csv]" in out and "--dry-run" in out
    assert (mf.read_bytes(), cc.read_bytes()) == before


@pytest.mark.parametrize("bom", [False, True])
def test_cli_refreeze_writes_manifest_csv_and_backup(tmp_path, capsys, bom):
    mf, fz, cc = _setup(tmp_path, bom=bom)
    orig_csv = cc.read_bytes()
    assert main(["--frozen", str(fz), "--manifest", str(mf), "--crops-csv", str(cc), "--refreeze"]) == 0
    out = capsys.readouterr().out
    assert "크롭 3행 split 변경" in out and "이미지 3장 split 변경" in out
    bak = Path(str(cc) + BACKUP_SUFFIX)
    assert bak.read_bytes() == orig_csv  # 백업 = 원본 그대로
    new_csv = cc.read_bytes()
    assert new_csv.startswith(b"\xef\xbb\xbf") == bom
    assert b"\r\n" in new_csv and b"\n" not in new_csv.replace(b"\r\n", b"")  # CRLF 유지
    rows, expect = _read_csv(cc), reassign_crops(_crop_rows(), NEW)[0]
    assert rows == expect
    m = json.loads(mf.read_text(encoding="utf-8"))
    assert m["frozen_colonies"] == NEW and m["images"]["/d/003/a.jpg"]["split"] == "cal_b"
    assert b"\r\n" in mf.read_bytes() and not mf.read_bytes().endswith(b"\n")  # make_split_manifest 형식 유지

    # 두 번째 실행: 이미 재동결됨 → 바뀔 행 없음, 백업 충돌 없이 통과·파일 불변
    snap = (mf.read_bytes(), cc.read_bytes(), bak.read_bytes())
    assert main(["--frozen", str(fz), "--manifest", str(mf), "--crops-csv", str(cc), "--refreeze"]) == 0
    assert "바뀔 행 없음" in capsys.readouterr().out
    assert (mf.read_bytes(), cc.read_bytes(), bak.read_bytes()) == snap


def test_cli_refuses_existing_backup_unless_forced(tmp_path):
    mf, fz, cc = _setup(tmp_path)
    bak = Path(str(cc) + BACKUP_SUFFIX)
    bak.write_bytes(b"older backup")
    before = (mf.read_bytes(), cc.read_bytes())
    with pytest.raises(SystemExit) as e:
        main(["--frozen", str(fz), "--manifest", str(mf), "--crops-csv", str(cc), "--refreeze"])
    assert e.value.code == 2
    assert (mf.read_bytes(), cc.read_bytes(), bak.read_bytes()) == (*before, b"older backup")  # 아무것도 안 씀
    assert main(["--frozen", str(fz), "--manifest", str(mf), "--crops-csv", str(cc), "--refreeze",
                 "--force-backup"]) == 0
    assert bak.read_bytes() == before[1]


def test_cli_rejects_golden_change(tmp_path):
    mf, fz, cc = _setup(tmp_path)
    fz.write_text(json.dumps({"golden": ["001", "005"], "cal_a": ["002"], "cal_b": ["010"]}), encoding="utf-8")
    with pytest.raises(SystemExit) as e:
        main(["--frozen", str(fz), "--manifest", str(mf), "--refreeze"])
    assert e.value.code == 2


def test_committed_frozen_history_matches_current():
    """frozen_colonies_history.json 의 마지막 항목 = 커밋된 frozen_colonies.json = manifest frozen_colonies."""
    hist = AI_ROOT / "training" / "data" / "frozen_colonies_history.json"
    frozen = AI_ROOT / "training" / "data" / "frozen_colonies.json"
    if not (hist.exists() and frozen.exists()):
        pytest.skip("frozen_colonies_history.json 미커밋")
    h = json.loads(hist.read_text(encoding="utf-8"))["history"]
    assert [e["refreeze"] for e in h] == list(range(len(h)))  # 0 = 최초 동결
    assert h[-1]["frozen_colonies"] == json.loads(frozen.read_text(encoding="utf-8"))
    prev, cur = h[-2]["frozen_colonies"], h[-1]["frozen_colonies"]  # 마지막 재동결 = 이 도구 규칙 (golden 불변 등)
    validate_refreeze(prev, cur, {c for k in ("golden", "cal_a", "cal_b") for c in cur[k]})


def test_tasks_refreeze_target_passes_args_through():
    out = subprocess.run([sys.executable, "tasks.py", "refreeze", "--help"], cwd=AI_ROOT,
                         capture_output=True, text=True, encoding="utf-8")
    assert out.returncode == 0, out.stderr
    assert "training.data.refreeze_splits" in out.stdout and "--force-backup" in out.stdout
