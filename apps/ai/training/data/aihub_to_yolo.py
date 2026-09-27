"""
AI Hub 71667 (꿀벌 질병 진단 이미지 데이터) → Ultralytics YOLO 형식 변환.

스키마 확정 (Sample 검증, 330 이미지 / 4,210 인스턴스):
    - 한 이미지 = 한 JSON (COCO-like)
    - JSON 위치: 02.라벨링데이터/{성충|유충}/{class_folder}/{NNN}/*.json
    - 이미지 위치: 01.원천데이터 (라벨 경로에서 "02.라벨링데이터" → "01.원천데이터", .json → .jpg)
    - 이미지 크기: 1920×1080 고정 (JSON 의 image.width/height 신뢰 가능)
    - bbox 포맷: **`[x1, y1, x2, y2]` 픽셀** (COCO xywh 아님 — 2026-09-23 정정).
      Sample 4210개 중 4208개가 xyxy 면적 공식으로 `area` 필드와 일치.
      `parse_annotations` 가 매 박스를 `area` 로 교차검증한다 (stats 반환).
    - 폴더명 ≠ 라벨: 한 폴더 안에 여러 클래스 인스턴스가 섞여 있음 (정상)

클래스 매핑 (`--mapping`):
    - adult1  (기본, v0.2.0 Stage-1): 성충 3종(4·5·6) → 1-class `bee`. 유충 제외.
    - legacy3 (v0.1.0 호환): 7-class → bee_normal / bee_with_varroa / bee_other_disease.
    - single2 (v0.2.0 단일 스테이지 베이스라인): 성충 정상 → bee_normal(0), 성충 응애 → bee_varroa(1).
      유충·날개불구(6) 제외.

출력 모드:
    - 기본: images/<split>/ (복사 또는 --no-copy 심링크) + labels/<split>/
    - --manifest: 이미지 복사 없이 images_all.txt (한 줄 = 원본 절대 경로) + labels/all/.
      split 은 항상 all — train/val/golden/cal 분할은 split_manifest.json 단계에서.

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

    # v0.2.0 Stage-1: 성충 1-class, 이미지 복사 없는 manifest 모드
    python -m training.data.aihub_to_yolo \\
        --source training/datasets/aihub-71667 \\
        --output training/datasets/bee-adult1 \\
        --mapping adult1 --manifest
"""

from __future__ import annotations

import argparse
import json
import logging
import random
import shutil
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

logger = logging.getLogger(__name__)


# ===== 71667의 7개 category_id → 우리 class 매핑 =====
# 71667 cat: 0 유충_정상 / 1 유충_응애 / 2 유충_석고병 / 3 유충_부저병
#            4 성충_정상 / 5 성충_응애 / 6 성충_날개불구바이러스감염증
# None = 해당 매핑에서 제외.
CLASS_MAPPINGS: dict[str, dict[int, int | None]] = {
    # v0.2.0 Stage-1: 성충만, 1-class `bee`
    "adult1": {0: None, 1: None, 2: None, 3: None, 4: 0, 5: 0, 6: 0},
    # v0.1.0 호환(참고용) — 0 bee_normal / 1 bee_with_varroa / 2 bee_other_disease
    "legacy3": {0: 0, 1: 1, 2: 2, 3: 2, 4: 0, 5: 1, 6: 2},
    # v0.2.0 단일 스테이지 베이스라인(baseline_single.yaml): 0 bee_normal / 1 bee_varroa, 날개불구 제외
    "single2": {0: None, 1: None, 2: None, 3: None, 4: 0, 5: 1, 6: None},
}
DEFAULT_MAPPING = "adult1"

# v0.1.0 호환 별칭 (make_booth_cases.py 등 기존 소비자용)
CLASS_MAPPING: dict[int, int | None] = CLASS_MAPPINGS["legacy3"]

# (cls, x1, y1, x2, y2 픽셀, 71667 category_id, area 교차검증 통과 여부)
Box = tuple[int, float, float, float, float, int, bool]

AREA_REL_TOL = 0.02


