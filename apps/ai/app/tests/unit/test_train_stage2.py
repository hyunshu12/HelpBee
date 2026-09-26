# apps/ai/app/tests/unit/test_train_stage2.py
"""Stage-2 학습·보정·ONNX (Task 9). torch/cv2 필요 테스트는 함수 안 importorskip — Mac venv 는 skip, 학습 박스에서 실행."""
import json
from pathlib import Path

import numpy as np
import pytest
import yaml

from training.train_stage2 import (auroc, build_parser, calibrate, check_splits, choose_tau, choose_tau_youden, ece,
                                   fit_platt, is_improvement, measure_rates, model_spec, onnx_input_size,
                                   parse_backbone, parse_fpr_cap, parse_select_metric, parse_size_jitter,
                                   parse_tau_policy, pick_metric, rates_by_source, sample_weights, select_splits,
                                   select_tau, write_vdi_yaml)


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
    assert set(d) == {"version", "tau", "tpr", "fpr", "corrected", "platt", "tau_policy", "fpr_cap",
                      "cal_a_fpr_at_tau", "thresholds", "quality", "capture_floor_px_per_mm", "recommendations",
                      "by_source"}
    assert d["by_source"] is None
    assert d["tau_policy"] is None and d["fpr_cap"] is None and d["cal_a_fpr_at_tau"] is None
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
                   "label_smoothing": 0.05, "degrade": "none", "size_jitter": [0.7, 1.3], "img_size": 320,
                   "backbone": "resnet18", "select_metric": "cal_a_auroc", "tau_policy": "youden", "fpr_cap": 0.01,
                   "seed": 42, "crops": "training/crops-320", "project": "training/runs/stage2",
                   "name": "v0.2.0-stage2", "workers": 4, "amp": False, "swa_epochs": 0}


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
    for bb in ("resnet34", "resnet50", "efficientnet_b0"):  # v0.2.1 실험 백본
        assert parse_backbone(bb) == bb
    with pytest.raises(ValueError):
        parse_backbone("vit_b_16")


# ── v0.2.1: 백본 확장 · 피클 가능 Dataset · 워커 ──────────────────────────────
V021_BACKBONES = [("resnet34", 512), ("resnet50", 2048), ("efficientnet_b0", 1280)]


@pytest.mark.parametrize("backbone,channels", V021_BACKBONES)
def test_v021_backbone_shapes_metadata_onnx(tmp_path, backbone, channels):
    torch = pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    from training.train_stage2 import BACKBONES, build_model, write_metadata

    assert BACKBONES[backbone] == channels
    m = build_model(pretrained=False, backbone=backbone).eval()
    with torch.no_grad():
        logit, feat = m(torch.zeros(2, 3, 320, 320))
    assert tuple(logit.shape) == (2,) and tuple(feat.shape) == (2, channels, 10, 10)
    d = json.loads(Path(write_metadata(tmp_path / "m.json", m, (1.0, 0.0), 0.5, 320)).read_text(encoding="utf-8"))
    assert d["backbone"] == backbone and d["feat_channels"] == channels and len(d["fc_weight"]) == channels
    assert d["img_size"] == 320

    pytest.importorskip("onnx")
    ort = pytest.importorskip("onnxruntime")
    from training.train_stage2 import export_onnx

    p = export_onnx(m, tmp_path / "s2.onnx", img_size=320)
    s = ort.InferenceSession(str(p), providers=["CPUExecutionProvider"])
    assert [o.name for o in s.get_outputs()] == ["logit", "featmap"]
    assert onnx_input_size(s.get_inputs()[0].shape) == 320
    lo, fe = s.run(None, {"image": np.zeros((2, 3, 320, 320), np.float32)})
    assert lo.shape == (2,) and fe.shape == (2, channels, 10, 10)


def _fake_rows(n=4):
    return [{"path": f"c/{i}.png", "label": str(i % 2), "source": "71667-val", "split": "train"} for i in range(n)]


