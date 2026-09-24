"""
AI Hub 71667 Training 서브셋 추출기 — TL.zip 을 풀지 않고 스트리밍 인덱스 → 선택 → 최소 JSON + 7z 이미지 추출.

왜: TL.zip(라벨 16.3 GB)은 풀면 ~620 GB 다(라벨 JSON 1개 ≈ 2 MB, 그중 `environment` 센서 시계열이 ~1.36 MB).
학습 박스 디스크에 못 푼다. 그래서
  1) index      — TL.zip 멤버를 하나씩 읽어 `environment` 를 잘라낸 뒤 필요한 필드만 JSONL 1줄로.
  2) select     — 응애 성충 이미지 전부 + 성충 이미지 colony 층화 샘플(유충 전용 제외) → n_target 장.
  3) materialize — 선택분만 최소 JSON 으로 `<out>/02.라벨링데이터/...` 에 쓰고, 이미지 멤버 목록을 만들어
                   7z 로 TS.zip(멀티볼륨)에서 그 이미지만 `<out>/01.원천데이터/...` 로 추출.

결과 트리는 VL 과 같은 구조라 기존 파이프라인(make_split_manifest, aihub_to_yolo)이 그대로 읽는다.
상세 절차: training/data/DOWNLOAD.md §4-1.

Usage:
    python -m training.data.aihub_subset index --tl-zip <TL.zip> --out index.jsonl [--limit N]
    python -m training.data.aihub_subset select --index index.jsonl --n 25000 --out selected.jsonl
    python -m training.data.aihub_subset materialize --selected selected.jsonl --ts-zip <vols/TS.zip> \\
        --out-root D:\\helpbee-data\\aihub-71667-train-sub --sevenzip "C:\\Program Files\\7-Zip\\7z.exe" [--verify-listing]
"""

from __future__ import annotations

import argparse
import json
import random
import subprocess
import sys
import zipfile
from collections import Counter, defaultdict
from pathlib import Path, PurePosixPath

from training.data.aihub_to_yolo import IMAGE_DIR_NAME, LABEL_DIR_NAME, parse_annotations

CATEGORIES_71667 = [
    {"id": 0, "name": "유충_정상", "supercategory": "유충"},
    {"id": 1, "name": "유충_응애", "supercategory": "유충"},
    {"id": 2, "name": "유충_석고병", "supercategory": "유충"},
    {"id": 3, "name": "유충_부저병", "supercategory": "유충"},
    {"id": 4, "name": "성충_정상", "supercategory": "성충"},
    {"id": 5, "name": "성충_응애", "supercategory": "성충"},
    {"id": 6, "name": "성충_날개불구바이러스감염증", "supercategory": "성충"},
]
REQUIRED_KEYS = ("image", "annotations", "collection", "colony")
_ENV_KEY = b'"environment"'


# ---------- 파싱 ----------

def strip_environment(raw: bytes) -> dict:
    """JSON 바이트에서 거대한 "environment" 키를 파싱 없이 잘라내고 json.loads.

    `rfind('"environment"')` 위치 앞에서 자르고, 남은 꼬리의 `,` 를 지운 뒤 `}` 로 닫는다.
    environment 가 마지막 최상위 키가 아니면(잘린 결과가 JSON 이 아니거나 필수 키가 빠지면)
    전체 json.loads 로 폴백한다. 어느 경로든 결과에 environment 는 없다.
    """
    i = raw.rfind(_ENV_KEY)
    if i > 0:
        head = raw[:i].rstrip()
        if head.endswith(b","):
            try:
                d = json.loads((head[:-1] + b"}").decode("utf-8"))
                if isinstance(d, dict) and all(k in d for k in REQUIRED_KEYS):
                    return d
            except (UnicodeDecodeError, json.JSONDecodeError):
                pass
    d = json.loads(raw.decode("utf-8"))
    d.pop("environment", None)
    return d


def decode_member_name(info: zipfile.ZipInfo) -> str:
    """zip 멤버명 → 올바른 유니코드. UTF-8 플래그(0x800)가 없으면 zipfile 이 cp437 로 디코드하므로
    원 바이트로 되돌려 UTF-8 로(실패하면 cp949 로) 다시 디코드한다."""
    name = info.filename
    if info.flag_bits & 0x800:
        return name
    try:
        b = name.encode("cp437")
    except UnicodeEncodeError:  # 이미 올바른 이름 (metadata_encoding 지정 등)
        return name
    for enc in ("utf-8", "cp949"):
        try:
            return b.decode(enc)
        except UnicodeDecodeError:
            continue
    return name


