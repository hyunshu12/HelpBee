"""two_stage_engine — 순수 로직(합성 배열·가짜 세션) + 로컬 v0.2.0 번들 통합(없으면 skip)."""
from pathlib import Path

import numpy as np
import pytest

from app.services.two_stage_engine import (
    BudgetExceeded,
    OnnxTwoStageEngine,
    cam_from_featmap,
    cap_crops,
    chunk_indices,
    classify_crops,
    decode_boxes,
    detect_bees,
    iomin_nms,
    letterbox_tiles,
    needs_tiling,
    normalize_crops,
)
from app.services.vdi import VdiConfig

BUNDLE = Path.home() / ".cache" / "helpbee" / "two-stage" / "v0.2.0"


def test_crop_cap_and_chunking():
    boxes = [(i, i, i + 10, i + 10) for i in range(1600)]
    kept, sampled = cap_crops(boxes, cap=1500, rng=np.random.default_rng(0))
    assert len(kept) == 1500 and sampled is True
    assert kept == sorted(kept)  # 원래 순서 보존
    chunks = chunk_indices(1500, 64)
    assert len(chunks[-1]) == 1500 % 64 and sum(len(c) for c in chunks) == 1500
    same, s2 = cap_crops(boxes[:10], cap=1500)
    assert same == boxes[:10] and s2 is False


def test_cam_shape_and_normalized():
    cam = cam_from_featmap(np.random.rand(512, 10, 10).astype(np.float32), np.random.rand(512).astype(np.float32))
    assert cam.shape == (10, 10) and cam.min() >= 0.0 and cam.max() <= 1.0


def test_cam_relu_all_negative_is_zero():
    cam = cam_from_featmap(np.ones((4, 3, 3), np.float32), -np.ones(4, np.float32))
    assert np.all(cam == 0.0)


def test_tiles_cover_image_with_overlap():
    tiles = letterbox_tiles((3000, 4000), n=2, overlap=0.1)  # (h, w)
    assert len(tiles) == 4 and tiles[0] == (0, 0, 2200, 1650)  # (x, y, w, h)
    assert tiles[-1] == (1800, 1350, 2200, 1650)  # 오른쪽·아래 끝까지 덮는다


def test_needs_tiling_8mp():
    assert needs_tiling((3000, 4000)) is True  # 12MP
    assert needs_tiling((1080, 1920)) is False  # FHD (학습 분포)


def test_iomin_nms_merges_contained_box():
    boxes = np.array([[0, 0, 100, 100], [10, 10, 60, 60], [200, 200, 260, 260]], np.float32)
    keep = iomin_nms(boxes, np.array([0.9, 0.8, 0.7], np.float32), thr=0.7)
    assert sorted(keep) == [0, 2]


def _raw(boxes_xywh, scores, n=50):
    out = np.zeros((1, 5, n), np.float32)
    for i, (b, s) in enumerate(zip(boxes_xywh, scores)):
        out[0, :4, i] = b
        out[0, 4, i] = s
    return out


def test_decode_boxes_conf_nms():
    out = _raw([(100, 100, 40, 40), (102, 101, 40, 40), (300, 300, 20, 20), (500, 500, 20, 20)],
               [0.9, 0.8, 0.5, 0.1])
    boxes, scores = decode_boxes(out, conf=0.15, iou=0.7)
    assert len(boxes) == 2 and scores[0] == pytest.approx(0.9)
    assert tuple(boxes[0]) == pytest.approx((80, 80, 120, 120))


class FakeSess1:
    """letterbox 좌표계로 박스 1개를 돌려주는 가짜 Stage-1 세션."""

    class _I:
        name = "images"

    def __init__(self, xywh=(512, 512, 64, 64)):
        self.xywh = xywh
        self.calls = 0

    def get_inputs(self):
        return [self._I()]

    def run(self, _names, feed):
        self.calls += 1
        assert feed["images"].shape == (1, 3, 1024, 1024)
        return [_raw([self.xywh], [0.9])]


def test_detect_bees_unmaps_letterbox_to_original():
    img = np.zeros((1080, 1920, 3), np.uint8)
    boxes = detect_bees(FakeSess1(), img, imgsz=1024)
    # scale = 1024/1920, pad_y = (1024 - 576)//2 = 224 → 중심 (512,512) = 원본 (960, 540)
    assert len(boxes) == 1
    x1, y1, x2, y2 = boxes[0]
    assert (x1 + x2) / 2 == pytest.approx(960, abs=1) and (y1 + y2) / 2 == pytest.approx(540, abs=1)
    assert x2 - x1 == pytest.approx(64 * 1920 / 1024, abs=1)