def test_crop_dataset_is_picklable_without_torch(tmp_path):
    """Windows spawn 워커는 Dataset 을 피클한다 — 로컬 클래스면 EOFError (2026-09-24). torch 없이도 통과해야 함."""
    import pickle

    from training.train_stage2 import CropDataset, _dataset

    ds = _dataset(_fake_rows(), tmp_path, True, 90, 7, (0.7, 1.3), 320)
    assert isinstance(ds, CropDataset) and len(ds) == 4
    back = pickle.loads(pickle.dumps(ds))
    assert type(back) is CropDataset and len(back) == 4
    assert (back.rows, back.crops_dir, back.train, back.degrade_lo, back.seed, back.jitter, back.img_size) == \
        (_fake_rows(), tmp_path, True, 90, 7, (0.7, 1.3), 320)
    ev = pickle.loads(pickle.dumps(_dataset(_fake_rows(2), tmp_path, train=False, degrade_lo=None, seed=0, img_size=224)))
    assert ev.train is False and ev.jitter is None and ev.img_size == 224


def test_resolve_workers_and_loader_kwargs():
    from training.train_stage2 import loader_kwargs, resolve_workers

    assert resolve_workers({}) == 4  # 모든 플랫폼 기본 4
    assert resolve_workers({"workers": 0}) == 0 and resolve_workers({"workers": "2"}) == 2
    with pytest.raises(ValueError):
        resolve_workers({"workers": -1})
    assert loader_kwargs(0, 42) == {"num_workers": 0}  # workers=0 은 기존 인자와 동일


def _write_crops(root: Path, n=4, size=64):
    cv2 = pytest.importorskip("cv2")
    (root / "c").mkdir(parents=True, exist_ok=True)
    for i in range(n):
        img = np.full((size, size, 3), 40 * i, np.uint8)
        cv2.imwrite(str(root / "c" / f"{i}.png"), img)
    return _fake_rows(n)


def _collect(ds, workers, seed=42):
    import torch
    from torch.utils.data import DataLoader

    from training.train_stage2 import loader_kwargs

    dl = DataLoader(ds, batch_size=2, shuffle=False, **loader_kwargs(workers, seed))
    xs, ys = zip(*[(x, y) for x, y in dl])
    return torch.cat(xs), torch.cat(ys)


def test_crop_dataset_spawn_workers_deterministic(tmp_path):
    """macOS 기본 start method = spawn → Windows 와 같은 피클 경로. 같은 seed 면 워커 증강도 재현된다."""
    torch = pytest.importorskip("torch")
    from training.train_stage2 import _dataset

    rows = _write_crops(tmp_path)
    ds = _dataset(rows, tmp_path, True, None, 7, (0.7, 1.3), 64)
    x1, y1 = _collect(ds, 2)
    x2, y2 = _collect(ds, 2)
    assert tuple(x1.shape) == (4, 3, 64, 64) and y1.tolist() == [0.0, 1.0, 0.0, 1.0]
    assert torch.equal(x1, x2) and torch.equal(y1, y2)
    # 평가(train=False)는 증강 없음 → 워커 수와 무관하게 같은 텐서
    ev = _dataset(rows, tmp_path, False, None, 7, img_size=64)
    assert torch.equal(_collect(ev, 0)[0], _collect(ev, 2)[0])


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


# ── τ 정책 (스펙 v2.2) ────────────────────────────────────────────────────────
def _beta_scores(seed=2, n_neg=2000, n_pos=200):
    rng = np.random.default_rng(seed)
    y = np.r_[np.zeros(n_neg), np.ones(n_pos)].astype(int)
    p = np.r_[rng.beta(2, 5, n_neg), rng.beta(5, 2, n_pos)]  # 겹침이 커서 Youden 최적 FPR 이 1% 보다 큼
    return p, y


def _brute_youden(p, y, cap):
    best, bt = -np.inf, None
    for t in np.unique(p):
        tpr, fpr = measure_rates(p, y, t)
        if fpr <= cap and tpr - fpr >= best:
            best, bt = tpr - fpr, t
    return bt


