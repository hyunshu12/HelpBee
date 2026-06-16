"""yolo_engine — letterbox 전처리 + raw ONNX 출력 디코드(NMS) 순수 로직.

v0.1.0 ONNX는 export(nms=False) → 출력 [1, 4+nc, N] raw 텐서.
이 디코드/letterbox는 모델 없이 합성 배열로 단위 검증한다(실 추론은 통합 대상).
"""

import numpy as np
from PIL import Image

from app.services.yolo_engine import decode_detections, letterbox


# ---------- letterbox ----------

def test_letterbox_shape_and_range():
    img = Image.new("RGB", (1024, 576), (0, 128, 255))  # 16:9 비정사각
    out = letterbox(img, size=640)
    assert out.shape == (1, 3, 640, 640)
    assert out.dtype == np.float32
    assert out.min() >= 0.0 and out.max() <= 1.0


def test_letterbox_preserves_aspect_with_gray_pad():
    # 와이드 이미지 → 위/아래 회색(114) 패딩, 좌우는 꽉 참
    img = Image.new("RGB", (1280, 640), (10, 20, 30))
    out = letterbox(img, size=640)[0]  # [3,640,640]
    pad = 114 / 255.0
    # 맨 윗줄 가운데 픽셀은 패딩(회색)이어야 함
    assert abs(float(out[0, 0, 320]) - pad) < 1e-3
    # 정중앙은 콘텐츠(10/255)여야 함
    assert abs(float(out[0, 320, 320]) - 10 / 255.0) < 1e-2


# ---------- decode_detections ----------

def _anchor(cx, cy, w, h, scores):
    return [cx, cy, w, h, *scores]


def _channels_first(anchors):
    """anchors: list of [cx,cy,w,h,c0,c1,c2] → np [1, 7, N] (raw ultralytics 형태)."""
    arr = np.asarray(anchors, dtype=np.float32).T  # [7, N]
    return arr[None, ...]  # [1,7,N]


def test_decode_transposes_channels_first_and_counts_two_classes():
    out = _channels_first([
        _anchor(100, 100, 20, 20, [0.9, 0.0, 0.0]),  # class 0
        _anchor(500, 500, 20, 20, [0.0, 0.8, 0.0]),  # class 1, 멀리 떨어짐
    ])
    dets = decode_detections(out, conf_threshold=0.25, iou_threshold=0.5, num_classes=3)
    ids = sorted(d["class_id"] for d in dets)
    assert ids == [0, 1]


def test_decode_nms_collapses_overlapping_same_class():
    out = _channels_first([
        _anchor(100, 100, 40, 40, [0.9, 0.0, 0.0]),
        _anchor(105, 105, 40, 40, [0.7, 0.0, 0.0]),  # IoU>0.5 → 억제
    ])
    dets = decode_detections(out, conf_threshold=0.25, iou_threshold=0.5, num_classes=3)
    assert len(dets) == 1
    assert dets[0]["class_id"] == 0
    assert abs(dets[0]["score"] - 0.9) < 1e-6  # 더 높은 score가 남음


def test_decode_per_class_keeps_overlapping_different_classes():
    out = _channels_first([
        _anchor(100, 100, 40, 40, [0.9, 0.0, 0.0]),   # class 0
        _anchor(100, 100, 40, 40, [0.0, 0.85, 0.0]),  # 같은 박스, class 1
    ])
    dets = decode_detections(out, conf_threshold=0.25, iou_threshold=0.5, num_classes=3)
    assert sorted(d["class_id"] for d in dets) == [0, 1]


def test_decode_filters_below_conf_threshold():
    out = _channels_first([
        _anchor(100, 100, 20, 20, [0.9, 0.0, 0.0]),
        _anchor(300, 300, 20, 20, [0.10, 0.0, 0.0]),  # conf 미만
    ])
    dets = decode_detections(out, conf_threshold=0.25, iou_threshold=0.5, num_classes=3)
    assert len(dets) == 1
    assert dets[0]["class_id"] == 0


def test_decode_accepts_row_major_orientation():
    # [1, N, 4+nc] 형태(전치 불필요)도 동일 결과
    anchors = np.asarray([
        _anchor(100, 100, 20, 20, [0.9, 0.0, 0.0]),
        _anchor(500, 500, 20, 20, [0.0, 0.0, 0.7]),
    ], dtype=np.float32)[None, ...]  # [1, 2, 7]
    dets = decode_detections(anchors, conf_threshold=0.25, iou_threshold=0.5, num_classes=3)
    assert sorted(d["class_id"] for d in dets) == [0, 2]


def test_decode_empty_when_all_below_threshold():
    out = _channels_first([_anchor(100, 100, 20, 20, [0.1, 0.05, 0.0])])
    dets = decode_detections(out, conf_threshold=0.25, iou_threshold=0.5, num_classes=3)
    assert dets == []
