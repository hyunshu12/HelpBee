# apps/ai/training/data/refreeze_splits.py
"""홀드아웃 재동결(refreeze) — 이미 만든 split_manifest·crops.csv 의 71667 split 을 새 colony 맵으로 다시 배정.

왜: 재동결 1(2026-09-24)의 cal_a(002·020)/cal_b(010·016)는 양성이 사실상 한 colony(002 / 010)뿐이라, 같은 τ 에서
음성 FPR 이 colony 마다 ~10배 달라지는 것을 보정셋이 보지 못했다(docs/05-implementation/2026-09-27-v021-stage2-experiments.md
§4.3–§5). 재동결 2 는 cal-A/cal-B 를 각 6 colony 로 넓힌다 (training/data/frozen_colonies_history.json).

규칙 (71667 행만 — 외부 소스 VarroaDataset/EV2 는 손대지 않는다):
- 새 맵의 colony → 그 split(golden/cal_a/cal_b). train/val 이던 이미지·크롭이 cal 로 옮겨 간다.
- 새 맵에 없는 colony → 그대로 (train/val 시간 블록 분할 불변).
- golden 은 바꿀 수 없다 — golden 은 디듀프(dropped_dup)가 붙은 영구 평가셋이라 이 도구가 재현하지 못한다.
  golden 을 바꾸려면 make_split_manifest --refreeze 로 처음부터 다시 뽑는다.
- 이전 홀드아웃(golden/cal_a/cal_b) colony 가 새 맵에서 빠지면 오류 — 한 번 보정·평가에 쓴 colony 를 학습으로 되돌리면
  이후 수치가 오염된다.
- 결과 manifest 는 `make_split_manifest --frozen` 으로 처음부터 재생성한 것과 같다 (cal colony 는 디듀프 없음).

크롭은 다시 자르지 않는다: 71667 train/val 크롭은 자기 colony 를 안 본 fold 모델(out-of-fold) 박스라 cal 로 옮겨도
Stage-1 누수가 없다. 새 manifest 로 make_crops 를 다시 돌리면 새 cal colony 가 weights-all(그 colony 로 학습됨)로
잘려 누수가 생기므로, 기존 crops.csv 의 `split` 열만 이 도구로 고친다(`path`·PNG 위치는 그대로, 로더는 `path` 만 쓴다).
크롭 디렉터리의 stats.json `by_source_split` 은 갱신하지 않는다(정보용, 학습·평가 코드가 읽지 않음).

Usage (apps/ai 에서):
  python -m training.data.refreeze_splits --frozen training/data/frozen_colonies.json \\
      --manifest training/split_manifest.json [--crops-csv <crops>/crops.csv ...] --refreeze
  (= python tasks.py refreeze --refreeze [--crops-csv ...]) · 미리보기: --dry-run (쓰기 없음, --refreeze 불필요)

crops.csv 는 쓰기 전에 형제 백업 `<csv>.bak-refreeze1` 을 만든다 — 이미 있으면 --force-backup 없이는 거부(rc 2).
바뀔 행이 없는 파일(이미 재동결됨)은 백업·쓰기 모두 건너뛴다. 열 순서·인코딩(BOM)·줄바꿈(CRLF/LF)은 그대로 유지.
"""
from __future__ import annotations

import argparse
import copy
import csv
import io
import json
import shutil
from collections import defaultdict
from pathlib import Path

from training.data.make_split_manifest import is_71667

HOLDOUT_SPLITS = ("golden", "cal_a", "cal_b")
BACKUP_SUFFIX = ".bak-refreeze1"
SPLIT_ORDER = ("train", "val", "golden", "dropped_dup", "cal_a", "cal_b")


class RefreezeError(ValueError):
    """재동결 규칙 위반 (golden 변경, 홀드아웃 colony 누락, 모르는 colony, 중복 등)."""