def test_choose_tau_youden_maximizes_j_under_cap():
    p, y = _beta_scores()
    for cap in (0.10, 0.05, 0.3, 1.0):
        tau = choose_tau_youden(p, y, cap)
        tpr, fpr = measure_rates(p, y, tau)
        assert fpr <= cap + 1e-12
        assert tau == _brute_youden(p, y, cap)
    # cap 이 느슨할수록 J 는 줄지 않는다
    js = [np.subtract(*measure_rates(p, y, choose_tau_youden(p, y, c))) for c in (0.01, 0.05, 0.10, 1.0)]
    assert all(a <= b + 1e-12 for a, b in zip(js, js[1:]))
    # 이 겹침에서 Youden(cap 0.10) 은 FPR-1% τ 보다 TPR 이 높다 (v0.2.0 이 겪은 저 TPR 문제의 해법)
    assert measure_rates(p, y, choose_tau_youden(p, y, 0.10))[0] > measure_rates(p, y, choose_tau(p, y, 0.01))[0]


def test_choose_tau_youden_cap_zero_is_highest_negative():
    p, y = _beta_scores(seed=5)
    tau = choose_tau_youden(p, y, 0.0)
    assert tau == p[y == 0].max()
    tpr, fpr = measure_rates(p, y, tau)
    assert fpr == 0.0 and tpr == (p[y == 1] > p[y == 0].max()).mean()


def test_choose_tau_youden_requires_both_classes():
    with pytest.raises(ValueError):
        choose_tau_youden([0.1, 0.2], [0, 0], 0.1)


def test_select_tau_and_policy_parsing():
    p, y = _beta_scores()
    assert select_tau(p, y, "fpr", target_fpr=0.01) == choose_tau(p, y, 0.01)
    assert select_tau(p, y, "youden", fpr_cap=0.05) == choose_tau_youden(p, y, 0.05)
    assert parse_tau_policy(None) == "youden" and parse_tau_policy("fpr") == "fpr"
    assert parse_fpr_cap(None) == 0.10 and parse_fpr_cap("0.2") == 0.2
    with pytest.raises(ValueError):
        parse_tau_policy("f1")
    with pytest.raises(ValueError):
        parse_fpr_cap(1.5)


def test_calibrate_reports_policy_and_cal_a_fpr():
    rng = np.random.default_rng(9)

    def split(n_neg, n_pos, src):
        y = np.r_[np.zeros(n_neg), np.ones(n_pos)].astype(int)
        z = np.r_[rng.normal(-1, 1, n_neg), rng.normal(1, 1, n_pos)]
        return z, y, [{"source": src, "label": str(v)} for v in y]

    za, ya, ra = split(1500, 200, "71667-val")
    zb, yb, rb = split(3000, 100, "71667-val")
    zv, yv, rv = split(300, 60, "varroadataset")
    sp = {"cal_a": ra, "cal_b": rb, "val": rv}
    cal = calibrate(za, ya, zb, yb, zv, yv, sp, {})
    assert cal["tau_policy"] == "youden" and cal["fpr_cap"] == 0.10
    assert cal["cal_a_fpr_at_tau"] <= 0.10
    assert cal["report"]["tau_policy"] == "youden" and cal["report"]["cal_a_fpr_at_tau"] == cal["cal_a_fpr_at_tau"]
    assert set(cal["by_source_at_tau"]["cal_b"]) == {"71667"} and set(cal["by_source_at_tau"]["val"]) == {"varroadataset"}
    old = calibrate(za, ya, zb, yb, zv, yv, sp, {"tau_policy": "fpr"})
    assert old["tau_policy"] == "fpr" and old["cal_a_fpr_at_tau"] <= 0.01 + 1e-9
    assert old["tau"] >= cal["tau"] and old["tpr"] <= cal["tpr"]


