"""
AI Hub 71667 (꿀벌 질병 진단 이미지 데이터) → Ultralytics YOLO 형식 변환.

스키마 확정 (Sample 검증, 330 이미지 / 4,210 인스턴스):
    - 한 이미지 = 한 JSON (COCO-like)
    - JSON 위치: 02.라벨링데이터/{성충|유충}/{class_folder}/{NNN}/*.json
    - 이미지 위치: 01.원천데이터 (라벨 경로에서 "02.라벨링데이터" → "01.원천데이터", .json → .jpg)
    - 이미지 크기: 1920×1080 고정 (JSON 의 image.width/height 신뢰 가능)
    - bbox 포맷: COCO `[x, y, w, h]` (left-top + size, 픽셀)
    - 폴더명 ≠ 라벨: 한 폴더 안에 여러 클래스 인스턴스가 섞여 있음 (정상)

⚠️ Q3 답: 케이스 B (감염된 벌 영역의 bbox). 응애 자체의 bbox는 0개.
   → 클래스 의미는 "응애 객체"가 아닌 "응애가 보이는 벌 영역".

상세: apps/ai/training/datasets/AIHUB_71667.md

Usage:
    # Sample 폴더로 테스트 (330장)
    python -m training.data.aihub_to_yolo \\
        --source training/datasets/Sample \\
        --output training/datasets/varroa-v1-allraw \\
        --split all

    # 풀 데이터셋 5,000장
    python -m training.data.aihub_to_yolo \\
        --source training/datasets/aihub-71667 \\
        --output training/datasets/varroa-v1-allraw \\
        --split all \\
        --limit 5000
"""

from __future__ import annotations

import argparse
import json
import logging
import shutil
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)


# ===== 71667의 7개 category_id → 우리 3-class detection 매핑 =====
# v0.1.0 MVP: Q1' 결정 = B+ (3-class)
#   0: bee_normal         (정상 벌/유충)
#   1: bee_with_varroa    (응애가 보이는 벌 영역)
#   2: bee_other_disease  (날개불구·부저병·석고병 — 다른 질병 통합)
#
# 다른 클래스를 학습 데이터에 포함하는 이유:
#   - 응애만 학습하고 질병 영역을 배경으로 두면 모델이 다른 질병을 false positive로 학습
#   - 3-class로 명시 학습 → 응애 정확도 자체도 향상
#   - v0.2.0+ 에서 7-class 분리 시 자연스러운 확장 경로
CLASS_MAPPING: dict[int, int | None] = {
    0: 0,  # 유충_정상       → bee_normal
    1: 1,  # 유충_응애       → bee_with_varroa
    2: 2,  # 유충_석고병     → bee_other_disease
    3: 2,  # 유충_부저병     → bee_other_disease
    4: 0,  # 성충_정상       → bee_normal
    5: 1,  # 성충_응애       → bee_with_varroa
    6: 2,  # 성충_날개불구   → bee_other_disease
}

# 71667의 라벨/이미지 디렉터리 명 (한국어 그대로)
LABEL_DIR_NAME = "02.라벨링데이터"
IMAGE_DIR_NAME = "01.원천데이터"


@dataclass
class Sample:
    """변환 결과 — 분할 전 단일 이미지 단위."""

    image_path: Path  # source 절대 경로
    out_filename: str  # output 에 쓸 파일명 (충돌 방지를 위해 고유화)
    yolo_lines: list[str] = field(default_factory=list)
    meta: dict = field(default_factory=dict)


def _resolve_image_path(json_path: Path, image_filename: str) -> Path | None:
    """
    JSON 경로에서 라벨 디렉터리를 이미지 디렉터리로 치환해 image 경로 추론.

    예: 02.라벨링데이터/성충/성충_응애/044/X.json
      → 01.원천데이터/성충/성충_응애/044/X.jpg
    """
    parts = list(json_path.parts)
    try:
        idx = parts.index(LABEL_DIR_NAME)
    except ValueError:
        # 표준 경로 아님 — JSON 같은 폴더에 이미지 있을 가능성
        sibling = json_path.with_suffix(".jpg")
        return sibling if sibling.exists() else None
    parts[idx] = IMAGE_DIR_NAME
    image_path = Path(*parts).with_name(image_filename)
    return image_path if image_path.exists() else None