# ── 맵 검증 ───────────────────────────────────────────────────────────────────
def normalize_frozen(d: dict) -> dict[str, list[str]]:
    """{golden, cal_a, cal_b} → colony 문자열 리스트 (순서 유지). 키가 다르거나 colony 가 두 번 나오면 RefreezeError."""
    if not isinstance(d, dict) or set(d) != set(HOLDOUT_SPLITS):
        raise RefreezeError(f"frozen 맵 키는 정확히 {HOLDOUT_SPLITS}: {sorted(d) if isinstance(d, dict) else d!r}")
    out = {k: [str(c) for c in d[k]] for k in HOLDOUT_SPLITS}
    seen: dict[str, str] = {}
    for k in HOLDOUT_SPLITS:
        for c in out[k]:
            if c in seen:
                raise RefreezeError(f"colony {c} 가 {seen[c]} 와 {k} 에 중복")
            seen[c] = k
    return out


def colony_split_map(frozen: dict[str, list[str]]) -> dict[str, str]:
    return {c: k for k in HOLDOUT_SPLITS for c in frozen[k]}


def validate_refreeze(old: dict, new: dict, known_colonies: set[str]) -> None:
    """old → new 재동결이 허용되는지. golden 동일 · 이전 홀드아웃 ⊆ 새 홀드아웃 · 새 colony 는 모두 manifest 에 존재."""
    old, new = normalize_frozen(old), normalize_frozen(new)
    if set(old["golden"]) != set(new["golden"]):
        raise RefreezeError(f"golden 은 바꿀 수 없다 ({old['golden']} → {new['golden']}) — golden 디듀프는 "
                            "make_split_manifest --refreeze 로만 재현된다")
    held_new = colony_split_map(new)
    dropped = sorted(c for c in colony_split_map(old) if c not in held_new)
    if dropped:
        raise RefreezeError(f"이전 홀드아웃 colony {dropped} 가 새 맵에 없다 — 보정·평가에 쓴 colony 를 학습으로 "
                            "되돌릴 수 없다")
    unknown = sorted(c for c in held_new if c not in known_colonies)
    if unknown:
        raise RefreezeError(f"manifest 에 없는 71667 colony: {unknown}")


# ── manifest ─────────────────────────────────────────────────────────────────
def reassign_manifest(m: dict, new: dict) -> tuple[dict, int]:
    """manifest 사본에서 71667 이미지 split 을 colony 로 재배정 + frozen_colonies 갱신. (새 manifest, 바뀐 이미지 수).
    golden colony 이미지는 golden/dropped_dup 그대로(바뀌면 안 됨). 원본 m 은 건드리지 않는다."""
    new = normalize_frozen(new)
    held = colony_split_map(new)
    out = copy.deepcopy(m)
    out["frozen_colonies"] = new
    changed = 0
    for key, v in out["images"].items():
        if not is_71667(v.get("source", "")):
            continue
        target, cur = held.get(str(v["colony"])), v["split"]
        if target is None:
            if cur in HOLDOUT_SPLITS or cur == "dropped_dup":
                raise RefreezeError(f"홀드아웃({cur}) 이미지의 colony {v['colony']} 가 새 맵에 없다: {key}")
            continue
        if target == "golden":
            if cur not in ("golden", "dropped_dup"):
                raise RefreezeError(f"golden colony {v['colony']} 이미지가 {cur} — golden 은 바꿀 수 없다: {key}")
            continue
        if cur == "dropped_dup":
            raise RefreezeError(f"dropped_dup(golden 디듀프) 이미지를 {target} 로 옮길 수 없다: {key}")
        if cur != target:
            v["split"] = target
            changed += 1
    return out, changed


def manifest_counts(m: dict) -> dict[str, dict[str, int]]:
    """split 별 {images, varroa} (71667 만)."""
    agg: dict[str, dict[str, int]] = defaultdict(lambda: {"images": 0, "varroa": 0})
    for v in m["images"].values():
        if is_71667(v.get("source", "")):
            r = agg[v["split"]]
            r["images"] += 1
            r["varroa"] += bool(v.get("has_varroa_adult"))
    return dict(agg)


def detect_newline(text: str) -> str:
    return "\r\n" if "\r\n" in text else "\n"


def dump_manifest(m: dict, newline: str = "\n") -> str:
    """make_split_manifest 와 같은 직렬화 (ensure_ascii=False, indent=1, 끝 줄바꿈 없음). newline 은 원본 유지용."""
    s = json.dumps(m, ensure_ascii=False, indent=1)
    return s.replace("\n", newline) if newline != "\n" else s


