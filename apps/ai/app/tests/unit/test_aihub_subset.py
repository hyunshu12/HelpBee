# apps/ai/app/tests/unit/test_aihub_subset.py
"""71667 Training 서브셋 추출기 — 합성 zip 으로 실제 데이터 없이 검증."""
import json
import shutil
import zipfile
from pathlib import Path

import pytest

from training.data.aihub_subset import (
    decode_member_name,
    image_member_for,
    index_labels,
    list_zip_members,
    select_subset,
    strip_environment,
    write_image_list,
    write_label_tree,
    write_min_json,
    extract_images,
)
from training.data.aihub_to_yolo import parse_annotations

CATS = [{"id": i, "name": n, "supercategory": n.split("_")[0]} for i, n in enumerate(
    ["유충_정상", "유충_응애", "유충_석고병", "유충_부저병", "성충_정상", "성충_응애", "성충_날개불구바이러스감염증"])]


def _label(stem: str, colony: str, anns: list[tuple[int, list[float]]], env_last: bool = True) -> dict:
    d = {
        "categories": CATS,
        "image": {"id": 0, "width": 1920, "height": 1080, "filename": f"{stem}.jpg", "caption": None, "hive": True},
        "annotations": [
            {"id": i, "image_id": 0, "category_id": c, "bbox": bb,
             "area": round((bb[2] - bb[0]) * (bb[3] - bb[1])), "state": "정상", "symptoms": "기생충"}
            for i, (c, bb) in enumerate(anns)],
        "collection": {"weather": "맑음", "datetime": "20230820_105708_001", "device": "플레이트촬영기", "resolution": "FHD"},
        "colony": {"id": colony, "PCR": "없음", "type": "스티로폼"},
    }
    env = {"in_temperature": [{"t": i, "v": 34.5} for i in range(200)], "note": "environment 더미 {중괄호} \"따옴표\""}
    if env_last:
        d["environment"] = env
    else:  # environment 가 마지막 키가 아닌 변형 — 폴백 경로
        d = {"environment": env, **d}
    return d


# (member, label) — 성충_응애 2 · 성충_정상 2 · 유충 2
MEMBERS = [
    ("성충/성충_응애/001/A_001_001_20230820105708_001_001_001_001.json",
     _label("A_001_001_20230820105708_001_001_001_001", "001", [(5, [100.0, 100.0, 300.0, 350.0]), (4, [500.0, 500.0, 700.0, 760.0])])),
    ("성충/성충_응애/002/A_001_002_20230820105709_001_001_001_001.json",
     _label("A_001_002_20230820105709_001_001_001_001", "002", [(5, [10.0, 20.0, 210.0, 220.0])])),
    ("성충/성충_정상/003/B_001_003_20230820105710_001_001_001_001.json",
     _label("B_001_003_20230820105710_001_001_001_001", "003", [(4, [0.0, 0.0, 250.0, 260.0]), (6, [800.0, 300.0, 990.0, 520.0])])),
    ("성충/성충_정상/004/B_001_004_20230820105711_001_001_001_001.json",
     _label("B_001_004_20230820105711_001_001_001_001", "004", [(4, [1.0, 2.0, 201.0, 302.0])], env_last=False)),
    ("유충/유충_응애/005/C_001_005_20230820105712_001_001_001_001.json",
     _label("C_001_005_20230820105712_001_001_001_001", "005", [(1, [100.0, 100.0, 500.0, 500.0])])),
    ("유충/유충_정상/005/C_001_005_20230820105713_001_001_001_001.json",
     _label("C_001_005_20230820105713_001_001_001_001", "005", [(0, [100.0, 100.0, 200.0, 200.0])])),
]
NO_UTF8_FLAG = {1, 4}  # 이 인덱스의 멤버는 UTF-8 플래그 없이(cp437 로 보이게) 쓴다


class _NoFlagInfo(zipfile.ZipInfo):
    """UTF-8 플래그(0x800) 없이 UTF-8 바이트를 그대로 쓴다 — 한국 Windows 압축기 흉내."""

    def _encodeFilenameFlags(self):  # noqa: N802
        return self.filename.encode("utf-8"), self.flag_bits & ~0x800


