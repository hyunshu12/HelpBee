"""추론 전 이미지 정규화 (in-memory).

설계 근거: backend-design §3.3, apps/ai/CLAUDE.md §7-4.
파이프라인:
  1. EXIF orientation 적용 후 strip
  2. RGBA/LA/P → RGB 평탄화 (흰 배경)
  3. HEIC → JPEG (pillow-heif, 설치 시에만)
  4. 긴 변 1024px 다운스케일 (LANCZOS, 업스케일 안 함)
  5. JPEG q=95 인코딩 (아래 QUALITY_CASCADE 참조)
  6. 10MB 가드 — 초과 시 q90→q85 순차 다운, 그래도 초과면 ImageTooLargeError
"""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO

from PIL import Image, ImageOps

# HEIC 지원은 선택적 — libheif 없는 환경에서도 나머지 파이프라인은 동작.
try:  # pragma: no cover - 환경 의존
    import pillow_heif

    pillow_heif.register_heif_opener()
    HEIF_SUPPORTED = True
except Exception:  # pragma: no cover
    HEIF_SUPPORTED = False

MAX_BYTES = 10 * 1024 * 1024
MAX_EDGE = 1024
# q95 인코딩. q85는 응애의 미세 신호를 약화시켜 YOLO 검출 앵커의 argmax를
# varroa→normal로 뒤집어 false negative(safe 오진)를 유발 → train/serve skew.
# (golden eval은 원본을 직접 letterbox해 이 재압축을 안 거침.) 단일 이미지 측정:
# q85 varroa 0 (safe) → q95 varroa 1 (watch), 동일 normal 셋에서 FP 증가 0.
# 정식 라벨 기반 golden 서빙경로 평가는 후속 과제. 공유 전처리라 OpenAI 경로도 q95 사용.
QUALITY_CASCADE = (95, 90, 85)


class ImageDecodeError(Exception):
    """디코드 불가(손상/미지원 포맷)."""


class ImageTooLargeError(Exception):
    """q-cascade 후에도 크기 한도 초과."""


@dataclass
class Preprocessed:
    jpeg: bytes
    width: int
    height: int


def _flatten_to_rgb(img: Image.Image) -> Image.Image:
    if img.mode == "RGB":
        return img
    if img.mode in ("RGBA", "LA", "P"):
        rgba = img.convert("RGBA")
        bg = Image.new("RGB", rgba.size, (255, 255, 255))
        bg.paste(rgba, mask=rgba.split()[-1])
        return bg
    return img.convert("RGB")


def preprocess_image(
    data: bytes,
    *,
    max_edge: int = MAX_EDGE,
    max_bytes: int = MAX_BYTES,
    quality_cascade: tuple[int, ...] = QUALITY_CASCADE,
) -> Preprocessed:
    try:
        img = Image.open(BytesIO(data))
        img.load()
    except Exception as exc:  # noqa: BLE001 - 모든 디코드 실패를 도메인 에러로
        raise ImageDecodeError(str(exc)) from exc

    img = ImageOps.exif_transpose(img)  # orientation 적용 (+ 태그 제거)
    img = _flatten_to_rgb(img)

    w, h = img.size
    longest = max(w, h)
    if longest > max_edge:
        scale = max_edge / longest
        img = img.resize(
            (max(1, round(w * scale)), max(1, round(h * scale))),
            Image.Resampling.LANCZOS,
        )

    for quality in quality_cascade:
        buf = BytesIO()
        img.save(buf, format="JPEG", quality=quality, optimize=True)  # exif 미전달 → strip
        encoded = buf.getvalue()
        if len(encoded) <= max_bytes:
            return Preprocessed(jpeg=encoded, width=img.width, height=img.height)

    raise ImageTooLargeError(
        f"image still exceeds {max_bytes} bytes after quality cascade {quality_cascade}"
    )
