# apps/ai/training/data/make_split_manifest.py
"""단일 split 진실 소스. golden/cal-A/cal-B는 colony 홀드아웃, train/val은 colony 내 시간 블록.

- 홀드아웃 colony 선택은 varroa-aware: 응애 이미지 많은 colony 부터 golden(응애 ≥100) → cal_a/cal_b
  교대(각 응애 ≥50), 남은 슬롯은 응애 0/적은 colony. golden+cal 합은 전체 이미지의 50% 상한.
  (무작위 선택은 71667 Validation 에서 golden/cal 응애가 14/6/10장뿐이었다.)
- golden 디듀프: 키 (colony, device, has_varroa_adult). 음성 10분, 양성 1분 창
  (응애 프레임은 버스트 촬영 — 10분 단일 창에서 183장 중 177장이 버려졌다).
- main 끝에 split 별 images / varroa / n_adult>0 요약을 출력한다.
- frozen_colonies: 한 번 정해지면 `--frozen` 으로 재생성해도 유지 (Training 셋 추가 시).
  `training/data/frozen_colonies.json` 이 있으면 `--frozen` 없이는 실행 거부(rc 2) — 새로 뽑으려면
  명시적 `--refreeze`. `--frozen` 이면 출력 frozen_colonies == 입력 == 커밋 파일을 검사한다.
- 라벨 대비 이미지 누락은 루트별로 세어 출력, 5% 초과면 rc 2 (압축 해제 레이아웃 오류)
- 외부 데이터(VarroaDataset / EV2)는 `split_external` — EV2 는 영상 단위 홀드아웃(연속 프레임 누수 방지)

Usage (apps/ai 에서):
  python -m training.data.make_split_manifest --roots <DATA_ROOT>/aihub-71667-val --tags 71667-val
  python -m training.data.make_split_manifest --roots <val> <train> --tags 71667-val 71667-train \
      --frozen training/split_manifest.json
"""
from __future__ import annotations

import argparse
import json
import random
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path


SOURCE_71667 = "71667"


def is_71667(source: str) -> bool:
    """manifest 태그(`71667-val`, `71667-train`, ...)와 리터럴 `71667` 을 모두 71667 로 본다 (접두 매칭)."""
    return str(source).startswith(SOURCE_71667)


def source_group(source: str) -> str:
    """집계·샘플링용 소스 그룹: 71667 태그는 `71667` 하나로, 나머지(varroadataset/ev2)는 그대로."""
    return SOURCE_71667 if is_71667(source) else str(source)


def _draw_holdouts(items: list[dict], rng: random.Random, n_g: int, half: int,
                   golden_varroa_target: int, cal_varroa_target: int,
                   max_holdout_share: float) -> tuple[list[str], list[str], list[str]]:
    """varroa-aware colony 홀드아웃 선택 (build_manifest docstring 참조)."""
    n_img: Counter = Counter(i["colony"] for i in items)
    n_var: Counter = Counter(i["colony"] for i in items if i["has_varroa_adult"])
    cap = max_holdout_share * len(items)
    colonies = sorted(n_img)
    rng.shuffle(colonies)  # 동률 tie-break 은 seed 로
    by_var = sorted((c for c in colonies if n_var[c] > 0), key=lambda c: -n_var[c])  # 안정 정렬
    g: list[str] = []
    a: list[str] = []
    b: list[str] = []
    used = 0

    def take(split: list[str], c: str) -> bool:
        nonlocal used
        if used + n_img[c] > cap:
            return False
        split.append(c)
        used += n_img[c]
        return True

    def var(split: list[str]) -> int:
        return sum(n_var[c] for c in split)

    queue = list(by_var)
    rest: list[str] = []
    for c in queue:  # 1) golden: 응애 많은 colony 부터
        if var(g) >= golden_varroa_target or len(g) >= n_g:
            rest.append(c)
        elif not take(g, c):
            rest.append(c)
    queue, rest, turn = rest, [], 0
    for c in queue:  # 2) cal_a / cal_b 교대
        needy = [s for s in (a, b) if var(s) < cal_varroa_target and len(s) < half]
        if not needy:
            rest.append(c)
            continue
        first = (a, b)[turn]
        target = first if first in needy else needy[0]
        if take(target, c):
            turn = 1 - turn
        else:
            rest.append(c)
    held = set(g) | set(a) | set(b)
    pool = [c for c in colonies if c not in held]  # 이미 seed 셔플됨
    pool.sort(key=lambda c: n_var[c])  # 3) 남은 슬롯은 응애 0/적은 colony 로 채움
    for split, n in ((g, n_g), (a, half), (b, half)):
        for c in list(pool):
            if len(split) >= n:
                break
            if take(split, c):
                pool.remove(c)
    return g, a, b


