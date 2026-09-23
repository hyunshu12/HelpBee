"""
Golden holdout 셋 선택 — 모든 모델 버전 비교의 절대 기준.

`split_manifest.json`(make_split_manifest.py 산출물)에서 `split=="golden"` 이미지만 골라
원본 71667 JSON category 기반 필드(`has_varroa_adult`, `n_adult`)로 응애/정상을 나눈다.
YOLO 라벨 txt(클래스 id)는 더 이상 읽지 않는다 — 1-class(bee) 변환 후엔 응애를 구분할 수 없음.

원칙:
    - 학습/aug에서 영구 제외 (golden colony 는 split manifest 에서 이미 홀드아웃·동결됨).
    - varroa = 성충_응애(category_id==5) 포함 이미지, normal = 성충 ≥1 & 응애 없음.
    - 분포 다양성 강제: colony ≥3, 촬영 기기 ≥2 (부족하면 ValueError).
    - 이미지 복사 없음 — 선택 결과(경로 목록)만 JSON 으로 기록.

Usage:
    python -m training.data.golden_holdout \\
        --manifest training/split_manifest.json \\
        --output training/golden.json \\
        --n-varroa 100 --n-normal 200
"""

from __future__ import annotations

import argparse
import json
import logging
import random
from pathlib import Path

logger = logging.getLogger(__name__)


def select_golden(
    manifest: dict,
    n_varroa: int = 100,
    n_normal: int = 200,
    seed: int = 42,
    min_colonies: int = 3,
    min_devices: int = 2,
) -> dict[str, list[str]]:
    """manifest 의 golden split 에서 응애 n_varroa / 정상 n_normal 장 선택."""
    rng = random.Random(seed)
    pool = [(p, v) for p, v in manifest["images"].items() if v["split"] == "golden"]
    var = [p for p, v in pool if v["has_varroa_adult"]]
    nor = [p for p, v in pool if not v["has_varroa_adult"] and v["n_adult"] > 0]
    rng.shuffle(var)
    rng.shuffle(nor)
    if len(var) < n_varroa or len(nor) < n_normal:
        logger.warning(f"golden 후보 부족: 응애 {len(var)}/{n_varroa}, 정상 {len(nor)}/{n_normal} — 가능한 만큼 사용")
    sel = {"varroa": var[:n_varroa], "normal": nor[:n_normal]}
    chosen = [manifest["images"][p] for p in sel["varroa"] + sel["normal"]]
    n_col = len({v["colony"] for v in chosen})
    n_dev = len({v["device"] for v in chosen})
    if n_col < min_colonies or n_dev < min_devices:
        raise ValueError(
            f"golden 다양성 부족: colony {n_col} (≥{min_colonies}), device {n_dev} (≥{min_devices}) 확인"
        )
    return sel


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--n-varroa", type=int, default=100)
    p.add_argument("--n-normal", type=int, default=200)
    p.add_argument("--min-colonies", type=int, default=3)
    p.add_argument("--min-devices", type=int, default=2)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args(argv)

    if not args.manifest.is_file():
        print(
            f"split manifest 없음: {args.manifest} — 먼저 `python tasks.py split` 로 생성하세요.",
            flush=True,
        )
        return 2
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    sel = select_golden(
        manifest,
        n_varroa=args.n_varroa,
        n_normal=args.n_normal,
        seed=args.seed,
        min_colonies=args.min_colonies,
        min_devices=args.min_devices,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(sel, ensure_ascii=False, indent=2), encoding="utf-8")
    logger.info(f"golden 선택 완료: 응애 {len(sel['varroa'])} + 정상 {len(sel['normal'])} → {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
