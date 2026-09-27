"""plan-2 최종 리뷰 수정 — C2(Stage-2 청크 스트리밍 메모리 상한), M3(raw_payload.boxes),
M6(호출별 rng), M7(기동 prewarm best-effort)."""
import numpy as np
import pytest
from fastapi.testclient import TestClient

import app.services.two_stage_engine as tse
from app.services.orchestrator import RAW_BOXES_CAP, compact_boxes, run_analysis
from app.services.two_stage_engine import BeeDet, OnnxTwoStageEngine, TwoStageResult, classify_boxes
from app.services.vdi import VdiConfig

CFG = VdiConfig(tau=0.6, tpr=0.9, fpr=0.01, corrected=True, platt=(1.0, 0.0))


class _Sess2:
    """Stage-2 가짜: logit = 배치 내 순번 기반, featmap 은 인덱스를 새긴 상수."""

    def __init__(self, logit_of_global):
        self.logit_of_global = logit_of_global
        self.offset = 0
        self.batches: list[int] = []

    def run(self, _names, feed):
        n = feed["image"].shape[0]
        self.batches.append(n)
        g = np.arange(self.offset, self.offset + n)
        self.offset += n
        fm = np.broadcast_to(g[:, None, None, None].astype(np.float32), (n, 4, 2, 2)).copy()
        return [self.logit_of_global(g).astype(np.float32), fm]


def _count_live_crops(monkeypatch):
    """crop_pad 호출 수를 normalize_crops 사이에서 센다 = 동시에 살아 있는 크롭 수의 상한."""
    stats = {"pending": 0, "max_pending": 0, "max_norm": 0}
    real_crop, real_norm = tse.crop_pad, tse.normalize_crops

    def crop(*a, **k):
        stats["pending"] += 1
        stats["max_pending"] = max(stats["max_pending"], stats["pending"])
        return real_crop(*a, **k)

    def norm(x):
        stats["max_norm"] = max(stats["max_norm"], len(x))
        stats["pending"] = 0
        return real_norm(x)

    monkeypatch.setattr(tse, "crop_pad", crop)
    monkeypatch.setattr(tse, "normalize_crops", norm)
    return stats