def parse_annotations(d: dict, mapping: str) -> tuple[list[Box], dict]:
    """71667 JSON → (boxes, stats). bbox는 [x1,y1,x2,y2] 픽셀. area 필드로 교차검증.

    stats: n_boxes / area_match / area_missing(area 없음·0) / area_mismatch.
    교차검증은 이미지 경계 clip 후 면적 기준이며, 불일치 박스도 버리지 않는다(통계만).
    """
    m = CLASS_MAPPINGS[mapping]
    img = d.get("image", {}) or {}
    W, H = float(img.get("width", 1920)), float(img.get("height", 1080))
    boxes: list[Box] = []
    stats = {"n_boxes": 0, "area_match": 0, "area_missing": 0, "area_mismatch": 0}
    for ann in d.get("annotations", []):
        cat = ann.get("category_id")
        bb = ann.get("bbox")
        if cat not in m or m[cat] is None or not bb or len(bb) != 4:
            continue
        x1, y1, x2, y2 = (float(v) for v in bb)
        x1, y1 = max(0.0, x1), max(0.0, y1)
        x2, y2 = min(W, x2), min(H, y2)
        if x2 - x1 <= 0 or y2 - y1 <= 0:
            continue
        stats["n_boxes"] += 1
        area = ann.get("area")
        if not area:  # None 또는 0
            stats["area_missing"] += 1
            area_ok = False
        else:
            area_ok = abs((x2 - x1) * (y2 - y1) - float(area)) / float(area) < AREA_REL_TOL
            stats["area_match" if area_ok else "area_mismatch"] += 1
        boxes.append((m[cat], x1, y1, x2, y2, int(cat), area_ok))
    return boxes, stats


def yolo_line(cls: int, x1: float, y1: float, x2: float, y2: float, W: float, H: float) -> str:
    """픽셀 xyxy → YOLO normalized `cls cx cy w h`."""
    cw, ch = x2 - x1, y2 - y1
    return f"{cls} {(x1 + cw / 2) / W:.6f} {(y1 + ch / 2) / H:.6f} {cw / W:.6f} {ch / H:.6f}"


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


MAX_MISSING_IMAGE_FRAC = 0.05  # 라벨은 있는데 이미지가 없는 비율 상한 — 넘으면 압축 해제 레이아웃 오류로 본다


class MissingImagesError(ValueError):
    """라벨 대비 이미지 누락이 MAX_MISSING_IMAGE_FRAC 초과 (01.원천데이터/02.라벨링데이터 형제 레이아웃 확인)."""


def check_missing_images(missing: int, total: int, where: str) -> None:
    """누락 수를 로그로 남기고 total 의 5% 초과면 MissingImagesError."""
    if missing:
        logger.warning(f"이미지 없는 라벨 {missing}/{total} ({where})")
    if total and missing / total > MAX_MISSING_IMAGE_FRAC:
        raise MissingImagesError(
            f"이미지 누락 {missing}/{total} ({missing / total:.1%}) > {MAX_MISSING_IMAGE_FRAC:.0%} — "
            f"{where} 아래 {IMAGE_DIR_NAME}/{LABEL_DIR_NAME} 가 같은 루트의 형제인지 확인 (DOWNLOAD.md §6)")


def _parse_one_json(json_path: Path, mapping: str = DEFAULT_MAPPING,
                    reasons: Counter | None = None) -> Sample | None:
    """71667 JSON 1개 → Sample. bbox 해석·매핑은 parse_annotations 단일 소스.
    reasons 가 주어지면 이미지 누락 시 reasons["missing_image"] 를 올린다."""
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
        if reasons is not None:
            reasons["missing_image"] += 1
        return None

    # YOLO 라벨 변환 (bbox = xyxy 픽셀, area 교차검증)
    boxes, area_stats = parse_annotations(d, mapping)
    W, H = float(img_w), float(img_h)
    yolo_lines = [yolo_line(b[0], b[1], b[2], b[3], b[4], W, H) for b in boxes]

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
            # 71667 원 category_id (매핑 전) — split/golden 층화·Stage-2 크롭용
            "cats": [b[5] for b in boxes],
            "has_varroa_adult": any(b[5] == 5 for b in boxes),
            "area_stats": area_stats,
        },
    )


def collect_samples(
    source: Path, limit: int | None = None, seed: int = 42, mapping: str = DEFAULT_MAPPING
) -> list[Sample]:
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

    # ⚠️ label_files 는 경로정렬이라 폴더(클래스/콜로니)별로 뭉쳐 있다.
    #   --limit 으로 앞 N 개만 취하면 특정 폴더에 편중된 비대표 샘플이 된다
    #   (콜로니 001 dominance 75% + 응애 인스턴스 2.4% → 응애 통째 누락 위험).
    #   seed 셔플로 전체 분포를 근사 층화. limit 없으면 전량이라 순서 무관.
    if limit is not None:
        random.Random(seed).shuffle(label_files)

    samples: list[Sample] = []
    skipped = Counter()
    seen = 0
    for jp in label_files:
        seen += 1
        s = _parse_one_json(jp, mapping, reasons=skipped)
        if s is None:
            skipped["parse_or_no_label"] += 1
            continue
        samples.append(s)
        if limit and len(samples) >= limit:
            break

    logger.info(f"수집된 샘플: {len(samples)} (skipped={dict(skipped)})")
    check_missing_images(skipped["missing_image"], seen, str(source))
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


