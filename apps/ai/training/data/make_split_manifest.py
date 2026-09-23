# apps/ai/training/data/make_split_manifest.py
"""단일 split 진실 소스. golden/cal-A/cal-B는 colony 홀드아웃, train/val은 colony 내 시간 블록.

- golden: 10분 디듀프 (같은 colony·device 에서 직전 채택 프레임과 10분 미만이면 dropped_dup)
- frozen_colonies: 한 번 정해지면 `--frozen` 으로 재생성해도 유지 (Training 셋 추가 시)
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


def build_manifest(items: list[dict], seed: int, golden_frac=0.10, cal_frac=0.15, dedupe_min=10,
                   frozen: dict | None = None) -> dict:
    rng = random.Random(seed)
    colonies = sorted({i["colony"] for i in items})
    if frozen:
        g, a, b = (list(frozen[k]) for k in ("golden", "cal_a", "cal_b"))
    else:
        with_v = sorted({i["colony"] for i in items if i["has_varroa_adult"]})
        rng.shuffle(with_v)
        rest = [c for c in colonies if c not in with_v]
        rng.shuffle(rest)
        n_g = max(3, round(len(colonies) * golden_frac))
        n_c = max(2, round(len(colonies) * cal_frac))
        g = (with_v[:3] + rest)[:n_g]
        pool = [c for c in colonies if c not in g]
        rng.shuffle(pool)
        half = max(1, n_c // 2)
        a, b = pool[:half], pool[half:half * 2]
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
                key = (col, it["device"])
                prev = last.get(key)
                s = split
                if split == "golden" and prev is not None and (it["ts"] - prev).total_seconds() < dedupe_min * 60:
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
    from training.data.aihub_to_yolo import _resolve_image_path, parse_annotations
    items = []
    for root, tag in zip(roots, source_tags):
        for jp in (root / "02.라벨링데이터").rglob("*.json"):
            d = json.loads(jp.read_text(encoding="utf-8"))
            img = _resolve_image_path(jp, d["image"]["filename"])
            if img is None:
                continue
            boxes, _ = parse_annotations(d, "adult1")
            ts = d.get("collection", {}).get("datetime", "")[:15]
            try:
                t = datetime.strptime(ts, "%Y%m%d_%H%M%S")
            except ValueError:
                continue
            items.append({"image": str(img.resolve()), "colony": str(d.get("colony", {}).get("id")),
                          "device": d.get("collection", {}).get("device", ""), "ts": t,
                          "has_varroa_adult": any(b[5] == 5 for b in boxes), "n_adult": len(boxes), "source": tag})
    return items


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--roots", nargs="+", type=Path, required=True)
    p.add_argument("--tags", nargs="+", required=True)
    p.add_argument("--output", type=Path, default=Path("training/split_manifest.json"))
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--frozen", type=Path, default=None, help="기존 manifest — frozen_colonies 유지")
    a = p.parse_args()
    if len(a.roots) != len(a.tags):
        p.error("--roots 와 --tags 개수가 같아야 한다")
    frozen = json.loads(a.frozen.read_text(encoding="utf-8"))["frozen_colonies"] if a.frozen else None
    items = load_items_from_aihub(a.roots, a.tags)
    if not items:
        p.error(f"라벨 0건 — {[str(r / '02.라벨링데이터') for r in a.roots]} 확인")
    m = build_manifest(items, a.seed, frozen=frozen)
    a.output.write_text(json.dumps(m, ensure_ascii=False, indent=1), encoding="utf-8")
    Path("training/data/frozen_colonies.json").write_text(
        json.dumps(m["frozen_colonies"], ensure_ascii=False, indent=1), encoding="utf-8")
    print(Counter(v["split"] for v in m["images"].values()))


if __name__ == "__main__":
    main()