def test_c2_1600_boxes_streams_in_chunks_and_caps_at_1500(monkeypatch):
    boxes = [(float(i % 40) * 10, float(i // 40) * 10, float(i % 40) * 10 + 8, float(i // 40) * 10 + 8)
             for i in range(1600)]
    monkeypatch.setattr(tse, "detect_bees", lambda *a, **k: list(boxes))
    stats = _count_live_crops(monkeypatch)
    eng = OnnxTwoStageEngine("vtest", cache_dir="/nonexistent", s3_bucket=None)
    eng._s1 = object()
    eng._s2 = _Sess2(lambda g: np.where(g % 97 == 0, 5.0, -5.0))
    eng._meta = {"fc_weight": [0.1] * 4, "img_size": 16}
    r = eng.analyze(np.zeros((480, 640, 3), np.uint8), CFG)

    assert r.sampled is True and r.bee_total == 1500
    assert stats["max_pending"] <= eng.chunk == 64  # 전체 N 크롭을 한 번에 만들지 않는다
    assert stats["max_norm"] <= 64
    assert sum(eng._s2.batches) == 1500 and max(eng._s2.batches) <= 64
    assert len(r.evidence) <= eng.topk
    assert all(np.asarray(e["cam"]).shape == (2, 2) for e in r.evidence)


def test_c2_classify_boxes_keeps_true_topk_featmaps_across_chunks():
    n = 200
    img = np.zeros((64, 64, 3), np.uint8)
    boxes = [(0.0, 0.0, 8.0, 8.0)] * n
    # 상위 p: 전역 인덱스 199, 130, 65, 3 (서로 다른 청크)
    hot = {199: 9.0, 130: 8.0, 65: 7.0, 3: 6.0}
    sess = _Sess2(lambda g: np.array([hot.get(int(i), -3.0) for i in g]))
    p, feats = classify_boxes(sess, img, boxes, img_size=8, chunk=64, topk=3)
    assert p.shape == (n,)
    assert set(feats) == {199, 130, 65}
    for i, f in feats.items():  # featmap 이 해당 박스의 것
        assert float(f.flat[0]) == i
    assert sess.batches == [64, 64, 64, 8]


def test_m6_cap_sampling_uses_per_call_rng(monkeypatch):
    boxes = [(float(i), 0.0, float(i) + 5, 5.0) for i in range(40)]
    monkeypatch.setattr(tse, "detect_bees", lambda *a, **k: list(boxes))
    eng = OnnxTwoStageEngine("vtest", cache_dir="/nonexistent", s3_bucket=None, crop_cap=10)
    assert not hasattr(eng, "_rng")  # 공유 Generator 없음(스레드 비안전)
    eng._s1 = object()
    eng._meta = {"fc_weight": [0.1] * 4, "img_size": 8}
    picks = []
    for _ in range(2):
        eng._s2 = _Sess2(lambda g: np.zeros(len(g)))
        r = eng.analyze(np.zeros((64, 64, 3), np.uint8), CFG)
        picks.append([b.box for b in r.bees])
    assert picks[0] == picks[1] and len(picks[0]) == 10  # 호출마다 같은 seed → 결정적


class _FakeTwoStage:
    model_version = "t"
    model_versions = {"stage1": "a", "stage2": "b", "vdi_config": "c"}

    def __init__(self, n):
        self.n = n

    def analyze(self, image, cfg, *, deadline=None):
        b = [BeeDet(box=(1.4, 2.6, 30.5, 40.49), p_infested=0.91234, infested=True) for _ in range(self.n)]
        return TwoStageResult(b, len(b), len(b), False, [], self.model_versions, {"stage1": 1, "stage2": 1})


def test_m3_raw_payload_boxes_shape(jpeg_bytes):
    r = run_analysis(jpeg_bytes, engine="yolo", two_stage=_FakeTwoStage(3), vdi_cfg=CFG)
    boxes = r.raw_payload["boxes"]
    assert boxes == [[1, 3, 30, 40, 0.912]] * 3
    assert all(isinstance(v, int) for v in boxes[0][:4])
    assert "bees" not in r.raw_payload


def test_m3_compact_boxes_cap():
    bees = [BeeDet(box=(0, 0, 1, 1), p_infested=0.5, infested=False)] * (RAW_BOXES_CAP + 50)
    assert len(compact_boxes(bees)) == RAW_BOXES_CAP == tse.CROP_CAP


def test_m7_prewarm_failure_does_not_block_startup(monkeypatch):
    import app.deps as deps
    import app.main as main

    class Broken:
        version = "v0.2.0"

        def prewarm(self):
            raise FileNotFoundError("no cache, no S3")

    monkeypatch.setattr(deps, "get_two_stage_engine", lambda: Broken())
    monkeypatch.delenv("AI_PREWARM", raising=False)
    assert main.prewarm_two_stage() is False
    with TestClient(main.app) as client:  # startup 훅 실행 — 예외 없이 기동
        assert client.get("/health").status_code == 200


def test_m7_prewarm_success_and_opt_out(monkeypatch):
    import app.deps as deps
    import app.main as main

    calls = []

    class Ok:
        version = "v0.2.0"

        def prewarm(self):
            calls.append(1)

    monkeypatch.setattr(deps, "get_two_stage_engine", lambda: Ok())
    monkeypatch.delenv("AI_PREWARM", raising=False)
    assert main.prewarm_two_stage() is True and calls == [1]
    monkeypatch.setenv("AI_PREWARM", "0")
    assert main.prewarm_two_stage() is False and calls == [1]
    monkeypatch.setattr(deps, "get_two_stage_engine", lambda: None)  # yolo-v1 롤백
    monkeypatch.delenv("AI_PREWARM", raising=False)
    assert main.prewarm_two_stage() is False