def _rel_label_path(member: str) -> str:
    """zip 안 라벨 경로 → 02.라벨링데이터 아래 상대경로 (접두 `02.라벨링데이터/` 가 있으면 뗀다)."""
    p = member.replace("\\", "/").lstrip("/")
    prefix = LABEL_DIR_NAME + "/"
    return p[len(prefix):] if p.startswith(prefix) else p


def _record(member: str, d: dict) -> dict:
    img = d.get("image", {}) or {}
    anns = [{"category_id": a.get("category_id"), "bbox": a.get("bbox"), "area": a.get("area")}
            for a in d.get("annotations", []) or []]
    adult_boxes, _ = parse_annotations({"image": img, "annotations": anns}, "adult1")
    return {
        "json": member,
        "image": img.get("filename"),
        "colony": str((d.get("colony", {}) or {}).get("id")),
        "datetime": (d.get("collection", {}) or {}).get("datetime", ""),
        "device": (d.get("collection", {}) or {}).get("device", ""),
        "width": img.get("width"),
        "height": img.get("height"),
        "cats": [a["category_id"] for a in anns],
        "n_adult": len(adult_boxes),
        "has_varroa_adult": any(b[5] == 5 for b in adult_boxes),  # make_split_manifest 와 같은 정의
        "annotations": anns,
    }


# ---------- 1) index ----------

def index_labels(tl_zip: Path, out_jsonl: Path, limit: int | None = None) -> dict:
    """TL.zip 을 스트리밍해 .json 멤버마다 JSONL 1줄. out_jsonl.part 에 쓰고 끝나면 rename(중단 시 불완전 파일 방지).

    반환 stats: n_members(.json 멤버 수) / n_ok / n_fail / by_folder(`성충/성충_응애` 등 상위 2단 폴더별 ok 수).
    """
    out_jsonl.parent.mkdir(parents=True, exist_ok=True)
    part = out_jsonl.with_name(out_jsonl.name + ".part")
    stats = {"n_members": 0, "n_ok": 0, "n_fail": 0, "by_folder": Counter()}
    with zipfile.ZipFile(tl_zip) as zf, part.open("w", encoding="utf-8", newline="\n") as f:
        for info in zf.infolist():
            if info.is_dir():
                continue
            member = decode_member_name(info)
            if not member.lower().endswith(".json"):
                continue
            if limit is not None and stats["n_members"] >= limit:
                break
            stats["n_members"] += 1
            try:
                rec = _record(member, strip_environment(zf.read(info)))
                if not rec["image"]:
                    raise ValueError("image.filename 없음")
            except (ValueError, KeyError, TypeError, AttributeError, UnicodeDecodeError) as e:
                stats["n_fail"] += 1
                print(f"[index] FAIL {member}: {type(e).__name__}: {e}", file=sys.stderr, flush=True)
                continue
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            stats["n_ok"] += 1
            stats["by_folder"]["/".join(_rel_label_path(member).split("/")[:2])] += 1
            if stats["n_members"] % 10000 == 0:
                print(f"[index] {stats['n_members']} members (ok={stats['n_ok']} fail={stats['n_fail']})", flush=True)
    part.replace(out_jsonl)
    stats["by_folder"] = dict(stats["by_folder"])
    return stats


# ---------- 2) select ----------