def build_manifest(items: list[dict], seed: int, golden_frac=0.10, cal_frac=0.15, dedupe_min=10,
                   frozen: dict | None = None, *, dedupe_min_pos: float = 1,
                   golden_varroa_target: int = 100, cal_varroa_target: int = 50,
                   max_holdout_share: float = 0.5) -> dict:
    """split manifest 생성.

    홀드아웃 선택 (`frozen is None` 일 때만; frozen 이면 그 colony 그대로):
      n_g = max(3, round(n_colony*golden_frac)), half = max(1, max(2, round(n_colony*cal_frac))//2).
      1) colony 를 응애(has_varroa_adult) 이미지 수 내림차순(동률은 seed 셔플)으로 golden 이
         응애 ≥ golden_varroa_target 또는 n_g colony 가 될 때까지 가져간다.
      2) 이어서 cal_a/cal_b 가 교대로 다음 colony 를 가져간다 (각각 응애 ≥ cal_varroa_target 또는
         half colony 까지).
      3) 남은 슬롯(golden n_g, cal 각 half)은 응애 0/적은 colony(seed 셔플)로 채운다.
      모든 단계에서 golden+cal 이미지 합이 전체의 max_holdout_share 를 넘기면 그 colony 는 건너뛴다.
      목표 미달이어도 예외 없이 가능한 최선을 택한다. 나머지 colony 는 train/val (colony 내 시간 80/20).
    디듀프 (golden 만): 키 (colony, device, has_varroa_adult) 별로 직전 채택 프레임과
      음성은 dedupe_min 분, 양성은 dedupe_min_pos 분 미만이면 dropped_dup (응애 프레임은 버스트 촬영).
    """
    colonies = sorted({i["colony"] for i in items})
    if frozen:
        g, a, b = (list(frozen[k]) for k in ("golden", "cal_a", "cal_b"))
    else:
        n_g = max(3, round(len(colonies) * golden_frac))
        n_c = max(2, round(len(colonies) * cal_frac))
        half = max(1, n_c // 2)
        g, a, b = _draw_holdouts(items, random.Random(seed), n_g, half,
                                 golden_varroa_target, cal_varroa_target, max_holdout_share)
    held = {c: "golden" for c in g} | {c: "cal_a" for c in a} | {c: "cal_b" for c in b}
    out = {"seed": seed, "frozen_colonies": {"golden": g, "cal_a": a, "cal_b": b}, "images": {}}
    by_col = defaultdict(list)
    for it in items:
        by_col[it["colony"]].append(it)

    def rec(it, split):
        out["images"][it["image"]] = {"split": split, "colony": it["colony"], "device": it["device"],
                                      "ts": it["ts"].isoformat(), "source": it["source"],
                                      "has_varroa_adult": bool(it["has_varroa_adult"]), "n_adult": int(it["n_adult"])}

    for col, its in by_col.items():
        its.sort(key=lambda x: x["ts"])
        if col in held:
            split = held[col]
            last = {}
            for it in its:
                pos = bool(it["has_varroa_adult"])
                key = (col, it["device"], pos)
                prev = last.get(key)
                s = split
                window = (dedupe_min_pos if pos else dedupe_min) * 60
                if split == "golden" and prev is not None and (it["ts"] - prev).total_seconds() < window:
                    s = "dropped_dup"
                else:
                    last[key] = it["ts"]
                rec(it, s)
        else:
            cut = int(len(its) * 0.8)
            for k, it in enumerate(its):
                rec(it, "train" if k < cut else "val")
    return out


def _ev2_video_id(image: Path | str) -> str:
    """EV2 `dataset_free/1_00953.MTS_frame6.png` → `1_00953` (폴더 무관 — 같은 영상이 free/infested 양쪽에 있음)."""
    return Path(image).name.split(".MTS")[0]


def split_external(rows: list[dict], seed: int, holdout_frac: float = 0.15) -> dict[str, str]:
    """외부 데이터 split. VarroaDataset 은 원 split 유지, EV2 는 영상 단위로 holdout/train.

    EV2 연속 프레임은 거의 동일 → 프레임 단위 분할은 누수. 영상을 seed 로 섞어
    EV2 행의 holdout_frac 이상이 될 때까지 영상 통째로 holdout 에 배정한다.
    """
    out: dict[str, str] = {}
    videos: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        if r["source"] == "ev2":
            videos[_ev2_video_id(r["image"])].append(r)
        else:
            out[str(r["image"])] = r["split"]
    n_ev2 = sum(len(v) for v in videos.values())
    order = sorted(videos)
    random.Random(seed).shuffle(order)
    held = 0
    for vid in order:
        split = "holdout" if held < holdout_frac * n_ev2 else "train"
        if split == "holdout":
            held += len(videos[vid])
        for r in videos[vid]:
            out[str(r["image"])] = split
    return out


def load_items_from_aihub(roots: list[Path], source_tags: list[str]) -> list[dict]:
    """루트별 02.라벨링데이터/*.json → manifest 항목. 이미지 누락은 루트별로 세어 로그하고,
    5% 초과면 MissingImagesError (압축 해제 레이아웃 오류 — DOWNLOAD.md §5)."""
    from training.data.aihub_to_yolo import _resolve_image_path, check_missing_images, parse_annotations
    items = []
    for root, tag in zip(roots, source_tags):
        n_json = missing = bad_ts = 0
        for jp in (root / "02.라벨링데이터").rglob("*.json"):
            n_json += 1
            d = json.loads(jp.read_text(encoding="utf-8"))
            img = _resolve_image_path(jp, d["image"]["filename"])
            if img is None:
                missing += 1
                continue
            boxes, _ = parse_annotations(d, "adult1")
            ts = d.get("collection", {}).get("datetime", "")[:15]
            try:
                t = datetime.strptime(ts, "%Y%m%d_%H%M%S")
            except ValueError:
                bad_ts += 1
                continue
            items.append({"image": str(img.resolve()), "colony": str(d.get("colony", {}).get("id")),
                          "device": d.get("collection", {}).get("device", ""), "ts": t,
                          "has_varroa_adult": any(b[5] == 5 for b in boxes), "n_adult": len(boxes), "source": tag})
        print(f"[{tag}] json={n_json} missing_image={missing} bad_datetime={bad_ts}", flush=True)
        check_missing_images(missing, n_json, str(root))
    return items


SUMMARY_ORDER = ("train", "val", "golden", "dropped_dup", "cal_a", "cal_b")


def split_summary(m: dict) -> list[str]:
    """split 별 `images / varroa images / n_adult>0 images` 한 줄씩."""
    agg: dict[str, list[int]] = defaultdict(lambda: [0, 0, 0])
    for v in m["images"].values():
        r = agg[v["split"]]
        r[0] += 1
        r[1] += bool(v["has_varroa_adult"])
        r[2] += v["n_adult"] > 0
    order = [s for s in SUMMARY_ORDER if s in agg] + sorted(set(agg) - set(SUMMARY_ORDER))
    return [f"[split] {s:<12} images={agg[s][0]} varroa={agg[s][1]} n_adult>0={agg[s][2]}" for s in order]


DEFAULT_FROZEN_COLONIES = Path("training/data/frozen_colonies.json")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--roots", nargs="+", type=Path, required=True)
    p.add_argument("--tags", nargs="+", required=True)
    p.add_argument("--output", type=Path, default=Path("training/split_manifest.json"))
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--frozen", type=Path, default=None, help="기존 manifest — frozen_colonies 유지")
    p.add_argument("--frozen-colonies", dest="frozen_colonies", type=Path, default=DEFAULT_FROZEN_COLONIES,
                   help="동결 colony 파일 (커밋됨). 존재하면 --frozen 또는 --refreeze 없이는 실행 거부")
    p.add_argument("--refreeze", action="store_true",
                   help="golden/cal colony 를 새로 뽑아 동결 파일을 덮어씀 (golden 오염 위험 — 의도적일 때만)")
    p.add_argument("--dedupe-min", dest="dedupe_min", type=float, default=10, help="golden 음성 디듀프 창(분)")
    p.add_argument("--dedupe-min-pos", dest="dedupe_min_pos", type=float, default=1, help="golden 양성 디듀프 창(분)")
    p.add_argument("--golden-varroa-target", dest="golden_varroa_target", type=int, default=100)
    p.add_argument("--cal-varroa-target", dest="cal_varroa_target", type=int, default=50)
    p.add_argument("--max-holdout-share", dest="max_holdout_share", type=float, default=0.5,
                   help="golden+cal 이미지가 전체에서 차지할 수 있는 최대 비율")
    a = p.parse_args(argv)
    if len(a.roots) != len(a.tags):
        p.error("--roots 와 --tags 개수가 같아야 한다")
    if a.frozen and a.refreeze:
        p.error("--frozen 과 --refreeze 는 함께 쓸 수 없다")
    committed = (json.loads(a.frozen_colonies.read_text(encoding="utf-8"))
                 if a.frozen_colonies.exists() else None)
    if committed is not None and not (a.frozen or a.refreeze):
        p.error(f"{a.frozen_colonies} 가 이미 있다 — golden/cal colony 동결 유지: "
                f"--frozen {a.output} 로 재생성하거나, 정말 다시 뽑을 때만 --refreeze")
    frozen = json.loads(a.frozen.read_text(encoding="utf-8"))["frozen_colonies"] if a.frozen else None
    if frozen is not None and committed is not None and frozen != committed:
        p.error(f"--frozen {a.frozen} 의 frozen_colonies 가 {a.frozen_colonies} 와 다르다")
    try:
        items = load_items_from_aihub(a.roots, a.tags)
    except ValueError as e:  # MissingImagesError
        p.error(str(e))
    if not items:
        p.error(f"라벨 0건 — {[str(r / '02.라벨링데이터') for r in a.roots]} 확인")
    m = build_manifest(items, a.seed, dedupe_min=a.dedupe_min, frozen=frozen, dedupe_min_pos=a.dedupe_min_pos,
                       golden_varroa_target=a.golden_varroa_target, cal_varroa_target=a.cal_varroa_target,
                       max_holdout_share=a.max_holdout_share)
    if frozen is not None and m["frozen_colonies"] != frozen:
        p.error("frozen_colonies 가 입력과 달라짐 — 동결 위반")
    a.output.write_text(json.dumps(m, ensure_ascii=False, indent=1), encoding="utf-8")
    a.frozen_colonies.parent.mkdir(parents=True, exist_ok=True)
    a.frozen_colonies.write_text(json.dumps(m["frozen_colonies"], ensure_ascii=False, indent=1), encoding="utf-8")
    print(Counter(v["split"] for v in m["images"].values()))
    for line in split_summary(m):
        print(line, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
