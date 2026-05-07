"""
Golden holdout 셋 추출 — 모든 모델 버전 비교의 절대 기준.

원칙:
    - 학습/aug에서 영구 제외. 매 모델 버전 동일 셋으로 mAP 비교.
    - 분포 다양성 강제: 양봉장 ≥3, 촬영 기기 ≥2, 응애·정상 균형
    - 71667 외부 데이터(베타 양봉가) 확보되면 그것으로 교체 권장
      (같은 데이터셋 내부 분리는 분포 동질 → 일반화 평가 약함)

Usage:
    python -m training.data.golden_holdout \\
        --input training/datasets/varroa-v1-allraw \\
        --output training/datasets/golden \\
        --n-varroa 100 --n-normal 200 \\
        --min-farms 3 --min-devices 2

검증 후 input/ 에서 해당 이미지 제거 (split_strategy.py 실행 전에).
"""

from __future__ import annotations

import argparse
import json
import logging
import random
import shutil
from collections import Counter, defaultdict
from pathlib import Path

from .split_strategy import Item, _load_items

logger = logging.getLogger(__name__)


def has_varroa_label(label_path: Path, varroa_class_id: int = 1) -> int:
    """라벨 파일에서 varroa(클래스 id=1) 인스턴스 수 반환."""
    n = 0
    for line in label_path.read_text().splitlines():
        if line.strip() and int(line.split()[0]) == varroa_class_id:
            n += 1
    return n


def extract_golden(
    items: list[Item],
    n_varroa: int = 100,
    n_normal: int = 200,
    min_farms: int = 3,
    min_devices: int = 2,
    seed: int = 42,
) -> list[Item]:
    """
    조건을 만족하는 golden 셋 추출.
    - 응애 인스턴스가 1개 이상인 이미지 n_varroa장
    - 응애 0인 이미지(정상만 있는) n_normal장
    - 양봉장 ≥ min_farms, 촬영 기기 ≥ min_devices 강제
    """
    rng = random.Random(seed)
    varroa_pool = [i for i in items if has_varroa_label(i.label) > 0]
    normal_pool = [i for i in items if has_varroa_label(i.label) == 0]
    rng.shuffle(varroa_pool)
    rng.shuffle(normal_pool)

    if len(varroa_pool) < n_varroa:
        logger.warning(
            f"응애 라벨 이미지 부족: {len(varroa_pool)} < 요구 {n_varroa}. "
            f"전체 사용."
        )
        n_varroa = len(varroa_pool)
    if len(normal_pool) < n_normal:
        logger.warning(
            f"정상 라벨 이미지 부족: {len(normal_pool)} < 요구 {n_normal}. "
            f"전체 사용."
        )
        n_normal = len(normal_pool)

    selected: list[Item] = []
    farms_used: set[str] = set()
    devices_used: set[str] = set()

    # 다양성 우선 — round-robin으로 농가/기기 골고루 픽
    def _pick(pool: list[Item], target_n: int):
        nonlocal farms_used, devices_used
        by_farm = defaultdict(list)
        for it in pool:
            by_farm[it.meta.get("farm_id") or "unknown"].append(it)
        farms = list(by_farm.keys())
        rng.shuffle(farms)
        out: list[Item] = []
        i = 0
        while len(out) < target_n and any(by_farm.values()):
            fid = farms[i % len(farms)]
            if by_farm[fid]:
                it = by_farm[fid].pop()
                out.append(it)
                farms_used.add(fid)
                if dev := it.meta.get("capture_device"):
                    devices_used.add(dev)
            i += 1
            if i > 100000:
                break  # safety
        return out

    selected.extend(_pick(varroa_pool, n_varroa))
    selected.extend(_pick(normal_pool, n_normal))

    # 다양성 게이트 검증
    if len(farms_used) < min_farms:
        logger.warning(
            f"⚠️ 농가 다양성 부족: {len(farms_used)} < 요구 {min_farms}. "
            f"71667 외부 데이터 확보 권장."
        )
    if len(devices_used) < min_devices:
        logger.warning(
            f"⚠️ 촬영 기기 다양성 부족: {len(devices_used)} < 요구 {min_devices}."
        )

    logger.info(
        f"golden 추출: 응애 {n_varroa} + 정상 {n_normal} = {len(selected)} 장 "
        f"(농가 {len(farms_used)}, 기기 {len(devices_used)})"
    )
    return selected


def write_golden(items: list[Item], output: Path):
    img_dst = output / "images" / "val"
    lbl_dst = output / "labels" / "val"
    img_dst.mkdir(parents=True, exist_ok=True)
    lbl_dst.mkdir(parents=True, exist_ok=True)
    manifest = []
    for it in items:
        shutil.copy2(it.image, img_dst / it.image.name)
        shutil.copy2(it.label, lbl_dst / it.label.name)
        manifest.append({"image": it.image.name, "meta": it.meta})
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))

    # data.yaml — Ultralytics가 eval에서 사용
    (output / "data.yaml").write_text(
        "path: .\n"
        "val: images/val\n"
        "names:\n  0: bee_normal\n  1: varroa_mite\n"
        "nc: 2\n",
        encoding="utf-8",
    )
    logger.info(f"golden 쓰기 완료: {output}")


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    p = argparse.ArgumentParser()
    p.add_argument("--input", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--n-varroa", type=int, default=100)
    p.add_argument("--n-normal", type=int, default=200)
    p.add_argument("--min-farms", type=int, default=3)
    p.add_argument("--min-devices", type=int, default=2)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()

    items = _load_items(args.input)
    if not items:
        raise SystemExit("입력에서 아이템 0개.")

    selected = extract_golden(
        items,
        n_varroa=args.n_varroa,
        n_normal=args.n_normal,
        min_farms=args.min_farms,
        min_devices=args.min_devices,
        seed=args.seed,
    )
    write_golden(selected, args.output)

    # 분포 리포트
    cls_counter = Counter()
    for it in selected:
        for line in it.label.read_text().splitlines():
            if line.strip():
                cls_counter[int(line.split()[0])] += 1
    print("\n===== Golden 통계 =====")
    print(f"이미지: {len(selected)}")
    print(f"인스턴스: {dict(cls_counter)}")


if __name__ == "__main__":
    main()
