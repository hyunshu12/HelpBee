import json
import os
from pathlib import Path

import pytest

from training.data.aihub_to_yolo import CLASS_MAPPINGS, parse_annotations, yolo_line


def _doc(anns):
    return {
        "image": {"width": 1920, "height": 1080, "filename": "a.jpg"},
        "annotations": anns,
        "collection": {"device": "소비판촬영기", "datetime": "20230820_105708_001"},
        "colony": {"id": "007"},
    }


def test_bbox_is_xyxy_and_area_crosschecks():
    d = _doc([{"category_id": 5, "bbox": [224.77, 413.65, 814.69, 1078.2], "area": 392031}])
    boxes, stats = parse_annotations(d, "adult1")
    ((cls, x1, y1, x2, y2, cat, area_ok),) = boxes
    assert (cls, cat) == (0, 5)
    assert (round(x2 - x1), round(y2 - y1)) == (590, 665)  # xyxy: w=589.92, h=664.55
    assert area_ok and stats["area_match"] == 1


def test_adult1_mapping_drops_larvae_keeps_all_adults():
    assert set(CLASS_MAPPINGS) >= {"adult1", "legacy3"}
    d = _doc([{"category_id": c, "bbox": [0, 0, 10, 10], "area": 100} for c in range(7)])
    boxes, _ = parse_annotations(d, "adult1")
    assert sorted(b[5] for b in boxes) == [4, 5, 6] and all(b[0] == 0 for b in boxes)


def test_parse_skips_missing_area():
    d = _doc(
        [
            {"category_id": 4, "bbox": [10, 10, 50, 50]},
            {"category_id": 4, "bbox": [10, 10, 50, 50], "area": 0},
        ]
    )
    boxes, stats = parse_annotations(d, "adult1")
    assert len(boxes) == 2 and stats["area_missing"] == 2 and stats["area_match"] == 0


def test_yolo_line_normalized():
    line = yolo_line(0, 0, 0, 960, 540, 1920, 1080)
    assert line == "0 0.250000 0.250000 0.500000 0.500000"


SAMPLE = Path(os.environ.get("AIHUB_SAMPLE_DIR", "")) if os.environ.get("AIHUB_SAMPLE_DIR") else None


@pytest.mark.skipif(SAMPLE is None or not SAMPLE.exists(), reason="AIHUB_SAMPLE_DIR 없음")
def test_sample_area_crosscheck_ratio():
    match = missing = total = 0
    for jp in SAMPLE.rglob("*.json"):
        d = json.loads(jp.read_text(encoding="utf-8"))
        _, s = parse_annotations(d, "legacy3")
        match += s["area_match"]
        missing += s["area_missing"]
        total += s["n_boxes"]
    assert total > 0
    assert match / max(1, total - missing) > 0.99  # 4208/4210 재현