def test_write_vdi_yaml_records_tau_policy_and_round_trips(tmp_path):
    from app.services.vdi import VdiConfig, load_vdi_config

    p = write_vdi_yaml(tmp_path / "vdi.yaml", version="v0.2.0", tau=0.41, tpr=0.72, fpr=0.08, platt=(0.7, -0.7),
                       tau_policy="youden", fpr_cap=0.10, cal_a_fpr_at_tau=0.093)
    d = yaml.safe_load(p.read_text(encoding="utf-8"))
    assert d["tau_policy"] == "youden" and d["fpr_cap"] == 0.10 and d["cal_a_fpr_at_tau"] == 0.093
    assert load_vdi_config(p) == VdiConfig(tau=0.41, tpr=0.72, fpr=0.08, corrected=True, elevated=3.0, high=10.0,
                                           platt=(0.7, -0.7))


def test_recalibrate_arg_parsing_dispatches_without_training(tmp_path, monkeypatch):
    import training.train_stage2 as ts

    cfg_path = tmp_path / "stage2.yaml"
    cfg_path.write_text("crops: training/crops-320\ntau_policy: youden\nfpr_cap: 0.1\n", encoding="utf-8")
    calls = {}
    monkeypatch.setattr(ts, "recalibrate", lambda run_dir, cfg: calls.setdefault("recal", (run_dir, cfg)))
    monkeypatch.setattr(ts, "train", lambda cfg: calls.setdefault("train", cfg))
    ts.main(["--recalibrate", str(tmp_path / "run"), "--config", str(cfg_path), "--set", "tau_policy=fpr"])
    run_dir, cfg = calls["recal"]
    assert "train" not in calls and run_dir == tmp_path / "run"
    assert cfg["tau_policy"] == "fpr" and cfg["fpr_cap"] == 0.1 and cfg["crops"] == "training/crops-320"
    a = build_parser().parse_args(["--recalibrate", "runs/x"])
    assert a.recalibrate == Path("runs/x") and a.config == Path("training/configs/stage2.yaml")
    assert build_parser().parse_args([]).recalibrate is None
    with pytest.raises(ValueError):
        ts.main(["--recalibrate", "r", "--config", str(cfg_path), "--set", "tau_policy=bogus"])


def test_tasks_recalibrate_target_registered():
    import tasks

    assert "recalibrate" in tasks.TARGETS


def _mini_crops(tmp_path):
    """cal_a/cal_b/val/train 각 8장(64px 노이즈, 라벨 교대) + crops.csv — train/recalibrate 스모크 공용."""
    cv2 = pytest.importorskip("cv2")
    crops = tmp_path / "crops"
    (crops / "img").mkdir(parents=True)
    rng = np.random.default_rng(0)
    rows = []
    for split, src in (("cal_a", "71667-val"), ("cal_b", "71667-val"), ("val", "varroadataset"),
                       ("train", "71667-val")):
        for i in range(8):
            lab = i % 2
            rel = f"img/{split}_{i}.png"
            cv2.imwrite(str(crops / rel), rng.integers(0, 255, (64, 64, 3), dtype=np.uint8))
            rows.append({"path": rel, "label": lab, "source": src, "colony": "c", "device": "d", "split": split,
                         "native_w": 100 + i, "native_h": 90 + i})
    import csv as _csv

    with (crops / "crops.csv").open("w", encoding="utf-8", newline="") as f:
        w = _csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    return crops


