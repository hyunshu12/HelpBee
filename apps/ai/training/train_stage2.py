"""Stage-2(벌 단위 응애 감염 이진 분류기) 학습·Platt 보정·τ 선택·ONNX 내보내기 (v0.2.0).

Usage (apps/ai 에서, 학습 박스):
    python -m training.train_stage2 --config training/configs/stage2.yaml [--degrade none|90] [--set k=v ...]
    (= python tasks.py train-stage2 --degrade 90)
    python -m training.train_stage2 --recalibrate <run_dir> [--config ...] [--set k=v ...]
    (= python tasks.py recalibrate <run_dir>) — 학습 없이 best.pt 로 Platt·τ 만 다시 정한다 (ONNX 불변).

데이터: training/crops/crops.csv (make_crops.py 산출물). split 라우팅은 select_splits 참조 —
VarroaDataset `test` 와 EV2 `holdout` 은 Task 12 평가용이라 여기서 절대 쓰지 않는다.

모델: config `backbone` — ShuffleNet-V2 x1.0(기본, featmap 1024ch) · ResNet-18(512ch, v0.2.0 최종) ·
v0.2.1 실험용 ResNet-34(512ch) / ResNet-50(2048ch) / EfficientNet-B0(1280ch), ImageNet 가중치 → GAP → Linear(C,1).
ONNX 출력은 `logit`(B,) + `featmap`(B,C,h,w) (h=w=img_size/32);
계획 2(서빙)는 featmap 과 metadata.json 의 fc_weight 로 CAM 을 계산한다. 입력 크기는 config `img_size`(기본 224).

모델 선택(v3): config `select_metric` — `val_auroc`(v2 동작: 71667+VarroaDataset val) 또는 `cal_a_auroc`(71667 cal-A 만).
cal-B 는 절대 선택에 쓰지 않는다(편향 없는 TPR/FPR 측정 셋으로 유지).
v0.2.1 선택 프로토콜(opt-in): `select_metric: last` = 조기 종료 없이 epochs 전부(cosine 이 0 으로 수렴) → 마지막 epoch.
`swa_epochs: k>0` = 조기 종료 해제 + 마지막 k epoch 끝 가중치 등가 평균(AveragedModel) → 비증강·비샘플 train 부분집합
(≤ SWA_BN_MAX_ROWS)으로 BN 통계 재계산(recompute_bn: BN 만 train 모드, fp32) → 평균 모델이 best.pt·보정·ONNX 경로를 그대로 탄다.
(cal-A 는 사실상 colony 하나라 epoch 별 AUROC 가 0.77↔0.88 로 튀어 "최고 epoch" 은 운 좋은 고-LR iterate 를 고른다.)

보정: cal-A 크롭 logit 으로 Platt(a,b) 적합 → p = σ(a·z+b) → cal-A 에서 τ 선택 (config `tau_policy`:
`youden`(기본, 스펙 v2.2) = cal-A FPR ≤ `fpr_cap`(기본 0.10) 안에서 TPR−FPR 최대 | `fpr` = 음성 FPR `target_fpr`(1%)
분위수) → cal-B 에서 TPR/FPR 측정(독립 추정). vdi.yaml(`corrected = tpr - fpr >= 0.5`) + metadata.json +
eval_history/v0.2.0-stage2.json(AUROC·ECE 15-bin) 기록.

torch/torchvision/cv2 는 함수 안에서 lazy import — 이 모듈은 numpy/yaml 만으로 import 가능해야 한다
(Mac 테스트 venv 에 torch 없음).
"""
from __future__ import annotations

import argparse
import csv
import json
import logging
from pathlib import Path

import numpy as np
import yaml

from training.data.make_split_manifest import is_71667, source_group
from training.train import apply_overrides, dump_resolved

logger = logging.getLogger(__name__)

IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], np.float32)

# `last` = 고정 스케줄: 조기 종료 없이 epochs 전부 → 마지막 epoch 가중치를 best.pt 로 (epoch 지표로 고르지 않음).
SELECT_METRICS = ("val_auroc", "cal_a_auroc", "last")
SWA_BN_MAX_ROWS = 20_000  # SWA BN 재계산에 쓰는 train 행 상한 (등간격 부분집합)
TAU_POLICIES = ("youden", "fpr")
DEFAULT_TAU_POLICY = "youden"
DEFAULT_FPR_CAP = 0.10
DEFAULT_TARGET_FPR = 0.01
# 이름 → featmap 채널 수 (= fc_weight 길이). resnet34/resnet50/efficientnet_b0 은 v0.2.1 실험용 (기본값 불변).
BACKBONES = {"shufflenet_v2_x1_0": 1024, "resnet18": 512, "resnet34": 512, "resnet50": 2048,
             "efficientnet_b0": 1280}
DEFAULT_BACKBONE = "shufflenet_v2_x1_0"
DEFAULT_IMG_SIZE = 224
DEFAULT_WORKERS = 4  # DataLoader 워커 (모든 플랫폼 — CropDataset 은 피클 가능)

