# apps/ai/app/tests/unit/test_train_stage2.py
"""Stage-2 학습·보정·ONNX (Task 9). torch/cv2 필요 테스트는 함수 안 importorskip — Mac venv 는 skip, 학습 박스에서 실행."""
import json
from pathlib import Path

import numpy as np
import pytest
import yaml

from training.train_stage2 import (auroc, check_splits, choose_tau, ece, fit_platt, is_improvement, measure_rates,
                                   model_spec, onnx_input_size, parse_backbone, parse_select_metric,
                                   parse_size_jitter, pick_metric, rates_by_source, sample_weights, select_splits,
                                   write_vdi_yaml)


def test_phone_degrade_shape_and_range():
    pytest.importorskip("cv2")
    from training.train_stage2 import phone_degrade

    rng = np.random.default_rng(0)
    out = phone_degrade(np.full((224, 224, 3), 128, np.uint8), rng, lo_px=90)
    assert out.shape == (224, 224, 3) and out.dtype == np.uint8


def test_platt_recovers_scale_and_bias():
    rng = np.random.default_rng(1)
    z = rng.normal(0, 3, 4000)
    y = (rng.random(4000) < 1 / (1 + np.exp(-(0.5 * z - 1)))).astype(int)
    a, b = fit_platt(z, y)
    assert abs(a - 0.5) < 0.1 and abs(b + 1) < 0.25


def test_tau_hits_target_fpr_and_rates():
    rng = np.random.default_rng(2)
    y = np.r_[np.zeros(2000), np.ones(200)]
    p = np.r_[rng.beta(2, 8, 2000), rng.beta(8, 2, 200)]
    tau = choose_tau(p, y, 0.01)
    tpr, fpr = measure_rates(p, y, tau)
    assert fpr <= 0.012 and tpr > 0.5


def test_auroc_and_ece():
    assert auroc([0.1, 0.2, 0.8, 0.9], [0, 0, 1, 1]) == 1.0
    assert auroc([0.5, 0.5, 0.5, 0.5], [0, 1, 0, 1]) == 0.5  # 동점 = 평균 순위
    rng = np.random.default_rng(3)
    p = rng.random(20000)
    y = (rng.random(20000) < p).astype(int)  # 완벽 보정
    assert ece(p, y) < 0.02
    assert ece(np.full(1000, 0.9), np.zeros(1000)) == pytest.approx(0.9)


def test_sample_weights_equalize_source_prior_and_balance_classes():
    labels = np.r_[np.ones(100), np.zeros(900), np.ones(100), np.zeros(100), np.ones(6), np.zeros(294)]
    sources = np.array(["71667"] * 1000 + ["varroadataset"] * 200 + ["ev2"] * 300)
    w = sample_weights(labels, sources)
    assert w.shape == labels.shape and (w > 0).all()
    shares = [w[(sources == s) & (labels == 1)].sum() / w[sources == s].sum() for s in ("71667", "varroadataset", "ev2")]
    assert np.allclose(shares, shares[0])  # 소스별 기대 양성 비율 동일
    assert w[labels == 1].sum() == pytest.approx(w[labels == 0].sum())  # 클래스 균형
    mass = [w[sources == s].sum() for s in ("71667", "varroadataset", "ev2")]
    assert np.allclose(np.array(mass) / mass[0], [1, 0.2, 0.3])  # 소스 질량은 크기 비례 유지


def test_sample_weights_single_class_source_still_balances():
    labels = np.r_[np.ones(10), np.zeros(90), np.ones(50)]
    sources = np.array(["71667"] * 100 + ["ev2"] * 50)  # ev2 는 양성만
    w = sample_weights(labels, sources)
    assert w[labels == 1].sum() == pytest.approx(w[labels == 0].sum())


def test_select_splits_routes_sources():
    rows = [{"source": s, "split": sp} for s, sp in [
        ("71667", "train"), ("71667", "val"), ("71667", "golden"), ("71667", "cal_a"), ("71667", "cal_b"),
        ("varroadataset", "train"), ("varroadataset", "val"), ("varroadataset", "test"),
        ("ev2", "train"), ("ev2", "holdout")]]
    got = {k: [(r["source"], r["split"]) for r in v] for k, v in select_splits(rows).items()}
    assert got["train"] == [("71667", "train"), ("varroadataset", "train"), ("ev2", "train")]
    assert got["val"] == [("71667", "val"), ("varroadataset", "val")]
    assert got["cal_a"] == [("71667", "cal_a")] and got["cal_b"] == [("71667", "cal_b")]