def _read_jsonl(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def _write_jsonl(recs: list[dict], path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as f:
        for r in recs:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    return path


def select_subset(index_jsonl: Path, n_target: int = 25000, seed: int = 42,
                  per_colony_cap: float = 0.15) -> list[dict]:
    """선택 규칙 (결정적 — seed):
    (1) has_varroa_adult 이미지는 전부 포함 (n_target·cap 과 무관).
    (2) 나머지는 n_adult>0 이미지에서 colony 층화 라운드로빈 샘플. colony 당 총 이미지(응애 포함)가
        cap = max(1, int(n_target * per_colony_cap)) 를 넘지 않게 채운다.
    (3) 유충 전용(n_adult==0) 이미지는 제외.
    후보가 모자라거나 cap 에 막히면 있는 만큼만 돌려준다. 결과는 json 경로 순 정렬.
    """
    recs = _read_jsonl(index_jsonl)
    recs.sort(key=lambda r: r["json"])  # 입력 순서와 무관하게 결정적
    varroa = [r for r in recs if r.get("has_varroa_adult")]
    pool: dict[str, list[dict]] = defaultdict(list)
    for r in recs:
        if not r.get("has_varroa_adult") and r.get("n_adult", 0) > 0:
            pool[str(r["colony"])].append(r)
    cap = max(1, int(n_target * per_colony_cap))
    used = Counter(str(r["colony"]) for r in varroa)
    rng = random.Random(seed)
    colonies = sorted(pool)
    for c in colonies:
        rng.shuffle(pool[c])
    rng.shuffle(colonies)
    chosen: list[dict] = []
    budget = n_target - len(varroa)
    ptr = dict.fromkeys(colonies, 0)
    active = [c for c in colonies if used[c] < cap]
    while budget > 0 and active:
        nxt = []
        for c in active:
            if budget <= 0:
                break
            chosen.append(pool[c][ptr[c]])
            ptr[c] += 1
            used[c] += 1
            budget -= 1
            if ptr[c] < len(pool[c]) and used[c] < cap:
                nxt.append(c)
        active = nxt
    return sorted(varroa + chosen, key=lambda r: r["json"])


# ---------- 3) materialize ----------

def write_min_json(rec: dict, out_path: Path) -> None:
    """aihub_to_yolo.parse_annotations / make_split_manifest.load_items_from_aihub 가 읽는 필드만 쓴다."""
    d = {
        "categories": CATEGORIES_71667,
        "image": {"id": 0, "width": rec["width"], "height": rec["height"], "filename": rec["image"]},
        "annotations": [{"id": i, "image_id": 0, "category_id": a["category_id"], "bbox": a["bbox"], "area": a["area"]}
                        for i, a in enumerate(rec["annotations"])],
        "collection": {"device": rec["device"], "datetime": rec["datetime"]},
        "colony": {"id": rec["colony"]},
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(d, ensure_ascii=False), encoding="utf-8")


def write_label_tree(selected: list[dict], out_root: Path) -> int:
    """out_root/02.라벨링데이터/<TL zip 안 상대경로> 에 최소 JSON. 쓴 파일 수 반환."""
    base = out_root / LABEL_DIR_NAME
    for rec in selected:
        write_min_json(rec, base / PurePosixPath(_rel_label_path(rec["json"])))
    return len(selected)


def image_member_for(rec: dict) -> str:
    """TS zip 안 이미지 멤버 경로. TL/TS 는 미러 구조 — 라벨 멤버의 폴더 + image.filename
    (= json 멤버의 .json→.jpg; _resolve_image_path 와 같은 규칙). 라벨 멤버에 `02.라벨링데이터/`
    접두가 있으면 `01.원천데이터/` 로 바꾼다."""
    p = PurePosixPath(rec["json"].replace("\\", "/"))
    name = rec.get("image") or p.with_suffix(".jpg").name
    parts = list(p.parent.parts)
    if parts and parts[0] == LABEL_DIR_NAME:
        parts[0] = IMAGE_DIR_NAME
    return str(PurePosixPath(*parts, name)) if parts else name


def write_image_list(selected: list[dict], list_path: Path) -> Path:
    """7z @listfile — UTF-8, 한 줄 = 멤버 경로 (7z 에 -scsUTF-8 로 넘긴다)."""
    list_path.parent.mkdir(parents=True, exist_ok=True)
    list_path.write_text("".join(image_member_for(r) + "\n" for r in selected), encoding="utf-8", newline="\n")
    return list_path


def list_zip_members(zip_path: Path, sevenzip: Path | None = None) -> list[str]:
    """zip 멤버 목록 ('/' 구분). sevenzip 이 주어지면 `7z l -slt` (멀티볼륨 TS.zip 용), 아니면 zipfile."""
    if sevenzip is None:
        with zipfile.ZipFile(zip_path) as zf:
            return [decode_member_name(i) for i in zf.infolist() if not i.is_dir()]
    # -sccUTF-8: 7z 콘솔 출력 문자셋 (없으면 OEM 코드페이지로 나와 한글 멤버명이 깨진다 — 2026-09-24 박스 실측)
    out = subprocess.run([str(sevenzip), "l", "-slt", "-ba", "-mcp=65001", "-sccUTF-8", str(zip_path)],
                         capture_output=True, check=True)
    names, cur, is_dir = [], None, False
    for line in out.stdout.decode("utf-8", errors="replace").splitlines() + [""]:
        if line.startswith("Path = "):
            cur = line[len("Path = "):].replace("\\", "/")
        elif line.startswith("Folder = "):
            is_dir = line.endswith("+")
        elif not line.strip():
            if cur is not None and not is_dir:
                names.append(cur)
            cur, is_dir = None, False
    return names


def extract_images(ts_zip: Path, list_path: Path, out_root: Path, sevenzip: Path) -> int:
    """`7z x -mcp=65001 -scsUTF-8 -y -o<out_root>/01.원천데이터 <ts_zip> @<list>` 실행.
    목록 중 실제로 추출된 파일 수를 반환한다 (7z 비정상 종료 시 CalledProcessError)."""
    dest = out_root / IMAGE_DIR_NAME
    dest.mkdir(parents=True, exist_ok=True)
    cmd = [str(sevenzip), "x", "-mcp=65001", "-scsUTF-8", "-sccUTF-8", "-y", f"-o{dest}", str(ts_zip), f"@{list_path}"]
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)
    members = [m for m in list_path.read_text(encoding="utf-8").splitlines() if m.strip()]
    return sum((dest / PurePosixPath(m)).is_file() for m in members)


# ---------- CLI ----------

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("index")
    a.add_argument("--tl-zip", type=Path, required=True)
    a.add_argument("--out", type=Path, required=True)
    a.add_argument("--limit", type=int)
    b = sub.add_parser("select")
    b.add_argument("--index", type=Path, required=True)
    b.add_argument("--n", type=int, default=25000)
    b.add_argument("--seed", type=int, default=42)
    b.add_argument("--per-colony-cap", type=float, default=0.15)
    b.add_argument("--out", type=Path, required=True)
    c = sub.add_parser("materialize")
    c.add_argument("--selected", type=Path, required=True)
    c.add_argument("--ts-zip", type=Path, required=True)
    c.add_argument("--out-root", type=Path, required=True)
    c.add_argument("--sevenzip", type=Path, required=True)
    c.add_argument("--list", type=Path, help="7z listfile 경로 (기본 <out-root>/_subset_image_list.txt)")
    c.add_argument("--verify-listing", action="store_true", help="추출 전 TS zip 목록에 모든 이미지 멤버가 있는지 확인")
    args = ap.parse_args(argv)

    if args.cmd == "index":
        stats = index_labels(args.tl_zip, args.out, args.limit)
        print(json.dumps(stats, ensure_ascii=False, indent=2))
        return 0 if stats["n_ok"] else 1
    if args.cmd == "select":
        sel = select_subset(args.index, args.n, args.seed, args.per_colony_cap)
        _write_jsonl(sel, args.out)
        cols = Counter(r["colony"] for r in sel)
        print(f"[select] {len(sel)} images (varroa={sum(r['has_varroa_adult'] for r in sel)}, "
              f"colonies={len(cols)}, max/colony={max(cols.values(), default=0)}) → {args.out}")
        if len(sel) < args.n:
            print(f"[select] WARN 목표 {args.n} 미달 — 후보 부족 또는 colony cap", file=sys.stderr)
        return 0
    # materialize
    sel = _read_jsonl(args.selected)
    lst = write_image_list(sel, args.list or args.out_root / "_subset_image_list.txt")
    if args.verify_listing:
        have = set(list_zip_members(args.ts_zip, args.sevenzip))
        missing = [m for m in (image_member_for(r) for r in sel) if m not in have]
        if missing:
            print(f"[materialize] TS zip 에 없는 이미지 {len(missing)}/{len(sel)} — 예: {missing[:3]}", file=sys.stderr)
            return 2
    n_lbl = write_label_tree(sel, args.out_root)
    n_img = extract_images(args.ts_zip, lst, args.out_root, args.sevenzip)
    print(f"[materialize] labels={n_lbl} images={n_img} → {args.out_root}")
    return 0 if n_img == n_lbl else 2


if __name__ == "__main__":
    sys.exit(main())