def test_recalibrate_smoke_rewrites_outputs(tmp_path):
    torch = pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    import training.train_stage2 as ts

    crops = _mini_crops(tmp_path)
    run = tmp_path / "runs" / "v0.2.0-stage2"
    run.mkdir(parents=True)
    m = ts.build_model(pretrained=False, backbone="resnet18")
    torch.save(m.state_dict(), run / "best.pt")
    ts.write_metadata(run / "metadata.json", m, (1.0, 0.0), 0.5, 64)
    (run / "stage2.onnx").write_bytes(b"sentinel")
    cfg = {"crops": str(crops), "batch": 4, "workers": 0, "seed": 0, "tau_policy": "youden", "fpr_cap": 0.5,
           "vdi_out": str(tmp_path / "vdi.yaml"), "eval_out": str(tmp_path / "eval.json")}
    rep = ts.recalibrate(run, cfg)
    assert rep["recalibrated_from"] == str(run) and rep["tau_policy"] == "youden"
    for vp in (run / "vdi.yaml", tmp_path / "vdi.yaml"):
        d = yaml.safe_load(vp.read_text(encoding="utf-8"))
        assert d["tau_policy"] == "youden" and d["fpr_cap"] == 0.5 and d["tau"] == pytest.approx(rep["tau"])
    meta = json.loads((run / "metadata.json").read_text(encoding="utf-8"))
    assert meta["tau"] == pytest.approx(rep["tau"]) and meta["tau_policy"] == "youden" and meta["img_size"] == 64
    assert (run / "stage2.onnx").read_bytes() == b"sentinel"
    assert json.loads((tmp_path / "eval.json").read_text(encoding="utf-8"))["recalibrated_from"] == str(run)


# ── v0.2.1: AMP opt-in ────────────────────────────────────────────────────────
def test_parse_amp():
    from training.train_stage2 import parse_amp

    assert parse_amp(None) is False and parse_amp(False) is False and parse_amp(True) is True
    assert parse_amp("true") is True and parse_amp("1") is True and parse_amp("false") is False
    assert parse_amp("0") is False and parse_amp("TRUE") is True
    with pytest.raises(ValueError):
        parse_amp("fp16")


def test_amp_override_from_set():
    """--set amp=true 는 apply_overrides 의 bool 변환을 거쳐 True 로 온다."""
    from training.train import apply_overrides
    from training.train_stage2 import parse_amp

    root = Path(__file__).resolve().parents[3]
    cfg = yaml.safe_load((root / "training/configs/stage2.yaml").read_text(encoding="utf-8"))
    assert parse_amp(cfg["amp"]) is False
    assert parse_amp(apply_overrides(cfg, ["amp=true"])["amp"]) is True


def _smoke_cfg(tmp_path, crops, name, amp):
    return {"epochs": 1, "patience": 5, "batch": 4, "lr": 1e-3, "weight_decay": 0.0, "label_smoothing": 0.0,
            "degrade": "none", "size_jitter": None, "img_size": 64, "backbone": "resnet18",
            "select_metric": "cal_a_auroc", "tau_policy": "youden", "fpr_cap": 0.5, "seed": 0, "crops": str(crops),
            "project": str(tmp_path / "runs"), "name": name, "workers": 0, "amp": amp,
            "vdi_out": str(tmp_path / f"vdi_{name}.yaml"), "eval_out": str(tmp_path / f"eval_{name}.json")}


def test_main_rejects_bad_amp_early(tmp_path, monkeypatch):
    """--set amp=fp16 은 학습 전에 ValueError (workers 와 같은 조기 검증)."""
    import training.train_stage2 as ts

    monkeypatch.setattr(ts, "train", lambda cfg: pytest.fail("train 호출되면 안 됨"))
    root = Path(__file__).resolve().parents[3]
    with pytest.raises(ValueError, match="amp"):
        ts.main(["--config", str(root / "training/configs/stage2.yaml"), "--set", "amp=fp16"])


