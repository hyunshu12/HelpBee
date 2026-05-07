"""
71667 데이터 분할 — data leakage 방지.

핵심 원칙:
    같은 벌통/같은 농가 사진이 train/val 양쪽에 들어가면 mAP가 거짓말함.
    무작위 분할(random.shuffle) 절대 금지.

전략 (메타 풍부도 + 농가 imbalance 자동 감지):
    1. per_colony_time_block (★ default 권장):
       각 colony 내에서 시간 순으로 마지막 val_ratio% 를 val.
       colony 단위 누수 차단 + 한 농가가 75% 차지하는 71667 imbalance 대응.
    2. farm_group:
       양봉장(colony.id) 단위. 같은 농가 한쪽으로만.
       imbalanced 농가에서는 train/val 비율이 의도와 크게 어긋날 수 있음.
    3. device_holdout:
       촬영 기기 단위. 한 기기를 통째로 val.
       device generalization 평가용.
    4. sequence_block:
       시간 블록. 같은 세션 한쪽으로.
    5. random:
       ⚠️ Fallback only. 메타 전혀 없을 때만.

상세: apps/ai/training/datasets/AIHUB_71667.md §분할 전략

Usage:
    python -m training.data.split_strategy \\
        --input training/datasets/varroa-v1-allraw \\
        --output training/datasets/varroa-v1 \\
        --val-ratio 0.2 \\
        --seed 42
"""

from __future__ import annotations

import argparse
import json
import logging
import random
import shutil
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)


@dataclass
class Item:
    """이미지 1장 + 메타. aihub_to_yolo.py 출력의 양면 + _meta.json 사이드카."""

    image: Path
    label: Path
    meta: dict


def _load_items(input_root: Path) -> list[Item]:
    """
    aihub_to_yolo.py 결과 디렉터리에서 이미지/라벨/메타 수집.

    구조:
        {input_root}/images/{train|val|test|all}/*.jpg
        {input_root}/labels/{train|val|test|all}/*.txt
        {input_root}/_meta.json   (aihub_to_yolo.py 가 생성)
    """
    # split 폴더 자동 감지 ('all' 우선, 없으면 train)
    img_dir = None
    for cand in ["all", "train"]:
        d = input_root / "images" / cand
        if d.exists():
            img_dir = d
            lbl_dir = input_root / "labels" / cand
            break
    if img_dir is None:
        raise SystemExit(f"images/all 또는 images/train 폴더 없음: {input_root}")

    meta_file = input_root / "_meta.json"
    meta_map: dict[str, dict] = {}
    if meta_file.exists():
        meta_map = json.loads(meta_file.read_text(encoding="utf-8"))
    else:
        logger.warning(
            f"_meta.json 없음 — 메타 정보 없이 진행. "
            f"farm/device/sequence 분할 불가, random fallback 됨."
        )

    items: list[Item] = []
    for img_path in sorted(img_dir.iterdir()):
        if not img_path.is_file():
            continue
        lbl_path = lbl_dir / img_path.with_suffix(".txt").name
        if not lbl_path.exists():
            continue
        items.append(
            Item(image=img_path, label=lbl_path, meta=meta_map.get(img_path.name, {}))
        )
    logger.info(f"로드된 아이템: {len(items)} (메타 매칭 {sum(1 for i in items if i.meta)}건)")
    return items


def detect_strategy(items: list[Item]) -> str:
    """메타 + 분포로 최적 전략 자동 선택."""
    if not items:
        return "random"

    farm_n = sum(1 for i in items if i.meta.get("farm_id"))
    dev_n = sum(1 for i in items if i.meta.get("capture_device"))
    ts_n = sum(1 for i in items if i.meta.get("captured_at"))
    farm_ratio = farm_n / len(items)

    # farm_id + timestamp 둘 다 풍부 → per_colony_time_block (가장 정확)
    if farm_ratio > 0.8 and ts_n / len(items) > 0.8:
        # 농가 분포 imbalance 검사
        farms = Counter(i.meta["farm_id"] for i in items if i.meta.get("farm_id"))
        max_farm_ratio = max(farms.values()) / len(items)
        if max_farm_ratio > 0.5:
            logger.info(
                f"농가 분포 imbalanced (top farm = {max_farm_ratio:.1%}) "
                f"→ per_colony_time_block 강력 추천"
            )
        return "per_colony_time_block"

    if farm_ratio > 0.8:
        return "farm_group"
    if dev_n / len(items) > 0.8:
        return "device_holdout"
    if ts_n / len(items) > 0.8:
        return "sequence_block"
    logger.warning(
        "⚠️ 메타가 부족 — random fallback. aihub_to_yolo.py 메타 추출 확인 권장."
    )
    return "random"


# ===== 전략 구현 =====
def split_per_colony_time_block(
    items: list[Item], val_ratio: float
) -> tuple[list[Item], list[Item]]:
    """
    각 colony 내에서 시간 순으로 마지막 val_ratio% 를 val.

    이점:
        - colony 단위 누수 차단 (다른 colony는 train/val 한쪽에만 있는 게 아니라
          모든 colony 가 양쪽에 시간으로 분리되어 들어감)
        - 한 농가가 75% 차지해도 그 농가의 80%는 train, 20%는 val 로 균형
        - 시간 분리로 같은 세션 누수 방지

    가정: meta['captured_at'] 가 정렬 가능한 문자열 (ISO 또는 YYYYMMDD_...)
    """
    by_colony: dict[str, list[Item]] = defaultdict(list)
    for it in items:
        fid = it.meta.get("farm_id") or "unknown"
        by_colony[fid].append(it)

    train, val = [], []
    summary = []
    for cid, lst in by_colony.items():
        s = sorted(lst, key=lambda i: i.meta.get("captured_at") or "")
        n_val = max(1, int(len(s) * val_ratio))
        train_part = s[:-n_val]
        val_part = s[-n_val:]
        train.extend(train_part)
        val.extend(val_part)
        summary.append((cid, len(train_part), len(val_part)))

    summary.sort(key=lambda x: -(x[1] + x[2]))
    logger.info("per_colony_time_block 분포:")
    for cid, t, v in summary[:10]:
        logger.info(f"  colony={cid}: train={t}, val={v}")
    logger.info(f"총합: train={len(train)}, val={len(val)} ({len(val) / len(items):.1%})")
    return train, val