def test_write_vdi_yaml_schema(tmp_path):
    p = write_vdi_yaml(tmp_path / "vdi.yaml", version="v0.2.0", tau=0.62, tpr=0.91, fpr=0.009, platt=(1.13, -0.42))
    d = yaml.safe_load(p.read_text(encoding="utf-8"))
    assert set(d) == {"version", "tau", "tpr", "fpr", "corrected", "platt", "thresholds", "quality",
                      "capture_floor_px_per_mm", "recommendations", "by_source"}
    assert d["by_source"] is None
    assert d["corrected"] is True and d["platt"] == {"a": 1.13, "b": -0.42}
    assert d["thresholds"] == {"elevated": 3.0, "high": 10.0}
    assert d["quality"] == {"blur_laplacian_min": 100, "exposure_mean": [40, 215]}
    assert d["capture_floor_px_per_mm"] is None
    r = d["recommendations"]
    assert r["low"] == ["응애 감염 징후가 낮게 관찰됐습니다. 다음 점검 시기에 재촬영하세요."]
    assert r["elevated"] == ["감염 벌 비율이 높게 관찰됐습니다. 가루설탕법(설탕 15g+일벌 100마리)으로 확인하세요."]
    assert r["high"] == ["감염 벌 비율이 매우 높게 관찰됐습니다. 가루설탕법으로 확인 후 방제 계획을 세우세요."]
    assert r["insufficient"] == ["벌이 보이도록 소비판을 가까이서 다시 촬영해 주세요."]
    assert r["next_check_windows"] == ["3월 중순~4월 초", "6월 중순~7월 초", "7월 하순~8월 중순", "10월 하순~11월 초"]
    d2 = yaml.safe_load(write_vdi_yaml(tmp_path / "v2.yaml", version="v0.2.0", tau=0.5, tpr=0.4, fpr=0.01,
                                       platt=(1.0, 0.0), capture_floor_px_per_mm=12.5).read_text(encoding="utf-8"))
    assert d2["corrected"] is False and d2["capture_floor_px_per_mm"] == 12.5
    bs = {"71667": {"tpr": 0.8, "fpr": 0.01, "n_pos": 50, "n_neg": 900}}
    d3 = yaml.safe_load(write_vdi_yaml(tmp_path / "v3.yaml", version="v0.2.0", tau=0.5, tpr=0.8, fpr=0.01,
                                       platt=(1.0, 0.0), by_source=bs).read_text(encoding="utf-8"))
    assert d3["by_source"] == bs


def test_rates_by_source_groups_71667_tags_and_handles_missing_class():
    p = np.array([0.9, 0.1, 0.8, 0.2, 0.3, 0.95, 0.6, 0.4])
    y = np.array([1, 0, 1, 0, 1, 0, 0, 0])
    src = ["71667-val", "71667-val", "71667-train", "71667", "varroadataset", "varroadataset", "ev2", "ev2"]
    r = rates_by_source(p, y, src, tau=0.5)
    assert set(r) == {"71667", "varroadataset", "ev2"}
    assert r["71667"] == {"tpr": 1.0, "fpr": 0.0, "n_pos": 2, "n_neg": 2}
    assert r["varroadataset"] == {"tpr": 0.0, "fpr": 1.0, "n_pos": 1, "n_neg": 1}
    assert r["ev2"] == {"tpr": None, "fpr": 0.5, "n_pos": 0, "n_neg": 2}


def test_parse_size_jitter():
    assert parse_size_jitter([0.7, 1.3]) == (0.7, 1.3)
    assert parse_size_jitter(None) is None and parse_size_jitter("none") is None and parse_size_jitter([]) is None
    with pytest.raises(ValueError):
        parse_size_jitter([1.3, 0.7])


def _jitter_probe_img():
    x = np.tile(np.arange(224, dtype=np.uint8)[None, :, None], (224, 1, 3))  # 가로 그라디언트
    x[92:132, 92:132] = (200, 30, 60)  # 가운데 블록
    x[0, :], x[-1, :], x[:, 0], x[:, -1] = 255, 255, 255, 255  # 흰 테두리 (검정 패딩과 구분)
    return x