def test_amp_on_cpu_is_identical_to_fp32(tmp_path, monkeypatch):
    """CPU 에서 amp=true 는 autocast 없이 amp=false 와 비트 단위로 같은 학습 결과."""
    torch = pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    pytest.importorskip("onnx")
    import training.train_stage2 as ts

    if torch.cuda.is_available():
        pytest.skip("CPU 전용 동치 테스트 (CUDA 박스에선 amp 가 실제로 켜진다)")
    orig = ts.build_model
    monkeypatch.setattr(ts, "build_model", lambda pretrained=True, backbone=ts.DEFAULT_BACKBONE: orig(False, backbone))
    crops = _mini_crops(tmp_path)
    r_on = ts.train(_smoke_cfg(tmp_path, crops, "on", "true"))
    r_off = ts.train(_smoke_cfg(tmp_path, crops, "off", False))
    a = torch.load(tmp_path / "runs/on/last.pt", weights_only=True)
    b = torch.load(tmp_path / "runs/off/last.pt", weights_only=True)
    assert a.keys() == b.keys() and all(torch.equal(a[k], b[k]) for k in a)
    assert all(v.dtype != torch.float16 for v in a.values())  # 가중치는 fp32 유지
    assert r_on["history"] == r_off["history"] and r_on["tau"] == r_off["tau"]
    assert r_on["amp"] is False and r_off["amp"] is False


def test_train_smoke_amp_recorded_and_onnx_fp32(tmp_path, monkeypatch):
    """1 epoch 스모크. amp=true 요청 → CUDA 면 autocast+GradScaler, CPU(Mac)면 fp32 폴백.
    요청값은 resolved_config, 실제 사용 여부는 metadata/eval JSON 에 남고 ONNX 는 fp32."""
    torch = pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    pytest.importorskip("onnx")
    ort = pytest.importorskip("onnxruntime")
    import training.train_stage2 as ts

    orig = ts.build_model
    monkeypatch.setattr(ts, "build_model", lambda pretrained=True, backbone=ts.DEFAULT_BACKBONE: orig(False, backbone))
    crops = _mini_crops(tmp_path)
    rep = ts.train(_smoke_cfg(tmp_path, crops, "amp", "true"))
    active = torch.cuda.is_available()
    run = tmp_path / "runs" / "amp"
    assert json.loads((run / "resolved_config.json").read_text(encoding="utf-8"))["amp"] is True
    assert json.loads((run / "metadata.json").read_text(encoding="utf-8"))["amp"] is active
    assert rep["amp"] is active
    s = ort.InferenceSession(str(run / "stage2.onnx"), providers=["CPUExecutionProvider"])
    assert s.get_inputs()[0].type == "tensor(float)" and s.get_outputs()[0].type == "tensor(float)"
    logit, feat = s.run(None, {"image": np.zeros((2, 3, 64, 64), np.float32)})
    assert logit.dtype == np.float32 and feat.shape == (2, 512, 2, 2)


# ── v0.2.1: 선택 프로토콜 — select_metric=last · SWA ─────────────────────────────
def test_select_metric_last_is_valid_but_not_an_epoch_metric():
    assert parse_select_metric("last") == "last"
    with pytest.raises(ValueError, match="last"):
        pick_metric({"epoch": 0, "val_auroc": 0.9, "cal_a_auroc": 0.8}, "last")
    with pytest.raises(ValueError):
        parse_select_metric("final")


def test_parse_swa_epochs_bounds():
    from training.train_stage2 import parse_swa_epochs

    assert parse_swa_epochs(None) == 0 and parse_swa_epochs(None, 5) == 0
    assert parse_swa_epochs(0, 5) == 0 and parse_swa_epochs(3, 5) == 3 and parse_swa_epochs(5, 5) == 5
    assert parse_swa_epochs("2", 5) == 2 and parse_swa_epochs(4.0, 5) == 4 and parse_swa_epochs(7) == 7
    for bad in (-1, 6, True, 2.5, "abc", "x2"):
        with pytest.raises(ValueError, match="swa_epochs"):
            parse_swa_epochs(bad, 5)


def test_swa_bn_rows_deterministic_every_nth():
    from training.train_stage2 import SWA_BN_MAX_ROWS, swa_bn_rows

    rows = list(range(45))
    assert swa_bn_rows(rows, cap=20) == rows[::3] and len(swa_bn_rows(rows, cap=20)) <= 20
    assert swa_bn_rows(rows, cap=45) == rows and swa_bn_rows(rows, cap=100) == rows
    assert swa_bn_rows(rows, cap=44) == rows[::2]
    big = list(range(50_001))
    sub = swa_bn_rows(big)
    assert len(sub) <= SWA_BN_MAX_ROWS == 20_000 and sub == big[::3] and swa_bn_rows(big) == sub


