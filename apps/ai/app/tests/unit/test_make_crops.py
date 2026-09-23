import json
from pathlib import Path

import numpy as np
import pytest

from training.data.make_crops import (
    external_crop_box,
    label_for,
    label_json_for,
    match_predictions,
    model_key_for,
    write_stats,
)


def test_iou_match_and_label_rules():
    preds = [(0, 0, 100, 100), (500, 500, 600, 600)]
    gts = [(5, (5, 5, 95, 95)), (6, (500, 500, 600, 600)), (4, (900, 900, 950, 950))]
    m = match_predictions(preds, gts)
    assert m == [((0, 0, 100, 100), 5), ((500, 500, 600, 600), 6)]
    assert label_for(5, image_has_varroa=True) == 1
    assert label_for(4, image_has_varroa=False) == 0
    assert label_for(4, image_has_varroa=True) is None      # 감염 이미지 내 정상 → 제외
    assert label_for(6, image_has_varroa=False) is None     # DWV 제외


def test_crop_pad_keeps_aspect():
    pytest.importorskip("cv2")
    from training.data.make_crops import crop_pad_224
    img = np.zeros((1080, 1920, 3), np.uint8)
    out, native = crop_pad_224(img, (100, 100, 300, 200))
    assert out.shape == (224, 224, 3) and native.shape[0] < native.shape[1]


def test_match_rate_recorded(tmp_path):
    p = write_stats(tmp_path, matched=40, total=100)
    s = json.loads(p.read_text(encoding="utf-8")); assert s["match_rate"] == 0.4 and s["warning"]


def test_out_of_fold_model_selection():
    from training.make_fold_lists import colony_fold
    colony = "001"
    other = {"A": "B", "B": "A"}[colony_fold(colony)]
    assert model_key_for("train", colony) == other     # 자기 fold 모델로 예측 금지
    assert model_key_for("val", colony) == other
    for s in ("golden", "cal_a", "cal_b"):
        assert model_key_for(s, colony) == "all"
    assert model_key_for("dropped_dup", colony) is None


def test_label_json_mirrors_image_path():
    img = Path("/d/aihub/01.원천데이터/성충/성충_응애/044/X.jpg")
    assert label_json_for(img) == Path("/d/aihub/02.라벨링데이터/성충/성충_응애/044/X.json")


def test_external_crop_box_rules():
    # VarroaDataset: 이미 벌 1마리 크롭 → 이미지 전체 (boxes 는 응애 위치라 무시)
    vd = {"source": "varroadataset", "boxes": [(10, 10, 20, 20)]}
    assert external_crop_box(vd, (280, 160, 3)) == (0, 0, 160, 280)
    # EV2: boxes[0] = 벌 박스 (프레임 좌표)
    ev = {"source": "ev2", "boxes": [(100, 200, 300, 400)]}
    assert external_crop_box(ev, (1080, 1920, 3)) == (100, 200, 300, 400)