def _unique_filename(json_path: Path, image_filename: str) -> str:
    """파일명 충돌 방지 — 폴더 NNN 을 prefix로.

    원본 파일명 안에 colony.id, datetime이 이미 들어있어 사실상 unique 하지만
    safety 차원에서 부모 폴더(NNN) prefix 추가.
    """
    parent_id = json_path.parent.name  # NNN
    stem = Path(image_filename).stem
    suffix = Path(image_filename).suffix or ".jpg"
    return f"{parent_id}_{stem}{suffix}"


def _parse_one_json(json_path: Path) -> Sample | None:
    """71667 JSON 1개 → Sample. 스키마 확정 후 안정적."""
    try:
        d = json.loads(json_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        logger.warning(f"JSON parse fail: {json_path}: {e}")
        return None

    # 필수 필드 검증
    img = d.get("image", {})
    img_w = img.get("width")
    img_h = img.get("height")
    image_filename = img.get("filename")
    if not (img_w and img_h and image_filename):
        logger.debug(f"image meta 누락: {json_path}")
        return None

    image_path = _resolve_image_path(json_path, image_filename)
    if image_path is None:
        logger.warning(f"image 파일 없음: {image_filename} (label: {json_path})")
        return None

    # YOLO 라벨 변환
    yolo_lines: list[str] = []
    skipped_cats = Counter()
    for ann in d.get("annotations", []):
        cid_71667 = ann.get("category_id")
        if cid_71667 is None or cid_71667 not in CLASS_MAPPING:
            skipped_cats[cid_71667] += 1
            continue
        our_cls = CLASS_MAPPING[cid_71667]
        if our_cls is None:
            skipped_cats[cid_71667] += 1
            continue

        bbox = ann.get("bbox")
        if not bbox or len(bbox) != 4:
            continue
        x, y, w, h = bbox  # COCO 표준
        if w <= 0 or h <= 0:
            continue

        # YOLO normalized: cx, cy, w, h
        cx = (x + w / 2) / img_w
        cy = (y + h / 2) / img_h
        nw = w / img_w
        nh = h / img_h
        # 경계 클램프 (1.0 초과 라벨 방어)
        if not (0 < nw <= 1.0 and 0 < nh <= 1.0):
            continue
        cx = max(0.0, min(1.0, cx))
        cy = max(0.0, min(1.0, cy))
        yolo_lines.append(f"{our_cls} {cx:.6f} {cy:.6f} {nw:.6f} {nh:.6f}")

    if not yolo_lines:
        # 라벨 0개 이미지 — v0.1.0은 스킵.
        # v0.2.0+ 에서 hard negative ratio 튜닝 검토.
        return None

    # 메타 추출 — split_strategy 가 사용
    collection = d.get("collection", {}) or {}
    colony = d.get("colony", {}) or {}

    return Sample(
        image_path=image_path,
        out_filename=_unique_filename(json_path, image_filename),
        yolo_lines=yolo_lines,
        meta={
            "image_filename": image_filename,
            # split_strategy.py 가 기대하는 키들 (도메인 추상화)
            "farm_id": colony.get("id"),  # 71667 colony.id 가 농가 ID
            "capture_device": collection.get("device"),  # 소비판/플레이트/소문 촬영기
            "captured_at": collection.get("datetime"),  # YYYYMMDD_HHmmss_NNN
            # 71667 고유 — 디버그/v0.2.0 분석용
            "colony_type": colony.get("type"),
            "weather": collection.get("weather"),
            "label_folder": json_path.parent.parent.name,  # 성충_응애 등
        },
    )


def collect_samples(source: Path, limit: int | None = None) -> list[Sample]:
    """
    source 트리에서 02.라벨링데이터 안의 모든 JSON → Sample.
    source 가 라벨/이미지 부모인 경우와 라벨 폴더 자체인 경우 모두 처리.
    """
    if (source / LABEL_DIR_NAME).exists():
        label_root = source / LABEL_DIR_NAME
    elif source.name == LABEL_DIR_NAME:
        label_root = source
    else:
        # source 자체에서 .json 모두 검색 (custom layout)
        label_root = source

    label_files = sorted(label_root.rglob("*.json"))
    logger.info(f"발견된 JSON 라벨: {len(label_files)} (루트: {label_root})")

    samples: list[Sample] = []
    skipped = Counter()
    for jp in label_files:
        s = _parse_one_json(jp)
        if s is None:
            skipped["parse_or_no_label"] += 1
            continue
        samples.append(s)
        if limit and len(samples) >= limit:
            break

    logger.info(f"수집된 샘플: {len(samples)} (skipped={dict(skipped)})")
    return samples


def write_yolo(samples: list[Sample], output: Path, split_name: str, copy_images: bool = True):
    """images/{split}, labels/{split} 에 작성."""
    img_dir = output / "images" / split_name
    lbl_dir = output / "labels" / split_name
    img_dir.mkdir(parents=True, exist_ok=True)
    lbl_dir.mkdir(parents=True, exist_ok=True)

    for s in samples:
        dst_img = img_dir / s.out_filename
        dst_lbl = lbl_dir / Path(s.out_filename).with_suffix(".txt").name
        if not dst_img.exists():
            if copy_images:
                shutil.copy2(s.image_path, dst_img)
            else:
                dst_img.symlink_to(s.image_path.resolve())
        dst_lbl.write_text("\n".join(s.yolo_lines) + "\n", encoding="utf-8")

    logger.info(f"기록 완료: {len(samples)}건 → {img_dir}")


def write_meta(samples: list[Sample], output: Path):
    """split_strategy.py 가 사용할 메타 사이드카 (out_filename 키)."""
    meta_path = output / "_meta.json"
    payload = {s.out_filename: s.meta for s in samples}
    meta_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    logger.info(f"메타 기록: {meta_path}")


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    p = argparse.ArgumentParser()
    p.add_argument("--source", type=Path, required=True, help="71667 루트 (Sample 또는 풀)")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--limit", type=int, default=None)
    p.add_argument("--no-copy", action="store_true", help="이미지 심볼릭 링크 (디스크 절약)")
    p.add_argument(
        "--split",
        type=str,
        default="all",
        choices=["train", "val", "test", "all"],
        help="all=분할 없이 통째로 (이후 split_strategy.py 사용)",
    )
    args = p.parse_args()

    samples = collect_samples(args.source, limit=args.limit)
    if not samples:
        raise SystemExit("샘플 0건. --source 경로 확인.")

    write_yolo(samples, args.output, split_name=args.split, copy_images=not args.no_copy)
    write_meta(samples, args.output)

    # ===== 통계 리포트 =====
    cls_counter = Counter()
    farm_counter = Counter()
    device_counter = Counter()
    for s in samples:
        for line in s.yolo_lines:
            cls_counter[int(line.split()[0])] += 1
        if fid := s.meta.get("farm_id"):
            farm_counter[fid] += 1
        if dev := s.meta.get("capture_device"):
            device_counter[dev] += 1

    cls_names = {0: "bee_normal", 1: "bee_with_varroa", 2: "bee_other_disease"}
    print("\n===== 변환 통계 =====")
    print(f"이미지: {len(samples)}")
    print("인스턴스 (클래스별):")
    total = sum(cls_counter.values())
    for cid in sorted(cls_counter):
        n = cls_counter[cid]
        print(f"  {cid} {cls_names.get(cid, '?')}: {n} ({n / total:.1%})")
    print(f"\n농가(colony.id) 분포: {len(farm_counter)} 개, top5={farm_counter.most_common(5)}")
    print(f"촬영 기기 분포: {dict(device_counter)}")

    # 응애 클래스 인스턴스 수가 적으면 경고 (Copy-Paste augmentation 권장 임계)
    varroa_n = cls_counter.get(1, 0)
    if varroa_n < total * 0.05:
        print(
            f"\n⚠️ 응애 인스턴스 부족: {varroa_n} ({varroa_n / total:.1%}). "
            f"yolo.yaml 의 copy_paste 0.3 유지 권장. 5% 미만이면 oversampling 검토."
        )


if __name__ == "__main__":
    main()