# 계획 2가 읽는 제품 문구 (스펙 §3) — 한 글자도 바꾸지 말 것.
RECOMMENDATIONS = {
    "low": ["응애 감염 징후가 낮게 관찰됐습니다. 다음 점검 시기에 재촬영하세요."],
    "elevated": ["감염 벌 비율이 높게 관찰됐습니다. 가루설탕법(설탕 15g+일벌 100마리)으로 확인하세요."],
    "high": ["감염 벌 비율이 매우 높게 관찰됐습니다. 가루설탕법으로 확인 후 방제 계획을 세우세요."],
    "insufficient": ["벌이 보이도록 소비판을 가까이서 다시 촬영해 주세요."],
    "next_check_windows": ["3월 중순~4월 초", "6월 중순~7월 초", "7월 하순~8월 중순", "10월 하순~11월 초"],
}


# ── 증강 ──────────────────────────────────────────────────────────────────────
def parse_select_metric(v) -> str:
    """config `select_metric` 검증. None → `val_auroc`(v2 동작)."""
    v = "val_auroc" if v is None else str(v)
    if v not in SELECT_METRICS:
        raise ValueError(f"select_metric 은 {SELECT_METRICS} 중 하나: {v!r}")
    return v


def parse_tau_policy(v) -> str:
    """config `tau_policy` 검증. None → `youden` (스펙 v2.2 기본)."""
    v = DEFAULT_TAU_POLICY if v is None else str(v)
    if v not in TAU_POLICIES:
        raise ValueError(f"tau_policy 는 {TAU_POLICIES} 중 하나: {v!r}")
    return v


def parse_fpr_cap(v) -> float:
    """config `fpr_cap` (Youden τ 의 cal-A FPR 상한). None → 0.10. [0, 1] 밖이면 ValueError."""
    v = DEFAULT_FPR_CAP if v is None else float(v)
    if not 0.0 <= v <= 1.0:
        raise ValueError(f"fpr_cap 은 [0, 1]: {v!r}")
    return v


def parse_backbone(v) -> str:
    v = DEFAULT_BACKBONE if v is None else str(v)
    if v not in BACKBONES:
        raise ValueError(f"backbone 은 {tuple(BACKBONES)} 중 하나: {v!r}")
    return v


def parse_amp(v) -> bool:
    """config `amp` (혼합 정밀도, opt-in). None/false → False (v0.2.0 재현 경로). bool 또는 true/false/1/0/yes/no."""
    if v is None or isinstance(v, bool):
        return bool(v)
    t = str(v).strip().lower()
    if t in ("true", "1", "yes", "on"):
        return True
    if t in ("false", "0", "no", "off", "none", ""):
        return False
    raise ValueError(f"amp 는 true/false: {v!r}")


def parse_swa_epochs(v, epochs=None) -> int:
    """config `swa_epochs` (마지막 k epoch 가중치 등가 평균, SWAD 식). None → 0(끔). 0 ≤ k ≤ epochs 정수.
    bool·비정수·음수·epochs 초과면 ValueError."""
    if v is None:
        return 0
    if isinstance(v, bool) or (isinstance(v, float) and not v.is_integer()):
        raise ValueError(f"swa_epochs 는 0 이상 정수: {v!r}")
    try:
        k = int(v.strip()) if isinstance(v, str) else int(v)
    except (TypeError, ValueError):
        raise ValueError(f"swa_epochs 는 0 이상 정수: {v!r}") from None
    if k < 0 or (epochs is not None and k > int(epochs)):
        raise ValueError(f"swa_epochs 는 0 ≤ k ≤ epochs({epochs}): {k}")
    return k


