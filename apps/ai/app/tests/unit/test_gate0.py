# apps/ai/app/tests/unit/test_gate0.py
import numpy as np
import pytest

from training.gate0_pxmm import collapse_target, rates_at_tau, scale_for_target, simulate_px_per_mm


def test_scale_for_target():
    assert scale_for_target(22, 11) == 0.5


def test_simulate_returns_224():
    pytest.importorskip("cv2")
    out = simulate_px_per_mm(np.full((300, 260, 3), 100, np.uint8), 22, 9, np.random.default_rng(0))
    assert out.shape == (224, 224, 3)


def test_native_from_padded_roundtrip():
    pytest.importorskip("cv2")
    from training.data.make_crops import crop_pad_224
    from training.gate0_pxmm import native_from_padded

    native = np.full((300, 260, 3), 100, np.uint8)
    padded, _ = crop_pad_224(native, (0, 0, 260, 300), margin=0.0)
    back = native_from_padded(padded, native_w=260, native_h=300)
    assert back.shape == (300, 260, 3)
    assert abs(float(back.mean()) - 100) < 1  # 검정 패딩이 섞이지 않음


def test_rates_at_tau_applies_platt_before_tau():
    logits = np.array([2.0, -2.0, 0.5, -0.5])
    y = np.array([1, 0, 1, 0])
    # platt a=1,b=0 → p = σ(z); τ=0.5 → z>0 양성
    r = rates_at_tau(logits, y, tau=0.5, platt=(1.0, 0.0))
    assert r == {"recall": 1.0, "specificity": 1.0, "n_pos": 2, "n_neg": 2}
    # b=-1 이동 → z=0.5 는 σ(-0.5)<0.5 로 음성
    r = rates_at_tau(logits, y, tau=0.5, platt=(1.0, -1.0))
    assert r["recall"] == 0.5 and r["specificity"] == 1.0


def test_rates_at_tau_empty_class_is_none():
    r = rates_at_tau(np.array([1.0]), np.array([1]), tau=0.5, platt=(1.0, 0.0))
    assert r["recall"] == 1.0 and r["specificity"] is None


def test_collapse_target_first_drop_of_15pp():
    res = {"22": {"recall": 0.80}, "15": {"recall": 0.70}, "12": {"recall": 0.64}, "9": {"recall": 0.30}}
    assert collapse_target(res, reference="22", drop=0.15) == 12.0
    assert collapse_target({"22": {"recall": 0.8}, "15": {"recall": 0.7}}, reference="22") is None


def test_simulate_respects_size():
    pytest.importorskip("cv2")
    out = simulate_px_per_mm(np.full((300, 260, 3), 100, np.uint8), 22, 12, np.random.default_rng(0), size=320)
    assert out.shape == (320, 320, 3)
