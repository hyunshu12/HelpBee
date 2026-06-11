"""B3 preprocess.py — 추론 전 이미지 정규화.

근거: backend-design §3.3, apps/ai/CLAUDE.md §7-4
(EXIF strip/orientation, RGBA→RGB, 1024px LANCZOS, JPEG q85, 10MB 가드).
"""

from io import BytesIO

import pytest
from PIL import Image

from app.services.preprocess import (
    ImageDecodeError,
    ImageTooLargeError,
    Preprocessed,
    preprocess_image,
)


def _jpeg(w: int, h: int, color="red", mode="RGB", exif=None) -> bytes:
    img = Image.new(mode, (w, h), color)
    buf = BytesIO()
    if exif is not None:
        img.save(buf, "JPEG", exif=exif)
    else:
        img.save(buf, "JPEG")
    return buf.getvalue()


def _png_rgba(w: int, h: int) -> bytes:
    img = Image.new("RGBA", (w, h), (10, 20, 30, 128))
    buf = BytesIO()
    img.save(buf, "PNG")
    return buf.getvalue()


def _open(b: bytes) -> Image.Image:
    return Image.open(BytesIO(b))


def test_returns_preprocessed_rgb_jpeg():
    out = preprocess_image(_jpeg(800, 600))
    assert isinstance(out, Preprocessed)
    im = _open(out.jpeg)
    assert im.format == "JPEG"
    assert im.mode == "RGB"


def test_rgba_flattened_to_rgb():
    out = preprocess_image(_png_rgba(300, 200))
    assert _open(out.jpeg).mode == "RGB"


def test_downscale_longest_edge_to_1024():
    out = preprocess_image(_jpeg(3000, 2000))
    assert max(out.width, out.height) == 1024
    # 종횡비 보존 (3:2)
    assert out.width == 1024 and out.height == 683


def test_no_upscale_small_image():
    out = preprocess_image(_jpeg(500, 400))
    assert (out.width, out.height) == (500, 400)


def test_exif_orientation_applied_and_stripped():
    img = Image.new("RGB", (100, 50), "blue")
    exif = img.getexif()
    exif[0x0112] = 6  # Orientation = Rotate 90 CW
    buf = BytesIO()
    img.save(buf, "JPEG", exif=exif)
    out = preprocess_image(buf.getvalue())
    assert (out.width, out.height) == (50, 100)  # 회전 적용됨
    assert not dict(_open(out.jpeg).getexif())  # EXIF 제거됨


def test_invalid_bytes_raises_decode_error():
    with pytest.raises(ImageDecodeError):
        preprocess_image(b"this is not an image")


def test_size_guard_raises_when_too_large():
    # 노이즈 1024x1024 → 작은 max_bytes에선 q-cascade로도 못 맞춤
    import os

    noise = Image.frombytes("RGB", (1024, 1024), os.urandom(1024 * 1024 * 3))
    buf = BytesIO()
    noise.save(buf, "PNG")
    with pytest.raises(ImageTooLargeError):
        preprocess_image(buf.getvalue(), max_bytes=3000)


def test_size_guard_fits_compressible():
    out = preprocess_image(_jpeg(800, 600, color="white"), max_bytes=20000)
    assert len(out.jpeg) <= 20000