def test_main_validates_swa_epochs_and_accepts_last(tmp_path, monkeypatch):
    """swa_epochs > epochs 는 학습 전 ValueError, select_metric=last + swa_epochs 는 train 까지 그대로 전달."""
    import training.train_stage2 as ts

    root = Path(__file__).resolve().parents[3]
    conf = str(root / "training/configs/stage2.yaml")
    monkeypatch.setattr(ts, "train", lambda cfg: pytest.fail("train 호출되면 안 됨"))
    with pytest.raises(ValueError, match="swa_epochs"):
        ts.main(["--config", conf, "--set", "swa_epochs=51"])
    with pytest.raises(ValueError, match="swa_epochs"):
        ts.main(["--config", conf, "--set", "epochs=10", "swa_epochs=11"])
    got = {}
    monkeypatch.setattr(ts, "train", lambda cfg: got.update(cfg) or "ok")
    assert ts.main(["--config", conf, "--set", "select_metric=last", "epochs=15", "swa_epochs=5"]) == "ok"
    assert got["select_metric"] == "last" and got["epochs"] == 15 and got["swa_epochs"] == 5


def _no_pretrained(monkeypatch, ts):
    orig = ts.build_model
    monkeypatch.setattr(ts, "build_model", lambda pretrained=True, backbone=ts.DEFAULT_BACKBONE: orig(False, backbone))


def test_train_select_metric_last_runs_all_epochs_and_keeps_last(tmp_path, monkeypatch):
    """select_metric=last: patience=0 이어도 조기 종료 없이 epochs 전부 → best.pt == last.pt, best_epoch = epochs-1."""
    torch = pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    pytest.importorskip("onnx")
    import training.train_stage2 as ts

    _no_pretrained(monkeypatch, ts)
    crops = _mini_crops(tmp_path)
    cfg = {**_smoke_cfg(tmp_path, crops, "last", False), "epochs": 2, "patience": 0, "select_metric": "last"}
    rep = ts.train(cfg)
    run = tmp_path / "runs" / "last"
    assert [r["epoch"] for r in rep["history"]] == [0, 1] and rep["best_epoch"] == 1
    assert rep["select_metric"] == "last" and rep["swa_epochs"] == 0 and "swa" not in rep
    assert not any(k.startswith("best_") and k != "best_epoch" for k in rep)
    assert rep["val_auroc"] == rep["history"][1]["val_auroc"]
    best = torch.load(run / "best.pt", weights_only=True)
    last = torch.load(run / "last.pt", weights_only=True)
    assert best.keys() == last.keys() and all(torch.equal(best[k], last[k]) for k in best)
    meta = json.loads((run / "metadata.json").read_text(encoding="utf-8"))
    assert meta["select_metric"] == "last" and meta["swa_epochs"] == 0
    assert json.loads((tmp_path / "eval_last.json").read_text(encoding="utf-8"))["select_metric"] == "last"


