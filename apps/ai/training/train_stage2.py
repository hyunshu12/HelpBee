"""Stage-2(벌 단위 응애 감염 이진 분류기) 학습·Platt 보정·τ 선택·ONNX 내보내기 (v0.2.0).

Usage (apps/ai 에서, 학습 박스):
    python -m training.train_stage2 --config training/configs/stage2.yaml [--degrade none|90] [--set k=v ...]
    (= python tasks.py train-stage2 --degrade 90)

데이터: training/crops/crops.csv (make_crops.py 산출물). split 라우팅은 select_splits 참조 —
VarroaDataset `test` 와 EV2 `holdout` 은 Task 12 평가용이라 여기서 절대 쓰지 않는다.

모델: ShuffleNet-V2 x1.0 (ImageNet) → GAP → Linear(1024,1). ONNX 출력은 `logit`(B,) + `featmap`(B,1024,7,7);
계획 2(서빙)는 featmap 과 metadata.json 의 fc_weight 로 CAM 을 계산한다.

보정: cal-A 크롭 logit 으로 Platt(a,b) 적합 → p = σ(a·z+b) → cal-A 음성 FPR 1% 에서 τ 선택 →
cal-B 에서 TPR/FPR 측정(독립 추정). vdi.yaml(`corrected = tpr - fpr >= 0.5`) + metadata.json +
eval_history/v0.2.0-stage2.json(AUROC·ECE 15-bin) 기록.

torch/torchvision/cv2 는 함수 안에서 lazy import — 이 모듈은 numpy/yaml 만으로 import 가능해야 한다
(Mac 테스트 venv 에 torch 없음).
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
import logging
from pathlib import Path

import numpy as np
import yaml

from training.data.make_split_manifest import is_71667, source_group
from training.train import apply_overrides, dump_resolved

logger = logging.getLogger(__name__)

IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], np.float32)

# 계획 2가 읽는 제품 문구 (스펙 §3) — 한 글자도 바꾸지 말 것.
RECOMMENDATIONS = {
    "low": ["응애 감염 징후가 낮게 관찰됐습니다. 다음 점검 시기에 재촬영하세요."],
    "elevated": ["감염 벌 비율이 높게 관찰됐습니다. 가루설탕법(설탕 15g+일벌 100마리)으로 확인하세요."],
    "high": ["감염 벌 비율이 매우 높게 관찰됐습니다. 가루설탕법으로 확인 후 방제 계획을 세우세요."],
    "insufficient": ["벌이 보이도록 소비판을 가까이서 다시 촬영해 주세요."],
    "next_check_windows": ["3월 중순~4월 초", "6월 중순~7월 초", "7월 하순~8월 중순", "10월 하순~11월 초"],
}


# ── 증강 ──────────────────────────────────────────────────────────────────────
def phone_degrade(img, rng, lo_px, hi_px=265):
    """고해상 크롭을 폰 촬영 품질로 열화: 블러 → 폰 스케일 축소 → 센서 노이즈 → ISP 언샤프 → JPEG → 224 복원."""
    import cv2

    tgt = int(rng.integers(lo_px, hi_px + 1))
    k = int(rng.choice([0, 3, 5]))
    x = img
    if k:
        x = cv2.GaussianBlur(x, (k, k), 0)  # 광학 블러
    small = cv2.resize(x, (tgt, tgt), interpolation=cv2.INTER_AREA)  # 폰 스케일로 축소
    small = np.clip(small.astype(np.float32) + rng.normal(0, rng.uniform(1, 6), small.shape), 0, 255).astype(np.uint8)
    sharp = cv2.addWeighted(small, 1.5, cv2.GaussianBlur(small, (0, 0), 1.0), -0.5, 0)  # ISP 언샤프
    _ok, buf = cv2.imencode(".jpg", sharp, [cv2.IMWRITE_JPEG_QUALITY, int(rng.integers(50, 96))])
    jpg = cv2.imdecode(buf, 1)
    return cv2.resize(jpg, (224, 224), interpolation=cv2.INTER_LINEAR)


def size_jitter(img, rng, lo: float = 0.7, hi: float = 1.3):
    """크기 지터: 224 크롭 내용 전체를 s~U(lo,hi) 배로 리사이즈 → s<1 이면 가운데 두고 검정 패딩
    (make_crops.crop_pad_224 와 같은 검정), s>1 이면 가운데 224 를 잘라낸다.

    2026-09-24 shakedown: [native_w, native_h, w/h] 만으로 라벨 AUROC 0.82~0.85 (게이트 < 0.7) — 71667 양성은
    "감염 벌 영역" 박스라 크게 나와 겉보기 크기가 라벨 지름길이 된다. 학습에서 겉보기 크기를 흔들어 끊는다."""
    import cv2

    h, w = img.shape[:2]
    s = float(rng.uniform(lo, hi))
    nh, nw = max(1, int(round(h * s))), max(1, int(round(w * s)))
    if (nh, nw) == (h, w):
        return img
    r = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_AREA if s < 1 else cv2.INTER_LINEAR)
    if nh <= h and nw <= w:
        out = np.zeros_like(img)
        y0, x0 = (h - nh) // 2, (w - nw) // 2
        out[y0:y0 + nh, x0:x0 + nw] = r
        return out
    y0, x0 = (nh - h) // 2, (nw - w) // 2
    return np.ascontiguousarray(r[y0:y0 + h, x0:x0 + w])


def parse_size_jitter(v) -> tuple[float, float] | None:
    """config `size_jitter: [lo, hi]` → (lo, hi). None/빈 값/`none` → 끔."""
    if v is None or (isinstance(v, str) and v.lower() == "none") or (isinstance(v, (list, tuple)) and not v):
        return None
    lo, hi = (float(t) for t in v)
    if not 0 < lo <= hi:
        raise ValueError(f"size_jitter 는 0 < lo <= hi 인 [lo, hi]: {v!r}")
    return lo, hi


def augment(img, rng, degrade_lo: int | None, jitter: tuple[float, float] | None = None):
    """학습 증강: [크기 지터] + [폰 열화] + 좌우/상하 flip · ±15° 회전 · 밝기/대비 ±0.3 · CLAHE p0.3 · 약한 원근(≤~10°)."""
    import cv2

    x = size_jitter(img, rng, *jitter) if jitter else img
    x = phone_degrade(x, rng, degrade_lo) if degrade_lo else x
    if rng.random() < 0.5:
        x = x[:, ::-1]
    if rng.random() < 0.5:
        x = x[::-1]
    x = np.ascontiguousarray(x)
    h, w = x.shape[:2]
    if rng.random() < 0.3:  # 약한 원근: 코너를 ±5% 흔듦 (≈ 최대 10° 기울기)
        j = 0.05 * w
        src = np.float32([[0, 0], [w, 0], [w, h], [0, h]])
        dst = (src + rng.uniform(-j, j, src.shape)).astype(np.float32)
        x = cv2.warpPerspective(x, cv2.getPerspectiveTransform(src, dst), (w, h), borderMode=cv2.BORDER_REFLECT_101)
    m = cv2.getRotationMatrix2D((w / 2, h / 2), float(rng.uniform(-15, 15)), 1.0)
    x = cv2.warpAffine(x, m, (w, h), borderMode=cv2.BORDER_REFLECT_101)
    if rng.random() < 0.3:
        lab = cv2.cvtColor(x, cv2.COLOR_RGB2LAB)
        lab[..., 0] = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(lab[..., 0])
        x = cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)
    alpha, beta = 1 + rng.uniform(-0.3, 0.3), 255 * rng.uniform(-0.3, 0.3)  # 대비·밝기
    return np.clip(x.astype(np.float32) * alpha + beta, 0, 255).astype(np.uint8)


def parse_degrade(v) -> int | None:
    """`none`/None → 열화 없음, 정수(문자열) → lo_px."""
    if v is None or (isinstance(v, str) and v.lower() == "none"):
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        raise ValueError(f"--degrade 는 none 또는 정수 lo_px: {v!r}") from None


# ── 샘플링 ────────────────────────────────────────────────────────────────────
def sample_weights(labels: np.ndarray, sources: np.ndarray) -> np.ndarray:
    """WeightedRandomSampler 가중치 = 클래스 역빈도 × 소스별 양성 prior 균등화.

    1) 소스 s 안에서 각 클래스 가중치를 n_s / (2·n_{s,c}) 로 → 소스 질량은 n_s 유지, 양성 기대비율 0.5 로 동일.
       (한 클래스만 있는 소스는 가중치 1.)
    2) 전역 클래스 균형 보정(양성 총질량 = 음성 총질량). 모든 양성에 같은 배수라 혼합 소스 간 양성 비율은 동일 유지.
    평균 1 로 정규화.
    """
    y = np.asarray(labels).astype(int)
    src = np.asarray(sources)
    w = np.ones(len(y), np.float64)
    for s in np.unique(src):
        m = src == s
        n_s = m.sum()
        counts = {c: int((y[m] == c).sum()) for c in (0, 1)}
        if counts[0] and counts[1]:
            for c in (0, 1):
                w[m & (y == c)] = n_s / (2 * counts[c])
    pos, neg = w[y == 1].sum(), w[y == 0].sum()
    if pos and neg:
        w[y == 1] *= neg / pos
    return w * (len(w) / w.sum())


def select_splits(rows: list[dict]) -> dict[str, list[dict]]:
    """crops.csv 행 → train/val/cal_a/cal_b. train=모든 소스 `train`; val=71667 `val`+VarroaDataset `val`;
    cal_a/cal_b=71667 만. golden·VarroaDataset test·EV2 holdout 은 제외(평가 전용).
    71667 판정은 `is_71667`(접두 매칭) — manifest 태그 `71667-val`/`71667-train` 이 crops.csv 로 그대로 온다."""
    out: dict[str, list[dict]] = {"train": [], "val": [], "cal_a": [], "cal_b": []}
    for r in rows:
        s, sp = r["source"], r["split"]
        if sp == "train":
            out["train"].append(r)
        elif sp == "val" and (is_71667(s) or s == "varroadataset"):
            out["val"].append(r)
        elif sp in ("cal_a", "cal_b") and is_71667(s):
            out[sp].append(r)
    return out


def check_splits(sp: dict[str, list[dict]]) -> None:
    """학습 전 조기 검증: train/val/cal_a/cal_b 가 비었거나 한 클래스뿐이면 ValueError.
    (몇 시간 학습 뒤 Platt/τ 단계에서 np.concatenate([]) 로 죽거나 NaN 이 나는 것을 막는다.)"""
    bad = []
    for k in ("train", "val", "cal_a", "cal_b"):
        labels = {int(r["label"]) for r in sp.get(k, [])}
        if labels != {0, 1}:
            bad.append(f"{k}: n={len(sp.get(k, []))} labels={sorted(labels)}")
    if bad:
        raise ValueError("Stage-2 split 부족 (양성·음성 모두 필요) — " + "; ".join(bad)
                         + " · crops.csv 의 source/split 열 확인 (71667 은 is_71667 접두 매칭)")


# ── 보정·지표 (numpy) ─────────────────────────────────────────────────────────
def fit_platt(logits, y, l2: float = 1e-6, iters: int = 100):
    """σ(a·z+b) 로지스틱 회귀(Newton/IRLS). sklearn LogisticRegression(C=1e6) 과 동치(기울기에만 약한 L2)."""
    z = np.asarray(logits, np.float64).ravel()
    t = np.asarray(y, np.float64).ravel()
    x = np.c_[z, np.ones_like(z)]
    theta = np.zeros(2)
    reg = np.diag([l2, 0.0])
    for _ in range(iters):
        p = 1 / (1 + np.exp(-(x @ theta)))
        g = x.T @ (p - t) + reg @ theta
        h = (x * (p * (1 - p))[:, None]).T @ x + reg + 1e-12 * np.eye(2)
        step = np.linalg.solve(h, g)
        theta -= step
        if np.abs(step).max() < 1e-10:
            break
    return float(theta[0]), float(theta[1])


def choose_tau(p, y, target_fpr=0.01):
    """음성 점수의 (1-target_fpr) 분위수 → p > τ 의 FPR ≤ target_fpr."""
    neg = np.sort(np.asarray(p)[np.asarray(y) == 0])
    return float(neg[int(np.ceil((1 - target_fpr) * len(neg))) - 1])


def measure_rates(p, y, tau):
    p, y = np.asarray(p), np.asarray(y)
    pred = p > tau
    return float(pred[y == 1].mean()), float(pred[y == 0].mean())


def rates_by_source(p, y, sources, tau) -> dict:
    """소스 그룹(`source_group`: 71667 태그 → `71667`, varroadataset, ev2)별 τ 에서의 TPR/FPR.
    한 클래스가 없는 소스는 그 지표 None. shakedown(2026-09-24)에서 71667 cal-A 로 정한 τ 가
    VarroaDataset/EV2 에서 recall ≈ 0 이었다 — 전체 cal-B 한 숫자로는 안 보여 소스별로 남긴다."""
    p = np.asarray(p, np.float64)
    y = np.asarray(y).astype(int)
    groups = np.array([source_group(s) for s in sources])
    out = {}
    for g in sorted(set(groups)):
        m = groups == g
        pred, yy = p[m] > tau, y[m]
        pos, neg = yy == 1, yy == 0
        out[str(g)] = {"tpr": float(pred[pos].mean()) if pos.any() else None,
                       "fpr": float(pred[neg].mean()) if neg.any() else None,
                       "n_pos": int(pos.sum()), "n_neg": int(neg.sum())}
    return out


def auroc(p, y) -> float:
    """Mann-Whitney U (동점은 평균 순위)."""
    p = np.asarray(p, np.float64)
    y = np.asarray(y).astype(bool)
    order = np.argsort(p, kind="mergesort")
    ranks = np.empty(len(p))
    ranks[order] = np.arange(1, len(p) + 1)
    _, inv, cnt = np.unique(p, return_inverse=True, return_counts=True)
    ranks = (np.bincount(inv, weights=ranks) / cnt)[inv]
    npos, nneg = int(y.sum()), int((~y).sum())
    return float((ranks[y].sum() - npos * (npos + 1) / 2) / (npos * nneg))


def ece(p, y, bins: int = 15) -> float:
    """Expected Calibration Error (등간격 bins, 양성 확률 기준)."""
    p = np.asarray(p, np.float64)
    y = np.asarray(y, np.float64)
    idx = np.minimum((p * bins).astype(int), bins - 1)
    total = 0.0
    for b in range(bins):
        m = idx == b
        if m.any():
            total += m.sum() * abs(p[m].mean() - y[m].mean())
    return float(total / len(p))


def sigmoid(z):
    return 1 / (1 + np.exp(-np.asarray(z, np.float64)))


# ── 모델·내보내기 ─────────────────────────────────────────────────────────────
_STAGE2_CLS = None


def _stage2_class():
    global _STAGE2_CLS
    if _STAGE2_CLS is None:
        import torch.nn as nn
        from torchvision.models import ShuffleNet_V2_X1_0_Weights, shufflenet_v2_x1_0

        class Stage2(nn.Module):
            def __init__(self, pretrained=True):
                super().__init__()
                b = shufflenet_v2_x1_0(weights=ShuffleNet_V2_X1_0_Weights.IMAGENET1K_V1 if pretrained else None)
                self.features = nn.Sequential(b.conv1, b.maxpool, b.stage2, b.stage3, b.stage4, b.conv5)
                self.fc = nn.Linear(1024, 1)

            def forward(self, x):
                f = self.features(x)  # (B,1024,7,7)
                return self.fc(f.mean((2, 3))).squeeze(1), f

        _STAGE2_CLS = Stage2
    return _STAGE2_CLS


def build_model(pretrained=True):
    return _stage2_class()(pretrained)


def export_onnx(model, path: Path) -> Path:
    import torch

    model.eval()
    dummy = torch.zeros(1, 3, 224, 224)
    torch.onnx.export(model, dummy, str(path), input_names=["image"], output_names=["logit", "featmap"],
                      opset_version=17, dynamic_axes={"image": {0: "b"}, "logit": {0: "b"}, "featmap": {0: "b"}})
    return Path(path)


def write_metadata(path: Path, model, platt: tuple[float, float], tau: float) -> Path:
    """계획 2 CAM 계산용: fc 가중치(1024) + Platt + τ."""
    fc = model.fc.weight.detach().cpu().numpy().reshape(-1)
    data = {"fc_weight": [float(v) for v in fc], "platt": {"a": float(platt[0]), "b": float(platt[1])},
            "tau": float(tau)}
    path = Path(path)
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return path


def write_vdi_yaml(path: Path, *, version: str, tau: float, tpr: float, fpr: float, platt: tuple[float, float],
                   capture_floor_px_per_mm: float | None = None, by_source: dict | None = None) -> Path:
    data = {
        "version": version,
        "tau": float(tau),
        "tpr": float(tpr),
        "fpr": float(fpr),
        "corrected": bool(tpr - fpr >= 0.5),
        "platt": {"a": float(platt[0]), "b": float(platt[1])},
        "thresholds": {"elevated": 3.0, "high": 10.0},
        "quality": {"blur_laplacian_min": 100, "exposure_mean": [40, 215]},
        "capture_floor_px_per_mm": capture_floor_px_per_mm,
        "recommendations": RECOMMENDATIONS,
        "by_source": by_source,  # cal-B 소스별 {tpr, fpr, n_pos, n_neg} @τ (진단용, 서빙은 읽지 않음)
    }
    path = Path(path)
    path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")
    return path


# ── 학습 루프 ─────────────────────────────────────────────────────────────────
def read_crops(crops_dir: Path) -> list[dict]:
    with (Path(crops_dir) / "crops.csv").open(encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def _dataset(rows, crops_dir: Path, train: bool, degrade_lo: int | None, seed: int,
             jitter: tuple[float, float] | None = None):
    import cv2
    import torch
    from torch.utils.data import Dataset

    from training.data.make_crops import _imread  # 비ASCII(Windows 한국어) 경로 안전

    class CropDataset(Dataset):
        def __len__(self):
            return len(rows)

        def __getitem__(self, i):
            r = rows[i]
            bgr = _imread(crops_dir / r["path"])
            if bgr is None:
                raise FileNotFoundError(f"크롭 이미지 읽기 실패: {crops_dir / r['path']}")
            img = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
            if img.shape[:2] != (224, 224):
                img = cv2.resize(img, (224, 224), interpolation=cv2.INTER_LINEAR)
            if train:
                info = torch.utils.data.get_worker_info()
                rng = np.random.default_rng([seed, i, torch.initial_seed() % (2**32), info.id if info else 0])
                img = augment(img, rng, degrade_lo, jitter)
            x = (img.astype(np.float32) / 255 - IMAGENET_MEAN) / IMAGENET_STD
            return torch.from_numpy(x.transpose(2, 0, 1).copy()), torch.tensor(float(r["label"]))

    return CropDataset()


def _predict_logits(model, loader, device) -> tuple[np.ndarray, np.ndarray]:
    import torch

    model.eval()
    zs, ys = [], []
    with torch.no_grad():
        for x, y in loader:
            z, _ = model(x.to(device, non_blocking=True))
            zs.append(z.float().cpu().numpy())
            ys.append(y.numpy())
    return np.concatenate(zs), np.concatenate(ys).astype(int)


def train(cfg: dict) -> dict:
    import torch
    from torch.utils.data import DataLoader, WeightedRandomSampler

    torch.manual_seed(cfg["seed"])
    np.random.seed(cfg["seed"])
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    crops_dir = Path(cfg["crops"])
    degrade_lo = parse_degrade(cfg.get("degrade"))
    jitter = parse_size_jitter(cfg.get("size_jitter"))
    save_dir = Path(cfg["project"]) / cfg["name"]
    save_dir.mkdir(parents=True, exist_ok=True)
    dump_resolved(cfg, save_dir)

    sp = select_splits(read_crops(crops_dir))
    for k, v in sp.items():
        logger.info(f"{k}: {len(v)} crops ({sum(int(r['label']) for r in v)} pos)")
    check_splits(sp)
    labels = np.array([int(r["label"]) for r in sp["train"]])
    weights = sample_weights(labels, np.array([source_group(r["source"]) for r in sp["train"]]))
    sampler = WeightedRandomSampler(torch.as_tensor(weights, dtype=torch.double), num_samples=len(weights),
                                    replacement=True, generator=torch.Generator().manual_seed(cfg["seed"]))
    # Windows(spawn)는 _dataset 안의 로컬 클래스를 피클할 수 없어 워커 0 (2026-09-24 박스 실측: EOFError in spawn).
    workers = int(cfg.get("workers", 0 if sys.platform == "win32" else 4))
    train_dl = DataLoader(_dataset(sp["train"], crops_dir, True, degrade_lo, cfg["seed"], jitter), batch_size=cfg["batch"],
                          sampler=sampler, num_workers=workers, pin_memory=True, drop_last=True)

    def eval_dl(rows):
        return DataLoader(_dataset(rows, crops_dir, False, None, cfg["seed"]), batch_size=cfg["batch"],
                          shuffle=False, num_workers=workers, pin_memory=True)

    model = build_model(pretrained=True).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=cfg["lr"], weight_decay=cfg["weight_decay"])
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=cfg["epochs"])
    loss_fn = torch.nn.BCEWithLogitsLoss()  # 가중 없음 (불균형은 sampler 가 처리)
    eps = float(cfg["label_smoothing"])
    val_loader = eval_dl(sp["val"])
    best_auc, best_ep, history = -1.0, -1, []
    for ep in range(cfg["epochs"]):
        model.train()
        tot, n = 0.0, 0
        for x, y in train_dl:
            x, y = x.to(device, non_blocking=True), y.to(device, non_blocking=True)
            z, _ = model(x)
            loss = loss_fn(z, y * (1 - eps) + 0.5 * eps)
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
            tot, n = tot + loss.item() * len(y), n + len(y)
        sched.step()
        zv, yv = _predict_logits(model, val_loader, device)
        auc = auroc(zv, yv)
        history.append({"epoch": ep, "train_loss": tot / max(n, 1), "val_auroc": auc})
        logger.info(f"epoch {ep}: loss={tot / max(n, 1):.4f} val_auroc={auc:.4f}")
        if auc > best_auc:
            best_auc, best_ep = auc, ep
            torch.save(model.state_dict(), save_dir / "best.pt")
        elif ep - best_ep >= cfg["patience"]:
            logger.info(f"early stop @ {ep} (best {best_ep}, auroc {best_auc:.4f})")
            break
    torch.save(model.state_dict(), save_dir / "last.pt")

    model.load_state_dict(torch.load(save_dir / "best.pt", map_location=device, weights_only=True))
    za, ya = _predict_logits(model, eval_dl(sp["cal_a"]), device)
    zb, yb = _predict_logits(model, eval_dl(sp["cal_b"]), device)
    platt = fit_platt(za, ya)
    pa, pb = sigmoid(platt[0] * za + platt[1]), sigmoid(platt[0] * zb + platt[1])
    tau = choose_tau(pa, ya, 0.01)
    tpr, fpr = measure_rates(pb, yb, tau)
    zv, yv = _predict_logits(model, val_loader, device)
    pv = sigmoid(platt[0] * zv + platt[1])
    by_source_at_tau = {"cal_b": rates_by_source(pb, yb, [r["source"] for r in sp["cal_b"]], tau),
                        "val": rates_by_source(pv, yv, [r["source"] for r in sp["val"]], tau)}

    model_cpu = model.to("cpu")
    export_onnx(model_cpu, save_dir / "stage2.onnx")
    write_metadata(save_dir / "metadata.json", model_cpu, platt, tau)
    vdi = write_vdi_yaml(Path(cfg.get("vdi_out", "training/configs/vdi.yaml")), version="v0.2.0", tau=tau, tpr=tpr,
                         fpr=fpr, platt=platt, by_source=by_source_at_tau["cal_b"])
    report = {
        "version": "v0.2.0-stage2", "model": "shufflenet_v2_x1_0", "degrade": cfg.get("degrade"),
        "best_epoch": best_ep, "val_auroc": best_auc, "platt": {"a": platt[0], "b": platt[1]},
        "tau": tau, "target_fpr": 0.01, "cal_b": {"tpr": tpr, "fpr": fpr, "corrected": tpr - fpr >= 0.5},
        "by_source_at_tau": by_source_at_tau, "size_jitter": list(jitter) if jitter else None,
        "auroc": {"cal_a": auroc(za, ya), "cal_b": auroc(zb, yb)},
        "ece15": {"cal_a": ece(pa, ya), "cal_b": ece(pb, yb), "cal_b_uncalibrated": ece(sigmoid(zb), yb)},
        "counts": {k: {"n": len(v), "pos": sum(int(r["label"]) for r in v)} for k, v in sp.items()},
        "history": history, "weights": str(save_dir / "best.pt"), "onnx": str(save_dir / "stage2.onnx"),
        "vdi": str(vdi),
    }
    out = Path(cfg.get("eval_out", "training/eval_history/v0.2.0-stage2.json"))
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    logger.info(f"τ={tau:.4f} cal-B TPR={tpr:.3f} FPR={fpr:.4f} → {out}")
    return report


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    p = argparse.ArgumentParser()
    p.add_argument("--config", type=Path, required=True, help="training/configs/stage2.yaml")
    p.add_argument("--degrade", default=None, help="none | <lo_px 정수> (폰 열화 증강)")
    p.add_argument("--set", nargs="*", default=[], metavar="KEY=VALUE", help="임의 config 키 오버라이드")
    a = p.parse_args()
    cfg = yaml.safe_load(a.config.read_text(encoding="utf-8"))
    cfg = apply_overrides(cfg, a.set)
    if a.degrade is not None:
        cfg["degrade"] = a.degrade
    parse_degrade(cfg.get("degrade"))  # 조기 검증
    cfg["config"] = str(a.config)
    train(cfg)


if __name__ == "__main__":
    main()