def swa_bn_rows(rows: list, cap: int = SWA_BN_MAX_ROWS) -> list:
    """SWA BN 재계산용 결정적 부분집합: cap 이하면 전부, 아니면 등간격(every n-th, n = ceil(len/cap))."""
    rows = list(rows)
    step = max(1, -(-len(rows) // int(cap)))
    return rows[::step]


def pick_metric(row: dict, select_metric: str) -> float:
    """epoch history 행에서 모델 선택 지표 값. cal_b 계열 키는 선택에 쓰지 않는다(불편 추정 셋).
    `last` 는 epoch 지표로 고르지 않으므로 ValueError (train 은 고정 스케줄 경로로 간다)."""
    m = parse_select_metric(select_metric)
    if m == "last":
        raise ValueError("select_metric=last 는 epoch 지표로 선택하지 않는다 (마지막 epoch 가 선택 모델)")
    return float(row[m])


def is_improvement(value: float, best: float) -> bool:
    """NaN(한 클래스뿐인 split 등)은 개선으로 치지 않는다."""
    return bool(np.isfinite(value) and value > best)


def model_spec(weights: Path | None = None, backbone: str | None = None, img_size: int | None = None) -> tuple[str, int]:
    """평가 스크립트용 (backbone, img_size). 명시값 > weights 옆 metadata.json > 기본값(shufflenet, 224)."""
    meta = {}
    if weights is not None:
        mp = Path(weights).parent / "metadata.json"
        if mp.exists():
            meta = json.loads(mp.read_text(encoding="utf-8"))
    bb = parse_backbone(backbone if backbone is not None else meta.get("backbone"))
    size = int(img_size if img_size is not None else meta.get("img_size", DEFAULT_IMG_SIZE))
    return bb, size


def onnx_input_size(shape, default: int = DEFAULT_IMG_SIZE) -> int:
    """ONNX 입력 shape [b,3,H,W] → H (정수가 아니면 default). 정사각 입력 가정."""
    h = shape[2] if shape is not None and len(shape) == 4 else None
    return int(h) if isinstance(h, (int, np.integer)) and h > 0 else default


def to_input_size(img, size: int):
    """크롭 PNG(make_crops --crop-size 로 224/320 등) → 모델 입력 size×size. 같으면 그대로."""
    import cv2

    if img.shape[:2] == (size, size):
        return img
    interp = cv2.INTER_AREA if max(img.shape[:2]) > size else cv2.INTER_LINEAR
    return cv2.resize(img, (size, size), interpolation=interp)


def phone_degrade(img, rng, lo_px, hi_px=265):
    """고해상 크롭을 폰 촬영 품질로 열화: 블러 → 폰 스케일 축소 → 센서 노이즈 → ISP 언샤프 → JPEG → 입력 크기 복원."""
    import cv2

    h, w = img.shape[:2]
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
    return cv2.resize(jpg, (w, h), interpolation=cv2.INTER_LINEAR)


def size_jitter(img, rng, lo: float = 0.7, hi: float = 1.3):
    """크기 지터: 크롭(임의 정사각 크기) 내용 전체를 s~U(lo,hi) 배로 리사이즈 → s<1 이면 가운데 두고 검정 패딩
    (make_crops.crop_pad_224 와 같은 검정), s>1 이면 가운데 원래 크기를 잘라낸다.

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


def check_splits(sp: dict[str, list[dict]], keys=("train", "val", "cal_a", "cal_b")) -> None:
    """학습 전 조기 검증: train/val/cal_a/cal_b 가 비었거나 한 클래스뿐이면 ValueError.
    (몇 시간 학습 뒤 Platt/τ 단계에서 np.concatenate([]) 로 죽거나 NaN 이 나는 것을 막는다.)"""
    bad = []
    for k in keys:
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


def choose_tau_youden(p, y, fpr_cap: float = DEFAULT_FPR_CAP) -> float:
    """Youden τ: 후보 τ(점수 고유값, 판정은 p > τ) 중 FPR ≤ fpr_cap 을 만족하는 것에서 TPR−FPR 최대.
    동점이면 큰 τ(보수적). fpr_cap=0 이면 음성 최고점 이상 중 TPR 최대 = 음성 최고점으로 수렴.
    τ = max(p) 는 항상 FPR 0 이라 feasible 집합이 비지 않는다."""
    p = np.asarray(p, np.float64).ravel()
    y = np.asarray(y).astype(int).ravel()
    pos, neg = np.sort(p[y == 1]), np.sort(p[y == 0])
    if not len(pos) or not len(neg):
        raise ValueError(f"choose_tau_youden: 양성·음성 모두 필요 (n_pos={len(pos)}, n_neg={len(neg)})")
    cand = np.unique(p)
    tpr = 1 - np.searchsorted(pos, cand, side="right") / len(pos)
    fpr = 1 - np.searchsorted(neg, cand, side="right") / len(neg)
    j = np.where(fpr <= float(fpr_cap) + 1e-12, tpr - fpr, -np.inf)
    best = np.flatnonzero(j == j.max())[-1]  # 동점 → 가장 큰 τ
    return float(cand[best])


def select_tau(p, y, policy: str = DEFAULT_TAU_POLICY, fpr_cap: float = DEFAULT_FPR_CAP,
               target_fpr: float = DEFAULT_TARGET_FPR) -> float:
    """config `tau_policy` 에 따라 cal-A 점수로 τ 선택 (`youden` | `fpr`)."""
    if parse_tau_policy(policy) == "youden":
        return choose_tau_youden(p, y, fpr_cap)
    return choose_tau(p, y, target_fpr)


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
        from torchvision import models as tvm

        # backbone → (생성자, ImageNet 가중치 enum 이름). 가중치는 모두 IMAGENET1K_V1.
        resnets = {"resnet18": (tvm.resnet18, "ResNet18_Weights"), "resnet34": (tvm.resnet34, "ResNet34_Weights"),
                   "resnet50": (tvm.resnet50, "ResNet50_Weights")}

        class Stage2(nn.Module):
            def __init__(self, pretrained=True, backbone=DEFAULT_BACKBONE):
                super().__init__()
                backbone = parse_backbone(backbone)
                if backbone in resnets:
                    ctor, wname = resnets[backbone]
                    b = ctor(weights=getattr(tvm, wname).IMAGENET1K_V1 if pretrained else None)
                    self.features = nn.Sequential(b.conv1, b.bn1, b.relu, b.maxpool,
                                                  b.layer1, b.layer2, b.layer3, b.layer4)
                elif backbone == "efficientnet_b0":
                    b = tvm.efficientnet_b0(weights=tvm.EfficientNet_B0_Weights.IMAGENET1K_V1 if pretrained else None)
                    self.features = b.features  # 마지막 1×1 conv 까지 → 1280ch
                else:
                    b = tvm.shufflenet_v2_x1_0(weights=tvm.ShuffleNet_V2_X1_0_Weights.IMAGENET1K_V1 if pretrained else None)
                    self.features = nn.Sequential(b.conv1, b.maxpool, b.stage2, b.stage3, b.stage4, b.conv5)
                self.backbone = backbone
                self.fc = nn.Linear(BACKBONES[backbone], 1)

            def forward(self, x):
                f = self.features(x)  # (B,C,h,w) — C=BACKBONES[backbone], h=w=img_size/32
                return self.fc(f.mean((2, 3))).squeeze(1), f

        _STAGE2_CLS = Stage2
    return _STAGE2_CLS


def build_model(pretrained=True, backbone: str = DEFAULT_BACKBONE):
    return _stage2_class()(pretrained, backbone)


def export_onnx(model, path: Path, img_size: int = DEFAULT_IMG_SIZE) -> Path:
    import torch

    model.eval()
    dummy = torch.zeros(1, 3, int(img_size), int(img_size))
    torch.onnx.export(model, dummy, str(path), input_names=["image"], output_names=["logit", "featmap"],
                      opset_version=17, dynamic_axes={"image": {0: "b"}, "logit": {0: "b"}, "featmap": {0: "b"}})
    return Path(path)


def write_metadata(path: Path, model, platt: tuple[float, float], tau: float,
                   img_size: int = DEFAULT_IMG_SIZE, tau_policy: str | None = None, amp: bool | None = None,
                   select_metric: str | None = None, swa_epochs: int | None = None) -> Path:
    """계획 2 CAM 계산용: fc 가중치(featmap 채널 수 길이) + Platt + τ + backbone/feat_channels/img_size.
    select_metric/swa_epochs 는 추적용(서빙은 읽지 않음) — None 이면 키를 쓰지 않는다."""
    fc = model.fc.weight.detach().cpu().numpy().reshape(-1)
    data = {"fc_weight": [float(v) for v in fc], "platt": {"a": float(platt[0]), "b": float(platt[1])},
            "tau": float(tau), "backbone": getattr(model, "backbone", DEFAULT_BACKBONE),
            "feat_channels": int(fc.shape[0]), "img_size": int(img_size)}
    if tau_policy is not None:
        data["tau_policy"] = parse_tau_policy(tau_policy)
    if amp is not None:
        data["amp"] = bool(amp)  # 학습 시 혼합 정밀도 사용 여부 (추적용 — ONNX 는 항상 fp32)
    if select_metric is not None:
        data["select_metric"] = parse_select_metric(select_metric)
    if swa_epochs is not None:
        data["swa_epochs"] = int(swa_epochs)
    path = Path(path)
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    return path


def write_vdi_yaml(path: Path, *, version: str, tau: float, tpr: float, fpr: float, platt: tuple[float, float],
                   capture_floor_px_per_mm: float | None = None, by_source: dict | None = None,
                   tau_policy: str | None = None, fpr_cap: float | None = None,
                   cal_a_fpr_at_tau: float | None = None) -> Path:
    data = {
        "version": version,
        "tau": float(tau),
        "tpr": float(tpr),
        "fpr": float(fpr),
        "corrected": bool(tpr - fpr >= 0.5),
        "platt": {"a": float(platt[0]), "b": float(platt[1])},
        "tau_policy": tau_policy,  # youden | fpr (진단·재현용, 서빙은 tau 만 읽는다)
        "fpr_cap": None if fpr_cap is None else float(fpr_cap),
        "cal_a_fpr_at_tau": None if cal_a_fpr_at_tau is None else float(cal_a_fpr_at_tau),
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


class CropDataset:
    """crops.csv 행 → (정규화 텐서 (3,H,W), 라벨). 맵 스타일 — DataLoader 는 __len__/__getitem__ 만 쓴다
    (torch Dataset 상속 불필요 → 이 모듈은 torch 없이 import 가능).

    모듈 최상위 클래스라 Windows spawn 워커로 피클된다 (2026-09-24 박스: `_dataset` 안의 로컬 클래스는
    EOFError in spawn → workers 0 강제, epoch 7.5분). 속성은 모두 피클 가능한 값(list/Path/int/tuple)만 둔다.

    증강 RNG(학습 전용): 샘플마다 `[seed, i, torch.initial_seed(), worker id]` 로 새로 만든다 — workers=0 이면
    2026-09-25 이전과 같은 값. workers>0 이면 워커 torch seed(= DataLoader base_seed + worker id)가 epoch 마다
    새로 뽑혀(비영속 워커) 같은 샘플도 epoch 별로 다른 증강을 받는다."""

    def __init__(self, rows, crops_dir: Path, train: bool, degrade_lo: int | None, seed: int,
                 jitter: tuple[float, float] | None = None, img_size: int = DEFAULT_IMG_SIZE):
        self.rows = list(rows)
        self.crops_dir = Path(crops_dir)
        self.train = bool(train)
        self.degrade_lo = degrade_lo
        self.seed = int(seed)
        self.jitter = tuple(jitter) if jitter else None
        self.img_size = int(img_size)

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, i):
        import cv2
        import torch

        from training.data.make_crops import _imread  # 비ASCII(Windows 한국어) 경로 안전

        r = self.rows[i]
        bgr = _imread(self.crops_dir / r["path"])
        if bgr is None:
            raise FileNotFoundError(f"크롭 이미지 읽기 실패: {self.crops_dir / r['path']}")
        img = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        img = to_input_size(img, self.img_size)
        if self.train:
            info = torch.utils.data.get_worker_info()
            rng = np.random.default_rng([self.seed, i, torch.initial_seed() % (2**32), info.id if info else 0])
            img = augment(img, rng, self.degrade_lo, self.jitter)
        x = (img.astype(np.float32) / 255 - IMAGENET_MEAN) / IMAGENET_STD
        return torch.from_numpy(x.transpose(2, 0, 1).copy()), torch.tensor(float(r["label"]))


def _dataset(rows, crops_dir: Path, train: bool, degrade_lo: int | None, seed: int,
             jitter: tuple[float, float] | None = None, img_size: int = DEFAULT_IMG_SIZE) -> CropDataset:
    """CropDataset 팩토리 (기존 호출부·eval_stage2 호환)."""
    return CropDataset(rows, crops_dir, train, degrade_lo, seed, jitter, img_size)


def seed_worker(worker_id: int) -> None:
    """DataLoader worker_init_fn: 전역 numpy/random 을 워커 torch seed(base_seed + worker_id, 결정적)로 고정.
    CropDataset 증강은 샘플별 자체 RNG 라 영향 없음 — 전역 RNG 를 쓰는 코드(cv2 제외 라이브러리)가 워커마다
    같은 난수를 내지 않게 하는 안전장치. 모듈 최상위 함수라 spawn 피클 가능."""
    import random

    import torch

    s = torch.initial_seed() % (2**32)
    np.random.seed(s)
    random.seed(s)


def resolve_workers(cfg: dict) -> int:
    """config `workers` (기본 4, 모든 플랫폼 — CropDataset 이 피클 가능해 Windows spawn 도 OK). 음수면 ValueError."""
    w = int(cfg.get("workers", DEFAULT_WORKERS))
    if w < 0:
        raise ValueError(f"workers 는 0 이상: {w}")
    return w


def loader_kwargs(workers: int, seed: int) -> dict:
    """DataLoader 공통 워커 인자. workers>0 이면 seed_worker + 전용 generator(base_seed 결정적, 전역 RNG 소비 무관).
    workers=0 은 기존과 같은 인자만 (동작 동일)."""
    if workers <= 0:
        return {"num_workers": 0}
    import torch

    return {"num_workers": workers, "worker_init_fn": seed_worker,
            "generator": torch.Generator().manual_seed(int(seed))}


def _autocast(enabled: bool):
    """enabled 면 CUDA fp16 autocast, 아니면 nullcontext (fp32 경로 그대로)."""
    import contextlib

    if not enabled:
        return contextlib.nullcontext()
    import torch

    return torch.autocast("cuda", dtype=torch.float16)


def _grad_scaler():
    """CUDA GradScaler. torch.amp.GradScaler("cuda")(torch ≥ 2.3) 가 없으면 torch.cuda.amp.GradScaler 로 폴백."""
    import torch

    if hasattr(getattr(torch, "amp", None), "GradScaler"):
        return torch.amp.GradScaler("cuda")
    return torch.cuda.amp.GradScaler()


def recompute_bn(loader, model, device=None):
    """SWA 평균 모델의 BatchNorm running stats 재추정 (torch swa_utils.update_bn 대체).

    update_bn 은 model.train() 전체를 켜서 EfficientNet 의 StochasticDepth·Dropout 이 블록을 떨군 채 통계를 모은다
    → eval(서빙) 활성과 어긋난다. 여기서는 모든 _BatchNorm 의 running stats 를 리셋·momentum=None(누적 평균,
    update_bn 과 동일)으로 두고 **BN 모듈만** train 모드, 나머지(StochasticDepth/Dropout 등)는 eval 모드로
    no_grad·fp32(autocast 없음) forward. 입력 = batch[0]. 끝나면 momentum 복원, 모델은 eval 모드로 반환."""
    import torch
    from torch.nn.modules.batchnorm import _BatchNorm

    bns = [m for m in model.modules() if isinstance(m, _BatchNorm)]
    model.eval()
    momenta = {}
    for m in bns:
        m.reset_running_stats()
        momenta[m] = m.momentum
        m.momentum = None
        m.train()
    try:
        if bns:
            with torch.no_grad():
                for batch in loader:
                    x = batch[0] if isinstance(batch, (list, tuple)) else batch
                    if device is not None:
                        x = x.to(device)
                    model(x.float())
    finally:
        for m, mom in momenta.items():
            m.momentum = mom
        model.eval()
    return model


def _predict_logits(model, loader, device, amp: bool = False) -> tuple[np.ndarray, np.ndarray]:
    """logit 은 항상 float32 로 모은다 (sigmoid/Platt/AUROC 는 fp32). amp=True 는 CUDA autocast 로 forward 만."""
    import torch

    model.eval()
    zs, ys = [], []
    with torch.no_grad():
        for x, y in loader:
            with _autocast(amp):
                z, _ = model(x.to(device, non_blocking=True))
            zs.append(z.float().cpu().numpy())
            ys.append(y.numpy())
    return np.concatenate(zs), np.concatenate(ys).astype(int)


def train(cfg: dict) -> dict:
    import torch
    from torch.optim import swa_utils
    from torch.utils.data import DataLoader, WeightedRandomSampler

    torch.manual_seed(cfg["seed"])
    np.random.seed(cfg["seed"])
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    crops_dir = Path(cfg["crops"])
    degrade_lo = parse_degrade(cfg.get("degrade"))
    jitter = parse_size_jitter(cfg.get("size_jitter"))
    select_metric = parse_select_metric(cfg.get("select_metric"))
    swa_epochs = parse_swa_epochs(cfg.get("swa_epochs"), cfg["epochs"])
    fixed_schedule = select_metric == "last" or swa_epochs > 0  # 조기 종료 해제 — epochs 전부 (cosine → 0)
    swa_start = cfg["epochs"] - swa_epochs
    backbone = parse_backbone(cfg.get("backbone"))
    img_size = int(cfg.get("img_size", DEFAULT_IMG_SIZE))
    cfg["amp"] = parse_amp(cfg.get("amp"))  # 요청값 → resolved_config.json
    use_amp = cfg["amp"] and device.type == "cuda"  # 실제 사용 여부 (CPU 면 fp32 그대로)
    if cfg["amp"] and not use_amp:
        logger.warning("amp=true 이지만 CUDA 없음 → fp32 로 학습")
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
    workers = resolve_workers(cfg)  # CropDataset 은 모듈 최상위라 Windows spawn 워커도 피클 가능
    train_dl = DataLoader(_dataset(sp["train"], crops_dir, True, degrade_lo, cfg["seed"], jitter, img_size),
                          batch_size=cfg["batch"], sampler=sampler, pin_memory=True, drop_last=True,
                          **loader_kwargs(workers, cfg["seed"]))

    def eval_dl(rows):
        return DataLoader(_dataset(rows, crops_dir, False, None, cfg["seed"], img_size=img_size), batch_size=cfg["batch"],
                          shuffle=False, pin_memory=True, **loader_kwargs(workers, cfg["seed"]))

    model = build_model(pretrained=True, backbone=backbone).to(device)
    opt = torch.optim.AdamW(model.parameters(), lr=cfg["lr"], weight_decay=cfg["weight_decay"])
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, T_max=cfg["epochs"])
    loss_fn = torch.nn.BCEWithLogitsLoss()  # 가중 없음 (불균형은 sampler 가 처리)
    # AMP: 모델은 fp32 마스터 가중치 그대로(.half() 금지) — autocast 는 forward 만, GradScaler 로 역전파.
    scaler = _grad_scaler() if use_amp else None
    eps = float(cfg["label_smoothing"])
    val_loader = eval_dl(sp["val"])
    cal_a_loader = eval_dl(sp["cal_a"])  # 71667 만 — select_metric=cal_a_auroc 일 때 선택 기준. cal_b 는 선택에 안 씀.
    best_score, best_ep, history = -1.0, -1, []
    swa = None  # swa_epochs>0: 마지막 k epoch 끝 가중치의 등가 평균 (파라미터만 — BN 통계는 학습 후 recompute_bn)
    for ep in range(cfg["epochs"]):
        model.train()
        tot, n = 0.0, 0
        for x, y in train_dl:
            x, y = x.to(device, non_blocking=True), y.to(device, non_blocking=True)
            if use_amp:
                with _autocast(True):
                    z, _ = model(x)
                    loss = loss_fn(z.float(), y * (1 - eps) + 0.5 * eps)
                opt.zero_grad(set_to_none=True)
                scaler.scale(loss).backward()
                scaler.step(opt)
                scaler.update()
            else:
                z, _ = model(x)
                loss = loss_fn(z, y * (1 - eps) + 0.5 * eps)
                opt.zero_grad(set_to_none=True)
                loss.backward()
                opt.step()
            tot, n = tot + loss.item() * len(y), n + len(y)
        sched.step()
        zv, yv = _predict_logits(model, val_loader, device, use_amp)  # 선택 지표용 — autocast 허용
        zca, yca = _predict_logits(model, cal_a_loader, device, use_amp)
        row = {"epoch": ep, "train_loss": tot / max(n, 1), "val_auroc": auroc(zv, yv), "cal_a_auroc": auroc(zca, yca)}
        history.append(row)
        logger.info(f"epoch {ep}: loss={row['train_loss']:.4f} val_auroc={row['val_auroc']:.4f} "
                    f"cal_a_auroc={row['cal_a_auroc']:.4f} (select={select_metric})")
        if swa_epochs and ep >= swa_start:
            if swa is None:
                swa = swa_utils.AveragedModel(model)  # 기본 avg_fn = 등가 누적 평균
            swa.update_parameters(model)
            logger.info(f"SWA 갱신 @ epoch {ep} ({swa.n_averaged.item()}/{swa_epochs})")
        if fixed_schedule:
            continue  # 선택·조기 종료 없음
        score = pick_metric(row, select_metric)
        if is_improvement(score, best_score):
            best_score, best_ep = score, ep
            torch.save(model.state_dict(), save_dir / "best.pt")
        elif ep - best_ep >= cfg["patience"]:
            logger.info(f"early stop @ {ep} (best {best_ep}, {select_metric} {best_score:.4f})")
            break
    torch.save(model.state_dict(), save_dir / "last.pt")

    bn_rows = None
    if swa is not None:
        # BN 재계산: 비증강·비샘플 train 부분집합, 셔플 없음, fp32(autocast 없음), BN 만 train 모드.
        bn_rows = swa_bn_rows(sp["train"])
        logger.info(f"SWA: epoch {swa_start}~{cfg['epochs'] - 1} 평균 → BN 재계산 ({len(bn_rows)} train 크롭, 비증강)")
        recompute_bn(eval_dl(bn_rows), swa.module, device=device)
        torch.save(swa.module.state_dict(), save_dir / "best.pt")
        best_ep = len(history) - 1
    elif select_metric == "last":
        torch.save(model.state_dict(), save_dir / "best.pt")  # 마지막 epoch = 선택 모델
        best_ep = len(history) - 1

    model.load_state_dict(torch.load(save_dir / "best.pt", map_location=device, weights_only=True))
    # Platt·τ·cal-B 는 amp 와 무관하게 fp32 forward — 서빙 ONNX(fp32) logit 과 같은 분포에서 보정해야 한다.
    za, ya = _predict_logits(model, cal_a_loader, device)
    zb, yb = _predict_logits(model, eval_dl(sp["cal_b"]), device)
    zv, yv = _predict_logits(model, val_loader, device)
    swa_report = None
    if swa is not None:  # 평균 모델의 fp32 val/cal-A AUROC (1회)
        swa_report = {"epochs": swa_epochs, "start_epoch": swa_start, "bn_rows": len(bn_rows),
                      "val_auroc": auroc(zv, yv), "cal_a_auroc": auroc(za, ya)}
        logger.info(f"SWA 평균 모델: val_auroc={swa_report['val_auroc']:.4f} "
                    f"cal_a_auroc={swa_report['cal_a_auroc']:.4f}")
    cal = calibrate(za, ya, zb, yb, zv, yv, sp, cfg)

    model_cpu = model.to("cpu")
    export_onnx(model_cpu, save_dir / "stage2.onnx", img_size)
    write_metadata(save_dir / "metadata.json", model_cpu, cal["platt"], cal["tau"], img_size, cal["tau_policy"],
                   amp=use_amp, select_metric=select_metric, swa_epochs=swa_epochs)
    vdi = _write_vdi(cal, Path(cfg.get("vdi_out", "training/configs/vdi.yaml")), save_dir / "vdi.yaml")
    # best_{metric} = 선택 모델의 지표 값 (SWA 면 평균 모델 fp32 값). select_metric=last 는 epoch 지표로 안 고르므로 키 없음.
    selection = {"select_metric": select_metric, "swa_epochs": swa_epochs}
    if select_metric != "last":
        selection[f"best_{select_metric}"] = swa_report[select_metric] if swa_report else best_score
    if swa_report:
        val_selected = swa_report["val_auroc"]
    else:
        val_selected = history[best_ep]["val_auroc"] if best_ep >= 0 else None
    report = {
        "version": "v0.2.0-stage2", "model": backbone, "img_size": img_size, "degrade": cfg.get("degrade"),
        "amp": use_amp,
        **selection,
        "best_epoch": best_ep, "val_auroc": val_selected,
        **cal["report"], "size_jitter": list(jitter) if jitter else None,
        "counts": {k: {"n": len(v), "pos": sum(int(r["label"]) for r in v)} for k, v in sp.items()},
        "history": history, **({"swa": swa_report} if swa_report else {}),
        "weights": str(save_dir / "best.pt"), "onnx": str(save_dir / "stage2.onnx"),
        "vdi": str(vdi),
    }
    out = Path(cfg.get("eval_out", "training/eval_history/v0.2.0-stage2.json"))
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    logger.info(f"τ={cal['tau']:.4f} ({cal['tau_policy']}) cal-B TPR={cal['tpr']:.3f} FPR={cal['fpr']:.4f} → {out}")
    return report


def calibrate(za, ya, zb, yb, zv, yv, sp: dict[str, list[dict]], cfg: dict) -> dict:
    """(numpy) cal-A logit → Platt → τ(`tau_policy`) → cal-B TPR/FPR + 소스별 rates. 학습·--recalibrate 공용.
    반환: platt/tau/tpr/fpr/tau_policy/fpr_cap/target_fpr/cal_a_fpr_at_tau/by_source_at_tau + eval JSON 조각 `report`."""
    policy = parse_tau_policy(cfg.get("tau_policy"))
    fpr_cap = parse_fpr_cap(cfg.get("fpr_cap"))
    target_fpr = float(cfg.get("target_fpr", DEFAULT_TARGET_FPR))
    platt = fit_platt(za, ya)
    pa, pb, pv = (sigmoid(platt[0] * np.asarray(z) + platt[1]) for z in (za, zb, zv))
    tau = select_tau(pa, ya, policy, fpr_cap, target_fpr)
    cal_a_fpr = measure_rates(pa, ya, tau)[1]
    tpr, fpr = measure_rates(pb, yb, tau)
    by_source_at_tau = {"cal_b": rates_by_source(pb, yb, [r["source"] for r in sp["cal_b"]], tau),
                        "val": rates_by_source(pv, yv, [r["source"] for r in sp["val"]], tau)}
    report = {
        "platt": {"a": platt[0], "b": platt[1]}, "tau": tau, "tau_policy": policy, "fpr_cap": fpr_cap,
        "target_fpr": target_fpr, "cal_a_fpr_at_tau": cal_a_fpr,
        "cal_b": {"tpr": tpr, "fpr": fpr, "corrected": tpr - fpr >= 0.5},
        "by_source_at_tau": by_source_at_tau,
        "auroc": {"cal_a": auroc(za, ya), "cal_b": auroc(zb, yb)},
        "ece15": {"cal_a": ece(pa, ya), "cal_b": ece(pb, yb), "cal_b_uncalibrated": ece(sigmoid(zb), yb)},
    }
    return {"platt": platt, "tau": tau, "tpr": tpr, "fpr": fpr, "tau_policy": policy, "fpr_cap": fpr_cap,
            "target_fpr": target_fpr, "cal_a_fpr_at_tau": cal_a_fpr, "by_source_at_tau": by_source_at_tau,
            "report": report}


def _write_vdi(cal: dict, *paths: Path) -> Path:
    """calibrate() 결과로 vdi.yaml 을 여러 경로에 같은 내용으로 쓴다. 첫 경로 반환."""
    for path in paths:
        write_vdi_yaml(path, version="v0.2.0", tau=cal["tau"], tpr=cal["tpr"], fpr=cal["fpr"], platt=cal["platt"],
                       by_source=cal["by_source_at_tau"]["cal_b"], tau_policy=cal["tau_policy"],
                       fpr_cap=cal["fpr_cap"], cal_a_fpr_at_tau=cal["cal_a_fpr_at_tau"])
    return Path(paths[0])


def recalibrate(run_dir: Path, cfg: dict) -> dict:
    """학습 없이 <run_dir>/best.pt 로 cal_a/cal_b/val 을 다시 예측해 Platt·τ(`tau_policy`) 재선택.
    backbone/img_size 는 <run_dir>/metadata.json. 갱신: <run_dir>/vdi.yaml · cfg vdi_out · cfg eval_out
    (`recalibrated_from` 추가, 같은 run 의 기존 JSON 이면 history 등 학습 필드 보존) · metadata.json(platt/tau/tau_policy).
    stage2.onnx 는 건드리지 않는다 (Platt·τ 는 ONNX 밖)."""
    import torch
    from torch.utils.data import DataLoader

    run_dir = Path(run_dir)
    weights, meta_path = run_dir / "best.pt", run_dir / "metadata.json"
    if not weights.exists() or not meta_path.exists():
        raise FileNotFoundError(f"--recalibrate 에 best.pt·metadata.json 필요: {run_dir}")
    backbone, img_size = model_spec(weights)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    crops_dir = Path(cfg["crops"])
    sp = select_splits(read_crops(crops_dir))
    check_splits(sp, keys=("val", "cal_a", "cal_b"))
    workers = resolve_workers(cfg)
    model = build_model(pretrained=False, backbone=backbone).to(device)
    model.load_state_dict(torch.load(weights, map_location=device, weights_only=True))

    def logits(rows):
        dl = DataLoader(_dataset(rows, crops_dir, False, None, int(cfg.get("seed", 0)), img_size=img_size),
                        batch_size=int(cfg.get("batch", 64)), shuffle=False,
                        **loader_kwargs(workers, int(cfg.get("seed", 0))))
        return _predict_logits(model, dl, device)

    (za, ya), (zb, yb), (zv, yv) = logits(sp["cal_a"]), logits(sp["cal_b"]), logits(sp["val"])
    cal = calibrate(za, ya, zb, yb, zv, yv, sp, cfg)

    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta.update({"platt": {"a": float(cal["platt"][0]), "b": float(cal["platt"][1])}, "tau": float(cal["tau"]),
                 "tau_policy": cal["tau_policy"]})
    meta_path.write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    vdi = _write_vdi(cal, run_dir / "vdi.yaml", Path(cfg.get("vdi_out", "training/configs/vdi.yaml")))

    out = Path(cfg.get("eval_out", "training/eval_history/v0.2.0-stage2.json"))
    base = {}
    if out.exists():
        prev = json.loads(out.read_text(encoding="utf-8"))
        if Path(str(prev.get("weights", "")).replace("\\", "/")).parent.name == run_dir.name:
            base = prev  # 같은 run 의 학습 리포트 → history/best_epoch 등 보존
    counts = {k: {"n": len(v), "pos": sum(int(r["label"]) for r in v)} for k, v in sp.items()}
    report = {**base, "version": "v0.2.0-stage2", "model": backbone, "img_size": img_size, **cal["report"],
              "counts": counts, "weights": str(weights), "vdi": str(vdi), "recalibrated_from": str(run_dir)}
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    logger.info(f"recalibrated τ={cal['tau']:.4f} ({cal['tau_policy']}, cal-A FPR={cal['cal_a_fpr_at_tau']:.4f}) "
                f"cal-B TPR={cal['tpr']:.3f} FPR={cal['fpr']:.4f} → {out}")
    return report


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser()
    p.add_argument("--config", type=Path, default=Path("training/configs/stage2.yaml"),
                   help="training/configs/stage2.yaml (기본)")
    p.add_argument("--degrade", default=None, help="none | <lo_px 정수> (폰 열화 증강)")
    p.add_argument("--set", nargs="*", default=[], metavar="KEY=VALUE", help="임의 config 키 오버라이드")
    p.add_argument("--recalibrate", type=Path, default=None, metavar="RUN_DIR",
                   help="학습 없이 RUN_DIR/best.pt 로 Platt·τ 재선택 (vdi.yaml·eval JSON·metadata.json 갱신, ONNX 불변)")
    return p


def main(argv: list[str] | None = None):
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    a = build_parser().parse_args(argv)
    cfg = yaml.safe_load(a.config.read_text(encoding="utf-8"))
    cfg = apply_overrides(cfg, a.set)
    if a.degrade is not None:
        cfg["degrade"] = a.degrade
    parse_tau_policy(cfg.get("tau_policy"))  # 조기 검증
    parse_fpr_cap(cfg.get("fpr_cap"))
    resolve_workers(cfg)
    parse_amp(cfg.get("amp"))  # --set amp=true 는 apply_overrides 가 bool 로, 문자열 "1"/"0" 등도 허용
    cfg["config"] = str(a.config)
    if a.recalibrate is not None:
        return recalibrate(a.recalibrate, cfg)
    parse_degrade(cfg.get("degrade"))
    parse_select_metric(cfg.get("select_metric"))
    parse_swa_epochs(cfg.get("swa_epochs"), cfg.get("epochs"))
    parse_backbone(cfg.get("backbone"))
    return train(cfg)


if __name__ == "__main__":
    main()