def test_train_swa_averages_last_k_epochs_and_recomputes_bn(tmp_path, monkeypatch):
    """swa_epochs=2, epochs=3: epoch 1·2 끝 가중치의 등가 평균 + 비증강 train 으로 BN 재계산 → best.pt ≠ last.pt,
    ONNX(logit, featmap) 내보내기, report/metadata 에 swa_epochs=2."""
    torch = pytest.importorskip("torch")
    pytest.importorskip("torchvision")
    pytest.importorskip("onnx")
    ort = pytest.importorskip("onnxruntime")
    from torch.optim import swa_utils

    import training.train_stage2 as ts

    _no_pretrained(monkeypatch, ts)
    snaps, bn_loaders = [], []
    orig_update = swa_utils.AveragedModel.update_parameters
    orig_bn = swa_utils.update_bn

    def spy_update(self, model):
        snaps.append({k: v.detach().clone() for k, v in model.state_dict().items()})
        return orig_update(self, model)

    def spy_bn(loader, model, device=None):
        bn_loaders.append(loader)
        return orig_bn(loader, model, device)

    monkeypatch.setattr(swa_utils.AveragedModel, "update_parameters", spy_update)
    monkeypatch.setattr(swa_utils, "update_bn", spy_bn)
    crops = _mini_crops(tmp_path)
    cfg = {**_smoke_cfg(tmp_path, crops, "swa", False), "epochs": 3, "patience": 0, "swa_epochs": 2}
    rep = ts.train(cfg)
    run = tmp_path / "runs" / "swa"

    assert len(rep["history"]) == 3 and rep["best_epoch"] == 2  # patience=0 이어도 조기 종료 없음
    assert rep["swa_epochs"] == 2 and rep["select_metric"] == "cal_a_auroc"
    assert rep["swa"]["epochs"] == 2 and rep["swa"]["start_epoch"] == 1 and rep["swa"]["bn_rows"] == 8
    assert rep["best_cal_a_auroc"] == rep["swa"]["cal_a_auroc"] == rep["auroc"]["cal_a"]
    assert rep["val_auroc"] == rep["swa"]["val_auroc"]

    best = torch.load(run / "best.pt", weights_only=True)
    last = torch.load(run / "last.pt", weights_only=True)
    assert best.keys() == last.keys()
    # 파라미터 = epoch 1·2 끝 스냅샷의 산술 평균 (last.pt = epoch 2 스냅샷)
    assert len(snaps) == 2 and all(torch.equal(snaps[1][k], last[k]) for k in last)
    params = [k for k, _ in ts.build_model(False, "resnet18").named_parameters()]
    for k in params:
        assert torch.allclose(best[k], (snaps[0][k] + snaps[1][k]) / 2, atol=1e-6), k
    assert any(not torch.equal(best[k], last[k]) for k in params)
    # BN 통계 재계산: 평균 모델 running stats ≠ 마지막 epoch, num_batches_tracked = BN 로더 배치 수(8/4=2)
    assert not torch.equal(best["features.1.running_mean"], last["features.1.running_mean"])
    assert int(best["features.1.num_batches_tracked"]) == 2 and int(last["features.1.num_batches_tracked"]) == 6
    # BN 로더: 비증강·비샘플(순차)·train 행
    (bl,) = bn_loaders
    assert bl.dataset.train is False and isinstance(bl.sampler, torch.utils.data.SequentialSampler)
    assert [r["split"] for r in bl.dataset.rows] == ["train"] * 8

    meta = json.loads((run / "metadata.json").read_text(encoding="utf-8"))
    assert meta["swa_epochs"] == 2 and meta["select_metric"] == "cal_a_auroc"
    ev = json.loads((tmp_path / "eval_swa.json").read_text(encoding="utf-8"))
    assert ev["swa_epochs"] == 2 and ev["swa"]["start_epoch"] == 1
    s = ort.InferenceSession(str(run / "stage2.onnx"), providers=["CPUExecutionProvider"])
    assert [o.name for o in s.get_outputs()] == ["logit", "featmap"]
    logit, feat = s.run(None, {"image": np.zeros((2, 3, 64, 64), np.float32)})
    assert logit.shape == (2,) and feat.shape == (2, 512, 2, 2)
    # ONNX 는 평균 모델(best.pt) 그대로: torch 평균 모델 logit 과 일치
    m = ts.build_model(False, "resnet18")
    m.load_state_dict(best)
    m.eval()
    x = torch.from_numpy(np.random.default_rng(1).normal(size=(2, 3, 64, 64)).astype(np.float32))
    with torch.no_grad():
        zt, _ = m(x)
    zo, _ = s.run(None, {"image": x.numpy()})
    assert np.allclose(zt.numpy(), zo, atol=1e-4)