def split_farm_group(
    items: list[Item], val_ratio: float, seed: int
) -> tuple[list[Item], list[Item]]:
    """양봉장(colony.id) 단위 — 같은 농가 한쪽으로만."""
    farms: dict[str, list[Item]] = defaultdict(list)
    for it in items:
        farms[it.meta.get("farm_id") or "unknown"].append(it)

    farm_ids = list(farms.keys())
    rng = random.Random(seed)
    rng.shuffle(farm_ids)

    val_n = max(1, int(len(farm_ids) * val_ratio))
    val_farms = set(farm_ids[:val_n])
    train, val = [], []
    for fid, lst in farms.items():
        (val if fid in val_farms else train).extend(lst)
    logger.info(
        f"farm_group: {len(farm_ids)} 농가 → val={len(val_farms)} 농가 / "
        f"train={len(train)} imgs, val={len(val)} imgs ({len(val) / len(items):.1%})"
    )
    return train, val


def split_device_holdout(
    items: list[Item], val_device: str | None
) -> tuple[list[Item], list[Item]]:
    """촬영 기기 단위 — 한 기기 통째로 val. None 이면 가장 적은 빈도 기기."""
    by_device: dict[str, list[Item]] = defaultdict(list)
    for it in items:
        by_device[it.meta.get("capture_device") or "unknown"].append(it)
    if val_device is None:
        val_device = min(by_device, key=lambda d: len(by_device[d]))
    val = by_device.pop(val_device)
    train = [i for lst in by_device.values() for i in lst]
    logger.info(
        f"device_holdout: val_device={val_device} ({len(val)} imgs), "
        f"train={len(train)} imgs (devices={list(by_device.keys())})"
    )
    return train, val


def split_sequence_block(
    items: list[Item], val_ratio: float
) -> tuple[list[Item], list[Item]]:
    """전체 시간순으로 마지막 val_ratio% 를 val."""
    s = sorted(items, key=lambda i: i.meta.get("captured_at") or "")
    n_val = max(1, int(len(s) * val_ratio))
    train, val = s[:-n_val], s[-n_val:]
    logger.info(f"sequence_block: train={len(train)}, val={len(val)} (last {val_ratio:.0%})")
    return train, val


def split_random(
    items: list[Item], val_ratio: float, seed: int
) -> tuple[list[Item], list[Item]]:
    """⚠️ Fallback. leakage 위험."""
    s = list(items)
    random.Random(seed).shuffle(s)
    n_val = max(1, int(len(s) * val_ratio))
    return s[n_val:], s[:n_val]


# ===== Output =====
def write_split(items: list[Item], output: Path, split_name: str):
    img_dst = output / "images" / split_name
    lbl_dst = output / "labels" / split_name
    img_dst.mkdir(parents=True, exist_ok=True)
    lbl_dst.mkdir(parents=True, exist_ok=True)
    for it in items:
        shutil.copy2(it.image, img_dst / it.image.name)
        shutil.copy2(it.label, lbl_dst / it.label.name)
    logger.info(f"기록: {len(items)} → {img_dst}")


def cls_distribution(items: list[Item]) -> dict[int, int]:
    c: Counter = Counter()
    for it in items:
        for line in it.label.read_text().splitlines():
            if line.strip():
                c[int(line.split()[0])] += 1
    return dict(c)


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    p = argparse.ArgumentParser()
    p.add_argument("--input", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--val-ratio", type=float, default=0.2)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument(
        "--strategy",
        type=str,
        default="auto",
        choices=[
            "auto",
            "per_colony_time_block",
            "farm_group",
            "device_holdout",
            "sequence_block",
            "random",
        ],
    )
    p.add_argument("--val-device", type=str, default=None, help="device_holdout 강제 지정")
    args = p.parse_args()

    items = _load_items(args.input)
    if not items:
        raise SystemExit("입력 0건")

    strategy = args.strategy if args.strategy != "auto" else detect_strategy(items)
    logger.info(f"=== strategy = {strategy} (n={len(items)}) ===")

    if strategy == "per_colony_time_block":
        train, val = split_per_colony_time_block(items, args.val_ratio)
    elif strategy == "farm_group":
        train, val = split_farm_group(items, args.val_ratio, args.seed)
    elif strategy == "device_holdout":
        train, val = split_device_holdout(items, args.val_device)
    elif strategy == "sequence_block":
        train, val = split_sequence_block(items, args.val_ratio)
    else:
        train, val = split_random(items, args.val_ratio, args.seed)

    write_split(train, args.output, "train")
    write_split(val, args.output, "val")

    # _meta.json 도 복사 (eval 시 사용 가능)
    meta_src = args.input / "_meta.json"
    if meta_src.exists():
        shutil.copy2(meta_src, args.output / "_meta.json")

    print("\n===== Split 통계 =====")
    print(f"strategy: {strategy}")
    print(f"train: {len(train)} 이미지, 인스턴스 {cls_distribution(train)}")
    print(f"val  : {len(val)} 이미지, 인스턴스 {cls_distribution(val)}")


if __name__ == "__main__":
    main()
