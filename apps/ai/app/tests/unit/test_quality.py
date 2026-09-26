"""quality.assess_quality — 스펙 v2.2 §3 quality: 블러·노출만 게이트, px/mm 는 경고만."""
import numpy as np

from app.services.quality import assess_quality


def test_blur_and_exposure_fail():
    flat = np.full((1080, 1920, 3), 20, np.uint8)  # 어둡고 평탄 → 블러·노출 실패
    q = assess_quality(flat, boxes=None, floor_px_per_mm=None)
    assert q["ok"] is False and {"blur", "exposure"} <= set(q["reasons"])
    assert q["px_per_mm_est"] is None


def test_textured_mid_exposure_ok():
    img = np.random.default_rng(0).integers(0, 255, (1080, 1920, 3), dtype=np.uint8)
    q = assess_quality(img, boxes=None, floor_px_per_mm=None)
    assert q["ok"] is True and q["reasons"] == [] and 40 <= q["exposure_mean"] <= 215


def test_overexposed_fails_exposure_only():
    img = np.random.default_rng(0).integers(225, 255, (600, 800, 3), dtype=np.uint8)
    q = assess_quality(img, boxes=None, floor_px_per_mm=None)
    assert q["reasons"] == ["exposure"] and q["ok"] is False


def test_px_per_mm_estimate_from_boxes_is_warning_only():
    img = np.random.default_rng(1).integers(0, 255, (1080, 1920, 3), dtype=np.uint8)
    q = assess_quality(img, boxes=[(0, 0, 60, 60)] * 20, floor_px_per_mm=12.0)  # 60px/12mm = 5 px/mm
    assert q["px_per_mm_est"] == 5.0 and "resolution" in q["warnings"] and q["ok"] is True


def test_px_per_mm_no_floor_no_warning():
    img = np.random.default_rng(2).integers(0, 255, (500, 500, 3), dtype=np.uint8)
    q = assess_quality(img, boxes=[(0, 0, 120, 60)], floor_px_per_mm=None)
    assert q["px_per_mm_est"] == 10.0 and q["warnings"] == []


def test_thresholds_configurable():
    img = np.random.default_rng(3).integers(0, 255, (400, 400, 3), dtype=np.uint8)
    q = assess_quality(img, boxes=None, floor_px_per_mm=None, blur_min=1e12)
    assert q["reasons"] == ["blur"]