def _build_zip(path: Path, entries: list[tuple[str, bytes]], no_flag: set[int]) -> Path:
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as zf:
        for i, (name, data) in enumerate(entries):
            info = (_NoFlagInfo if i in no_flag else zipfile.ZipInfo)(name, date_time=(2023, 8, 20, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, data)
    return path


@pytest.fixture
def zips(tmp_path):
    tl = _build_zip(tmp_path / "TL.zip",
                    [(m, json.dumps(d, ensure_ascii=False).encode("utf-8")) for m, d in MEMBERS], NO_UTF8_FLAG)
    ts = _build_zip(tmp_path / "TS.zip",
                    [(m[:-5] + ".jpg", b"\xff\xd8fakejpeg" + m.encode("utf-8")) for m, _ in MEMBERS], NO_UTF8_FLAG)
    return tl, ts


# ---------- strip_environment ----------

def test_strip_environment_fast_path_drops_env():
    raw = json.dumps(MEMBERS[0][1], ensure_ascii=False, indent=2).encode("utf-8")
    d = strip_environment(raw)
    assert "environment" not in d
    assert d["colony"]["id"] == "001" and len(d["annotations"]) == 2


def test_strip_environment_does_not_parse_env_payload():
    """빠른 경로는 environment 값을 아예 파싱하지 않는다 — 값이 깨져 있어도 성공."""
    head = json.dumps({k: v for k, v in MEMBERS[0][1].items() if k != "environment"}, ensure_ascii=False)[:-1]
    raw = (head + ', "environment": {"in_temperature": [1, 2, <<잘림>>').encode("utf-8")
    d = strip_environment(raw)
    assert d["colony"]["id"] == "001"


def test_strip_environment_fallback_when_env_not_last():
    raw = json.dumps(MEMBERS[3][1], ensure_ascii=False).encode("utf-8")
    d = strip_environment(raw)
    assert "environment" not in d
    assert d["colony"]["id"] == "004" and d["annotations"][0]["category_id"] == 4


def test_strip_environment_no_env_key():
    d = strip_environment(json.dumps({"image": {"filename": "x.jpg"}, "annotations": []}).encode("utf-8"))
    assert d["image"]["filename"] == "x.jpg"


# ---------- 멤버명 디코드 ----------

def test_member_names_restored_with_and_without_utf8_flag(zips):
    tl, _ = zips
    with zipfile.ZipFile(tl) as zf:
        infos = zf.infolist()
        assert not infos[1].flag_bits & 0x800 and infos[1].filename != MEMBERS[1][0]  # cp437 로 깨져 보임
        names = [decode_member_name(i) for i in infos]
    assert names == [m for m, _ in MEMBERS]


# ---------- index → select → materialize ----------

def test_index_labels_records(zips, tmp_path):
    tl, _ = zips
    out = tmp_path / "index.jsonl"
    stats = index_labels(tl, out)
    assert stats["n_members"] == 6 and stats["n_ok"] == 6 and stats["n_fail"] == 0
    assert stats["by_folder"]["성충/성충_응애"] == 2 and stats["by_folder"]["유충/유충_정상"] == 1
    recs = [json.loads(line) for line in out.read_text(encoding="utf-8").splitlines()]
    by = {r["json"]: r for r in recs}
    r0 = by[MEMBERS[0][0]]
    assert r0["image"] == "A_001_001_20230820105708_001_001_001_001.jpg"
    assert r0["colony"] == "001" and r0["device"] == "플레이트촬영기" and r0["datetime"] == "20230820_105708_001"
    assert (r0["width"], r0["height"]) == (1920, 1080)
    assert r0["cats"] == [5, 4] and r0["n_adult"] == 2 and r0["has_varroa_adult"] is True
    assert r0["annotations"][0] == {"category_id": 5, "bbox": [100.0, 100.0, 300.0, 350.0], "area": 50000}
    r_larva = by[MEMBERS[4][0]]
    assert r_larva["n_adult"] == 0 and r_larva["has_varroa_adult"] is False and r_larva["cats"] == [1]
    assert "environment" not in json.dumps(recs, ensure_ascii=False)


def test_index_labels_limit_and_bad_member(tmp_path):
    tl = _build_zip(tmp_path / "TL.zip", [
        (MEMBERS[0][0], json.dumps(MEMBERS[0][1], ensure_ascii=False).encode("utf-8")),
        ("성충/성충_정상/009/broken.json", b"{not json"),
        ("성충/readme.txt", b"skip me"),
        (MEMBERS[2][0], json.dumps(MEMBERS[2][1], ensure_ascii=False).encode("utf-8")),
    ], set())
    stats = index_labels(tl, tmp_path / "i.jsonl")
    assert stats["n_members"] == 3 and stats["n_ok"] == 2 and stats["n_fail"] == 1
    stats = index_labels(tl, tmp_path / "i2.jsonl", limit=1)
    assert stats["n_members"] == 1 and stats["n_ok"] == 1


def test_select_subset_rules(zips, tmp_path):
    tl, _ = zips
    idx = tmp_path / "index.jsonl"
    index_labels(tl, idx)
    sel = select_subset(idx, n_target=4)
    names = sorted(r["json"] for r in sel)
    assert names == sorted(m for m, _ in MEMBERS[:4])  # 응애 2 전부 + 성충_정상 2, 유충 0
    assert select_subset(idx, n_target=4) == sel  # 결정적


def _write_index(path: Path, recs: list[dict]) -> Path:
    path.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in recs), encoding="utf-8")
    return path