def test_size_jitter_shrink_pads_black_border():
    pytest.importorskip("cv2")
    from training.train_stage2 import size_jitter

    out = size_jitter(_jitter_probe_img(), np.random.default_rng(0), 0.7, 0.8)  # s<1 확정
    assert out.shape == (224, 224, 3) and out.dtype == np.uint8
    assert (out[:5] == 0).all() and (out[-5:] == 0).all() and (out[:, :5] == 0).all() and (out[:, -5:] == 0).all()
    assert tuple(out[112, 112]) == (200, 30, 60)


def test_size_jitter_enlarge_center_crops_keeping_center():
    pytest.importorskip("cv2")
    from training.train_stage2 import size_jitter

    img = _jitter_probe_img()
    out = size_jitter(img, np.random.default_rng(0), 1.2, 1.3)  # s>1 확정
    assert out.shape == (224, 224, 3)
    assert tuple(out[112, 112]) == tuple(img[112, 112])
    assert not (out[0] == 255).all()  # 흰 테두리는 잘려 나감


def test_augment_with_jitter_shape():
    pytest.importorskip("cv2")
    from training.train_stage2 import augment

    out = augment(_jitter_probe_img(), np.random.default_rng(5), None, (0.7, 1.3))
    assert out.shape == (224, 224, 3) and out.dtype == np.uint8


def test_onnx_two_outputs(tmp_path):
    pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    ort = pytest.importorskip("onnxruntime")
    from training.train_stage2 import build_model, export_onnx

    m = build_model(pretrained=False)
    p = export_onnx(m, tmp_path / "s2.onnx")
    s = ort.InferenceSession(str(p), providers=["CPUExecutionProvider"])
    assert [o.name for o in s.get_outputs()] == ["logit", "featmap"]
    logit, feat = s.run(None, {"image": np.zeros((2, 3, 224, 224), np.float32)})
    assert logit.shape == (2,) and feat.shape == (2, 1024, 7, 7)


def test_write_metadata(tmp_path):
    pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    from training.train_stage2 import build_model, write_metadata

    p = write_metadata(tmp_path / "metadata.json", build_model(pretrained=False), (1.13, -0.42), 0.62)
    d = json.loads(Path(p).read_text(encoding="utf-8"))
    assert len(d["fc_weight"]) == 1024 and all(isinstance(v, float) for v in d["fc_weight"])
    assert d["platt"] == {"a": 1.13, "b": -0.42} and d["tau"] == 0.62
    assert d["backbone"] == "shufflenet_v2_x1_0" and d["feat_channels"] == 1024 and d["img_size"] == 224


def test_stage2_yaml_loads():
    root = Path(__file__).resolve().parents[3]
    cfg = yaml.safe_load((root / "training/configs/stage2.yaml").read_text(encoding="utf-8"))
    assert cfg == {"epochs": 50, "patience": 10, "batch": 64, "lr": 3e-4, "weight_decay": 0.01,
                   "label_smoothing": 0.05, "degrade": "none", "size_jitter": [0.7, 1.3], "img_size": 224,
                   "backbone": "shufflenet_v2_x1_0", "select_metric": "val_auroc", "seed": 42,
                   "crops": "training/crops", "project": "training/runs/stage2", "name": "v0.2.0-stage2",
                   "workers": 0}


def test_parse_degrade():
    from training.train_stage2 import parse_degrade

    assert parse_degrade("none") is None and parse_degrade(None) is None and parse_degrade("90") == 90
    assert parse_degrade(90) == 90
    with pytest.raises(ValueError):
        parse_degrade("abc")


def test_check_splits_fails_fast_on_empty_or_single_class():
    ok = {k: [{"label": "0"}, {"label": "1"}] for k in ("train", "val", "cal_a", "cal_b")}
    check_splits(ok)
    with pytest.raises(ValueError, match="cal_a"):
        check_splits({**ok, "cal_a": []})
    with pytest.raises(ValueError, match="val"):
        check_splits({**ok, "val": [{"label": "0"}]})


def test_pick_metric_and_select_metric_validation():
    row = {"epoch": 3, "train_loss": 0.4, "val_auroc": 0.93, "cal_a_auroc": 0.81, "cal_b_auroc": 0.99}
    assert pick_metric(row, "val_auroc") == 0.93
    assert pick_metric(row, "cal_a_auroc") == 0.81
    assert parse_select_metric(None) == "val_auroc"
    with pytest.raises(ValueError):
        pick_metric(row, "cal_b_auroc")  # cal-B 는 선택 금지 (불편 TPR/FPR 셋)


