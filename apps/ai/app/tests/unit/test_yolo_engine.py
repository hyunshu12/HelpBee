"""B4 yolo_engine — 검출 결과 → 클래스 카운트 (순수 로직).

실제 ONNX 추론(OnnxYoloEngine)은 모델 의존이라 통합 검증 대상.
여기선 검출→카운트 변환과 프로토콜만 단위 검증한다.
"""

from app.services.yolo_engine import YoloResult, counts_from_detections


def test_tally_and_threshold_filter():
    dets = [
        {"class_id": 0, "score": 0.9},
        {"class_id": 0, "score": 0.1},  # 임계 미만 → 제외
        {"class_id": 1, "score": 0.5},
        {"class_id": 2, "score": 0.3},
    ]
    counts, mean = counts_from_detections(dets, conf_threshold=0.25)
    assert counts == {0: 1, 1: 1, 2: 1}
    assert abs(mean - (0.9 + 0.5 + 0.3) / 3) < 1e-9


def test_empty_detections():
    counts, mean = counts_from_detections([], conf_threshold=0.25)
    assert counts == {0: 0, 1: 0, 2: 0}
    assert mean == 0.0


def test_all_below_threshold():
    counts, mean = counts_from_detections([{"class_id": 1, "score": 0.1}], 0.25)
    assert counts == {0: 0, 1: 0, 2: 0}
    assert mean == 0.0


def test_unknown_class_ignored():
    counts, _ = counts_from_detections([{"class_id": 7, "score": 0.9}], 0.25)
    assert counts == {0: 0, 1: 0, 2: 0}


def test_yolo_result_shape():
    r = YoloResult(class_counts={0: 5, 1: 1, 2: 0}, confidence=0.7, model_version="helpbee-yolov11s-0.1.0")
    assert r.class_counts[1] == 1
    assert r.model_version.endswith("0.1.0")