# ── crops.csv ────────────────────────────────────────────────────────────────
def read_csv_preserving(path: Path) -> dict:
    """원본 형식(BOM·줄바꿈·끝 줄바꿈 유무)과 행(list[list[str]], 첫 행 = 헤더)."""
    raw = Path(path).read_bytes()
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw[3:].decode("utf-8") if bom else raw.decode("utf-8")
    nl = detect_newline(text)
    rows = list(csv.reader(io.StringIO(text, newline="")))
    return {"rows": rows, "bom": bom, "newline": nl, "trailing": text.endswith(nl)}


def write_csv_preserving(path: Path, doc: dict) -> None:
    buf = io.StringIO(newline="")
    csv.writer(buf, lineterminator=doc["newline"]).writerows(doc["rows"])
    text = buf.getvalue()
    if not doc["trailing"] and text.endswith(doc["newline"]):
        text = text[: -len(doc["newline"])]
    Path(path).write_bytes((b"\xef\xbb\xbf" if doc["bom"] else b"") + text.encode("utf-8"))


def _col(header: list[str], name: str) -> int:
    if name not in header:
        raise RefreezeError(f"crops.csv 에 `{name}` 열이 없다: {header}")
    return header.index(name)


def reassign_crops(rows: list[list[str]], new: dict) -> tuple[list[list[str]], int]:
    """crops.csv 행(헤더 포함) 사본에서 71667 행의 `split` 만 colony 로 재배정. (새 행, 바뀐 행 수).
    규칙은 reassign_manifest 와 같다 (golden 불변, 홀드아웃 colony 누락 오류)."""
    held = colony_split_map(normalize_frozen(new))
    header = rows[0]
    i_src, i_col, i_split = _col(header, "source"), _col(header, "colony"), _col(header, "split")
    out = [list(header)]
    changed = 0
    for n, r in enumerate(rows[1:], start=2):
        r = list(r)
        if not r or not is_71667(r[i_src]):
            out.append(r)
            continue
        target, cur = held.get(r[i_col]), r[i_split]
        if target is None:
            if cur in HOLDOUT_SPLITS:
                raise RefreezeError(f"crops.csv {n}행: 홀드아웃({cur}) colony {r[i_col]} 가 새 맵에 없다")
        elif target == "golden":
            if cur != "golden":
                raise RefreezeError(f"crops.csv {n}행: golden colony {r[i_col]} 크롭이 {cur} — golden 은 바꿀 수 없다")
        elif cur != target:
            r[i_split] = target
            changed += 1
        out.append(r)
    return out, changed


def crops_counts(rows: list[list[str]]) -> dict[str, dict[str, int]]:
    """split 별 {crops, pos, neg} (모든 소스 — 외부 소스 행은 재배정되지 않으므로 Δ 는 71667 이동분)."""
    header = rows[0]
    i_split, i_label = _col(header, "split"), _col(header, "label")
    agg: dict[str, dict[str, int]] = defaultdict(lambda: {"crops": 0, "pos": 0, "neg": 0})
    for r in rows[1:]:
        if not r:
            continue
        a = agg[r[i_split]]
        a["crops"] += 1
        a["pos" if int(r[i_label]) == 1 else "neg"] += 1
    return dict(agg)


def format_count_table(before: dict, after: dict, fields: tuple[str, ...], title: str) -> list[str]:
    """split 별 `field before→after (Δ)` 표. split 순서 = SPLIT_ORDER, 그 밖은 이름순."""
    splits = [s for s in SPLIT_ORDER if s in before or s in after]
    splits += sorted((set(before) | set(after)) - set(splits))
    lines = [f"[{title}] " + f"{'split':<12}" + "".join(f"{f + ' before→after (Δ)':>34}" for f in fields)]
    for s in splits:
        b, a = before.get(s, {}), after.get(s, {})
        cells = []
        for f in fields:
            x, y = b.get(f, 0), a.get(f, 0)
            cells.append(f"{f'{x}→{y} ({y - x:+d})':>34}")
        lines.append(f"[{title}] {s:<12}" + "".join(cells))
    return lines