def test_select_subset_colony_cap_and_stratification(tmp_path):
    recs = []
    for c, n in (("001", 500), ("002", 30), ("003", 30), ("004", 30)):
        for i in range(n):
            recs.append({"json": f"성충/성충_정상/{c}/{i}.json", "colony": c, "n_adult": 3, "has_varroa_adult": False})
    recs += [{"json": f"성충/성충_응애/001/v{i}.json", "colony": "001", "n_adult": 2, "has_varroa_adult": True} for i in range(5)]
    recs += [{"json": f"유충/유충_정상/002/l{i}.json", "colony": "002", "n_adult": 0, "has_varroa_adult": False} for i in range(50)]
    idx = _write_index(tmp_path / "idx.jsonl", recs)
    sel = select_subset(idx, n_target=100, seed=7, per_colony_cap=0.15)
    from collections import Counter
    col = Counter(r["colony"] for r in sel)
    assert sum(r["has_varroa_adult"] for r in sel) == 5  # 응애 전부
    assert all(r["n_adult"] > 0 for r in sel)  # 유충 전용 제외
    assert all(v <= 15 for v in col.values())  # 100 * 0.15
    assert len(sel) == 15 * 4 == 60  # 부족하면 있는 만큼 (cap 에 막힘)
    assert select_subset(idx, n_target=100, seed=7) == sel
    assert select_subset(idx, n_target=100, seed=8) != sel


def test_min_json_roundtrips_through_parsers(zips, tmp_path):
    tl, _ = zips
    idx = tmp_path / "index.jsonl"
    index_labels(tl, idx)
    sel = select_subset(idx, n_target=4)
    root = tmp_path / "train-sub"
    assert write_label_tree(sel, root) == 4
    orig = dict(MEMBERS)
    for r in sel:
        p = root / "02.라벨링데이터" / r["json"]
        assert p.exists()
        d = json.loads(p.read_text(encoding="utf-8"))
        assert set(d) == {"categories", "image", "annotations", "collection", "colony"}
        assert len(d["categories"]) == 7
        assert parse_annotations(d, "adult1") == parse_annotations(orig[r["json"]], "adult1")
        assert parse_annotations(d, "legacy3") == parse_annotations(orig[r["json"]], "legacy3")
        assert d["collection"]["datetime"][:15] == "20230820_105708"
        assert d["colony"]["id"] == r["colony"] and d["image"]["filename"] == r["image"]


def test_write_min_json_shape(tmp_path):
    rec = {"json": "성충/성충_정상/003/x.json", "image": "x.jpg", "colony": "003", "datetime": "20230820_105708_001",
           "device": "소문촬영기", "width": 1920, "height": 1080,
           "annotations": [{"category_id": 4, "bbox": [1, 2, 3, 4], "area": 4}]}
    out = tmp_path / "a" / "x.json"
    write_min_json(rec, out)
    d = json.loads(out.read_text(encoding="utf-8"))
    assert d["image"] == {"id": 0, "width": 1920, "height": 1080, "filename": "x.jpg"}
    assert d["annotations"] == [{"id": 0, "image_id": 0, "category_id": 4, "bbox": [1, 2, 3, 4], "area": 4}]
    assert d["collection"] == {"device": "소문촬영기", "datetime": "20230820_105708_001"}
    assert d["colony"] == {"id": "003"}


def test_image_member_and_list(zips, tmp_path):
    tl, ts = zips
    idx = tmp_path / "index.jsonl"
    index_labels(tl, idx)
    sel = select_subset(idx, n_target=4)
    members = [image_member_for(r) for r in sel]
    assert image_member_for({"json": MEMBERS[0][0], "image": "A_001_001_20230820105708_001_001_001_001.jpg"}) == \
        "성충/성충_응애/001/A_001_001_20230820105708_001_001_001_001.jpg"
    assert set(members) <= set(list_zip_members(ts))  # TL/TS 미러 (cp437 멤버 포함)
    lst = write_image_list(sel, tmp_path / "list.txt")
    assert lst.read_bytes().decode("utf-8").splitlines() == members


@pytest.mark.skipif(shutil.which("7z") is None, reason="7z 없음")
def test_extract_images_with_7z(zips, tmp_path):
    tl, ts = zips
    idx = tmp_path / "index.jsonl"
    index_labels(tl, idx)
    sel = select_subset(idx, n_target=4)
    lst = write_image_list(sel, tmp_path / "list.txt")
    root = tmp_path / "train-sub"
    n = extract_images(ts, lst, root, Path(shutil.which("7z")))
    assert n == 4
    for r in sel:
        assert (root / "01.원천데이터" / image_member_for(r)).exists()
