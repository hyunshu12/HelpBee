import json
from pathlib import Path

import numpy as np
import pytest

from training.data.make_crops import (
    ext_box_meta,
    external_crop_box,
    include_external,
    label_for,
    label_json_for,
    match_predictions,
    model_key_for,
    normalize_box,
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
    # EV2: PNG 도 이미 벌 크롭(spec §2) → 이미지 전체. 프레임 좌표 박스(크롭 밖)는 자르는 데 안 씀 (I1)
    ev = {"source": "ev2", "label": 1, "varroa_visible": True, "boxes": [(1044, 969, 702, 708)]}
    assert external_crop_box(ev, (300, 260, 3)) == (0, 0, 260, 300)
    assert ext_box_meta(ev) == "702 708 1044 969"  # 메타로만, min/max 정규화
    assert ext_box_meta(vd) == ""


def test_normalize_box_order():
    assert normalize_box((30, 40, 10, 20)) == (10, 20, 30, 40)
    assert normalize_box((10, 20, 30, 40)) == (10, 20, 30, 40)


def test_ev2_infested_not_visible_excluded():
    # I2: Stage-2 는 '보이는 응애' 분류기 — 감염 영상이지만 응애 안 보이는 프레임은 양성도 음성도 아님
    assert include_external({"source": "ev2", "label": 1, "varroa_visible": True})
    assert not include_external({"source": "ev2", "label": 1, "varroa_visible": False})
    assert include_external({"source": "ev2", "label": 0, "varroa_visible": False})  # 음성
    assert include_external({"source": "varroadataset", "label": 1, "varroa_visible": None})
    assert include_external({"source": "varroadataset", "label": 0, "varroa_visible": None})


def test_crops_external_skips_not_visible_positive_before_reading(tmp_path, monkeypatch):
    import training.data.make_crops as mc

    read: list = []
    monkeypatch.setattr(mc, "_imread", lambda p: read.append(p) or None)  # cv2 없이: 읽기 시도만 기록
    rows = [{"source": "ev2", "image": Path("dataset_free/a.png"), "label": 1, "varroa_visible": False,
             "boxes": [(0, 0, 1, 1)]},
            {"source": "ev2", "image": Path("dataset_free/b.png"), "label": 0, "varroa_visible": False,
             "boxes": [(0, 0, 1, 1)]}]
    res = mc.crops_external(rows, tmp_path, {}, tmp_path, writer=None)
    assert res["excluded_not_visible"] == 1 and res["unreadable"] == 1 and res["n"] == 0
    assert read == [tmp_path / "dataset_free/b.png"]


def test_crop_pad_empty_box_raises_clearly():
    pytest.importorskip("cv2")
    from training.data.make_crops import crop_pad_224
    with pytest.raises(ValueError, match="빈 크롭"):
        crop_pad_224(np.zeros((300, 260, 3), np.uint8), (1000, 900, 1200, 1000))


def test_crops_71667_skips_no_adult_images_before_loading(tmp_path, monkeypatch):
    """manifest 의 n_adult == 0 (유충 전용) 이미지는 라벨 JSON·이미지·Stage-1 모델 어느 것도 건드리지 않는다.
    경로가 존재하지 않아도 예외 없이 skipped_no_adult 로만 센다."""
    import sys
    import types

    import training.data.make_crops as mc

    touched: list = []
    fake_ultra = types.ModuleType("ultralytics")
    fake_ultra.YOLO = lambda *a, **k: touched.append(("YOLO", a)) or pytest.fail("모델 로드 금지")
    monkeypatch.setitem(sys.modules, "ultralytics", fake_ultra)
    monkeypatch.setattr(mc, "_imread", lambda p: touched.append(("imread", p)) or pytest.fail("이미지 읽기 금지"))
    orig_label_json_for = mc.label_json_for
    monkeypatch.setattr(mc, "label_json_for", lambda p: touched.append(("json", p)) or orig_label_json_for(p))

    missing = str(tmp_path / "nope" / "01.원천데이터" / "유충" / "유충_정상" / "001" / "x.jpg")
    manifest = {"images": {missing: {"split": "train", "colony": "001", "n_adult": 0,
                                     "has_varroa_adult": False, "source": "71667-val"}}}
    stats = mc.crops_71667(manifest, {"A": Path("a"), "B": Path("b"), "all": Path("c")}, tmp_path, writer=None)
    assert touched == []
    assert stats["skipped_no_adult"] == 1
    assert stats["crops_71667"] == 0 and stats["total"] == 0