def test_selection_over_history_differs_by_metric():
    """v2 실측 모양: val 은 epoch 1 이 최고지만 cal_a 는 뒤 epoch 이 최고 → 선택 epoch 이 갈린다."""
    hist = [{"val_auroc": 0.90, "cal_a_auroc": 0.70}, {"val_auroc": 0.95, "cal_a_auroc": 0.75},
            {"val_auroc": 0.94, "cal_a_auroc": 0.86}, {"val_auroc": 0.93, "cal_a_auroc": float("nan")}]

    def best(metric):
        b, be = -1.0, -1
        for ep, r in enumerate(hist):
            v = pick_metric(r, metric)
            if is_improvement(v, b):
                b, be = v, ep
        return be, b

    assert best("val_auroc") == (1, 0.95)
    assert best("cal_a_auroc") == (2, 0.86)  # NaN 은 개선 아님


def test_parse_backbone():
    assert parse_backbone(None) == "shufflenet_v2_x1_0" and parse_backbone("resnet18") == "resnet18"
    with pytest.raises(ValueError):
        parse_backbone("resnet50")


def test_model_spec_reads_metadata_and_explicit_overrides(tmp_path):
    assert model_spec(None) == ("shufflenet_v2_x1_0", 224)
    w = tmp_path / "best.pt"
    assert model_spec(w) == ("shufflenet_v2_x1_0", 224)  # metadata 없음 → 기본
    (tmp_path / "metadata.json").write_text(json.dumps({"backbone": "resnet18", "img_size": 320}), encoding="utf-8")
    assert model_spec(w) == ("resnet18", 320)
    assert model_spec(w, backbone="shufflenet_v2_x1_0", img_size=224) == ("shufflenet_v2_x1_0", 224)


def test_onnx_input_size():
    assert onnx_input_size(["b", 3, 320, 320]) == 320
    assert onnx_input_size(["b", 3, "h", "w"], default=256) == 256
    assert onnx_input_size(None) == 224


def test_to_input_size_resizes_any_crop():
    pytest.importorskip("cv2")
    from training.train_stage2 import to_input_size

    img = np.zeros((224, 224, 3), np.uint8)
    assert to_input_size(img, 224) is img
    assert to_input_size(img, 320).shape == (320, 320, 3)
    assert to_input_size(np.zeros((320, 320, 3), np.uint8), 224).shape == (224, 224, 3)


def test_augment_and_degrade_keep_320():
    pytest.importorskip("cv2")
    from training.train_stage2 import augment, phone_degrade, size_jitter

    img = np.full((320, 320, 3), 120, np.uint8)
    rng = np.random.default_rng(7)
    assert phone_degrade(img, rng, lo_px=90).shape == (320, 320, 3)
    assert size_jitter(img, rng, 0.7, 0.8).shape == (320, 320, 3)
    assert size_jitter(img, rng, 1.2, 1.3).shape == (320, 320, 3)
    assert augment(img, rng, 90, (0.7, 1.3)).shape == (320, 320, 3)


def test_resnet18_shapes_and_metadata(tmp_path):
    torch = pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    from training.train_stage2 import build_model, write_metadata

    m = build_model(pretrained=False, backbone="resnet18").eval()
    with torch.no_grad():
        logit, feat = m(torch.zeros(2, 3, 320, 320))
    assert tuple(logit.shape) == (2,) and tuple(feat.shape) == (2, 512, 10, 10)
    d = json.loads(Path(write_metadata(tmp_path / "m.json", m, (1.0, 0.0), 0.5, 320)).read_text(encoding="utf-8"))
    assert d["backbone"] == "resnet18" and d["feat_channels"] == 512 and len(d["fc_weight"]) == 512
    assert d["img_size"] == 320


def test_onnx_two_outputs_resnet18_320(tmp_path):
    pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    ort = pytest.importorskip("onnxruntime")
    from training.train_stage2 import build_model, export_onnx

    p = export_onnx(build_model(pretrained=False, backbone="resnet18"), tmp_path / "s2.onnx", img_size=320)
    s = ort.InferenceSession(str(p), providers=["CPUExecutionProvider"])
    assert [o.name for o in s.get_outputs()] == ["logit", "featmap"]
    assert onnx_input_size(s.get_inputs()[0].shape) == 320
    logit, feat = s.run(None, {"image": np.zeros((2, 3, 320, 320), np.float32)})
    assert logit.shape == (2,) and feat.shape == (2, 512, 10, 10)