def write_manifest(samples: list[Sample], output: Path, split_name: str) -> Path:
    """이미지 복사 없이 images_<split>.txt (한 줄 = 원본 절대 경로) + labels/<split>/ 작성.

    Ultralytics 는 라벨 경로를 images→labels 치환으로 찾으므로, 원본 경로에 `images`
    세그먼트가 없는 이 모드는 yolo_list_dataset.py 의 img2label_paths 패치와 함께 쓴다.
    """
    lbl_dir = output / "labels" / split_name
    lbl_dir.mkdir(parents=True, exist_ok=True)
    lines = []
    for s in samples:
        (lbl_dir / Path(s.out_filename).with_suffix(".txt").name).write_text(
            "\n".join(s.yolo_lines) + "\n", encoding="utf-8"
        )
        lines.append(str(s.image_path.resolve()))
    mf = output / f"images_{split_name}.txt"
    mf.write_text("\n".join(lines) + "\n", encoding="utf-8")
    logger.info(f"manifest 기록: {len(samples)}건 → {mf}")
    return mf


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
    p.add_argument("--seed", type=int, default=42, help="--limit 적용 시 셔플 seed (대표 샘플)")
    p.add_argument("--no-copy", action="store_true", help="이미지 심볼릭 링크 (디스크 절약)")
    p.add_argument(
        "--split",
        type=str,
        default="all",
        choices=["train", "val", "test", "all"],
        help="all=분할 없이 통째로 (이후 split_strategy.py 사용). --manifest 면 항상 all",
    )
    p.add_argument(
        "--mapping",
        type=str,
        default=DEFAULT_MAPPING,
        choices=sorted(CLASS_MAPPINGS),
        help="adult1=성충 1-class bee (v0.2.0 Stage-1), legacy3=v0.1.0 3-class, single2=단일 스테이지 베이스라인 2-class",
    )
    p.add_argument(
        "--manifest",
        action="store_true",
        help="이미지 복사/심링크 없이 images_all.txt + labels/all/ 작성 (split 은 이후 단계)",
    )
    args = p.parse_args()

    try:
        samples = collect_samples(args.source, limit=args.limit, seed=args.seed, mapping=args.mapping)
    except MissingImagesError as e:
        logger.error(str(e))
        raise SystemExit(2) from None
    if not samples:
        raise SystemExit("샘플 0건. --source 경로 확인.")

    args.output.mkdir(parents=True, exist_ok=True)
    if args.manifest:
        if args.split != "all":
            logger.warning(f"--manifest 는 --split all 고정 (요청 {args.split} 무시)")
        write_manifest(samples, args.output, split_name="all")
    else:
        write_yolo(samples, args.output, split_name=args.split, copy_images=not args.no_copy)
    write_meta(samples, args.output)

    # ===== 통계 리포트 =====
    cls_counter = Counter()
    area_totals = Counter()
    farm_counter = Counter()
    device_counter = Counter()
    for s in samples:
        for line in s.yolo_lines:
            cls_counter[int(line.split()[0])] += 1
        area_totals.update(s.meta.get("area_stats", {}))
        if fid := s.meta.get("farm_id"):
            farm_counter[fid] += 1
        if dev := s.meta.get("capture_device"):
            device_counter[dev] += 1

    cls_names = {
        "adult1": {0: "bee"},
        "single2": {0: "bee_normal", 1: "bee_varroa"},
    }.get(args.mapping, {0: "bee_normal", 1: "bee_with_varroa", 2: "bee_other_disease"})
    print(f"\n===== 변환 통계 (mapping={args.mapping}) =====")
    print(f"이미지: {len(samples)}")
    checked = area_totals["n_boxes"] - area_totals["area_missing"]
    print(
        f"bbox xyxy↔area 교차검증: {area_totals['area_match']}/{checked} 일치 "
        f"(area 누락 {area_totals['area_missing']}, 불일치 {area_totals['area_mismatch']})"
    )
    print("인스턴스 (클래스별):")
    total = sum(cls_counter.values())
    for cid in sorted(cls_counter):
        n = cls_counter[cid]
        print(f"  {cid} {cls_names.get(cid, '?')}: {n} ({n / total:.1%})")
    print(f"\n농가(colony.id) 분포: {len(farm_counter)} 개, top5={farm_counter.most_common(5)}")
    print(f"촬영 기기 분포: {dict(device_counter)}")

    if args.mapping == "adult1":
        n_var = sum(1 for s in samples if s.meta.get("has_varroa_adult"))
        print(f"성충_응애 포함 이미지: {n_var}")
    else:
        # 응애 클래스 인스턴스 수가 적으면 경고 (bbox 전용 라벨이라 copy_paste 는 no-op)
        varroa_n = cls_counter.get(1, 0)
        if varroa_n < total * 0.05:
            print(
                f"\n⚠️ 응애 인스턴스 부족: {varroa_n} ({varroa_n / total:.1%}). "
                f"5% 미만이면 oversampling(mixup/instance resampling) 검토."
            )


if __name__ == "__main__":
    main()