# ── CLI ──────────────────────────────────────────────────────────────────────
def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="홀드아웃 colony 재동결 (manifest + crops.csv split 재배정)")
    p.add_argument("--frozen", type=Path, required=True, help="새 colony 맵 {golden, cal_a, cal_b} (예: frozen_colonies.json)")
    p.add_argument("--manifest", type=Path, default=Path("training/split_manifest.json"))
    p.add_argument("--crops-csv", dest="crops_csv", type=Path, nargs="+", action="extend", default=[],
                   help="split 열을 고칠 crops.csv (여러 개 가능). 각 파일 옆에 <csv>.bak-refreeze1 백업")
    p.add_argument("--refreeze", action="store_true",
                   help="실제로 쓴다 (홀드아웃 재배정은 보정·평가 수치를 바꾼다 — 의도적일 때만)")
    p.add_argument("--dry-run", dest="dry_run", action="store_true", help="표만 출력, 아무것도 쓰지 않음")
    p.add_argument("--force-backup", dest="force_backup", action="store_true",
                   help=f"기존 <csv>{BACKUP_SUFFIX} 를 덮어쓴다")
    a = p.parse_args(argv)
    if not (a.refreeze or a.dry_run):
        p.error("홀드아웃 재동결은 --refreeze 가 필요하다 (미리보기는 --dry-run)")

    try:
        new = normalize_frozen(json.loads(a.frozen.read_text(encoding="utf-8")))
        m_text = a.manifest.read_bytes().decode("utf-8")  # read_text 는 CRLF→LF 변환 — 줄바꿈 감지 위해 bytes
        m = json.loads(m_text)
        known = {str(v["colony"]) for v in m["images"].values() if is_71667(v.get("source", ""))}
        validate_refreeze(m["frozen_colonies"], new, known)
        m2, n_img = reassign_manifest(m, new)
        csv_jobs = []
        for path in a.crops_csv:
            doc = read_csv_preserving(path)
            rows2, n_rows = reassign_crops(doc["rows"], new)
            csv_jobs.append((path, doc, rows2, n_rows))
    except RefreezeError as e:
        p.error(str(e))

    print(f"[refreeze] {m['frozen_colonies']} → {new}")
    for line in format_count_table(manifest_counts(m), manifest_counts(m2), ("images", "varroa"), "manifest"):
        print(line)
    print(f"[refreeze] manifest: 이미지 {n_img}장 split 변경", flush=True)
    for path, doc, rows2, n_rows in csv_jobs:
        for line in format_count_table(crops_counts(doc["rows"]), crops_counts(rows2), ("crops", "pos", "neg"),
                                       Path(path).name):
            print(line)
        print(f"[refreeze] {path}: 크롭 {n_rows}행 split 변경", flush=True)
    if a.dry_run:
        print("[refreeze] --dry-run: 쓰지 않음")
        return 0

    # 쓰기 전에 모든 백업 충돌을 먼저 검사 (일부만 쓰고 멈추지 않게)
    todo = [(path, doc, rows2) for path, doc, rows2, n_rows in csv_jobs if n_rows]
    for path, _doc, _rows2 in todo:
        bak = Path(str(path) + BACKUP_SUFFIX)
        if bak.exists() and not a.force_backup:
            p.error(f"백업 {bak} 가 이미 있다 — 덮어쓰려면 --force-backup (이미 재동결한 파일인지 먼저 확인)")
    for path, doc, rows2 in todo:
        bak = Path(str(path) + BACKUP_SUFFIX)
        shutil.copy2(path, bak)
        write_csv_preserving(path, {**doc, "rows": rows2})
        print(f"[refreeze] wrote {path} (backup {bak})")
    for path, _doc, _rows2, n_rows in csv_jobs:
        if not n_rows:
            print(f"[refreeze] {path}: 바뀔 행 없음 — 백업·쓰기 생략")
    if n_img or m2["frozen_colonies"] != m["frozen_colonies"]:
        a.manifest.write_text(dump_manifest(m2, detect_newline(m_text)), encoding="utf-8", newline="")
        print(f"[refreeze] wrote {a.manifest}")
    else:
        print(f"[refreeze] {a.manifest}: 이미 새 맵 — 쓰기 생략")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