def test_detect_bees_tiled_runs_four_passes_and_merges():
    sess = FakeSess1()
    img = np.zeros((3000, 4000, 3), np.uint8)
    boxes = detect_bees(sess, img, imgsz=1024, tile=True)
    assert sess.calls == 4 and 1 <= len(boxes) <= 4
    for b in boxes:
        assert 0 <= b[0] < b[2] <= 4000 and 0 <= b[1] < b[3] <= 3000


class FakeSess2:
    def __init__(self, logit_fn=lambda n: np.zeros(n, np.float32)):
        self.batches = []
        self.logit_fn = logit_fn

    def run(self, names, feed):
        x = feed["image"]
        self.batches.append(x.shape[0])
        n = x.shape[0]
        return [self.logit_fn(n), np.random.rand(n, 512, 10, 10).astype(np.float32)]


def test_classify_crops_chunks_of_64():
    sess = FakeSess2()
    logits, feats = classify_crops(sess, np.zeros((150, 3, 320, 320), np.float32), chunk=64)
    assert sess.batches == [64, 64, 22] and logits.shape == (150,) and feats.shape == (150, 512, 10, 10)


def test_classify_crops_budget_exceeded():
    with pytest.raises(BudgetExceeded):
        classify_crops(FakeSess2(), np.zeros((70, 3, 32, 32), np.float32), chunk=64, deadline=0.0)


def test_normalize_crops_imagenet():
    crops = np.full((2, 320, 320, 3), 255, np.uint8)
    x = normalize_crops(crops)
    assert x.shape == (2, 3, 320, 320) and x.dtype == np.float32
    assert x[0, 0, 0, 0] == pytest.approx((1 - 0.485) / 0.229, rel=1e-5)


def _engine_with_fakes(logits):
    eng = OnnxTwoStageEngine("vtest", cache_dir="/nonexistent", s3_bucket=None)
    eng._s1 = FakeSess1()
    eng._s2 = FakeSess2(lambda n: np.asarray(logits[:n], np.float32))
    eng._meta = {"fc_weight": [0.1] * 512, "img_size": 320, "feat_channels": 512}
    return eng


def test_engine_analyze_platt_tau_and_evidence():
    eng = _engine_with_fakes([5.0])  # 박스 1개
    cfg = VdiConfig(tau=0.6, tpr=0.9, fpr=0.01, corrected=True, platt=(1.0, 0.0))
    r = eng.analyze(np.random.default_rng(0).integers(0, 255, (1080, 1920, 3), dtype=np.uint8), cfg)
    assert r.bee_total == 1 and r.bee_infested == 1 and r.sampled is False
    assert r.bees[0].p_infested == pytest.approx(1 / (1 + np.exp(-5.0)))
    assert len(r.evidence) == 1 and np.asarray(r.evidence[0]["cam"]).shape == (10, 10)
    assert set(r.stage_latency_ms) >= {"stage1", "stage2"}
    assert r.model_versions == {"stage1": "vtest/stage1", "stage2": "vtest/stage2", "vdi_config": "vtest"}


def test_engine_analyze_below_tau_no_evidence():
    eng = _engine_with_fakes([-5.0])
    cfg = VdiConfig(tau=0.6, tpr=0.9, fpr=0.01, corrected=True, platt=(1.0, 0.0))
    r = eng.analyze(np.zeros((1080, 1920, 3), np.uint8), cfg)
    assert r.bee_infested == 0 and r.evidence == [] and r.bees[0].infested is False


@pytest.mark.skipif(not (BUNDLE / "stage2.onnx").exists(), reason="로컬 v0.2.0 번들 없음")
def test_real_bundle_loads_and_runs():
    eng = OnnxTwoStageEngine("v0.2.0", cache_dir=str(BUNDLE.parent), s3_bucket=None)
    cfg = eng.vdi_config()
    assert cfg.tau == pytest.approx(0.639, abs=1e-3) and cfg.platt[0] == pytest.approx(0.7148, abs=1e-3)
    assert eng.vdi_extras()["recommendations"]["low"]
    r = eng.analyze(np.random.default_rng(0).integers(0, 255, (1080, 1920, 3), dtype=np.uint8), cfg)
    assert r.bee_total == len(r.bees) and r.model_versions["vdi_config"] == "v0.2.0"
