"""Stage-2 분리 지표 · 지름길 프로브 (스펙 §7 Stage-2 게이트).

Usage (apps/ai 에서, 학습 박스):
    python -m training.eval_stage2 --weights runs/stage2/v0.2.0-native/best.pt --crops training/crops \\
        --split golden [--vdi training/configs/vdi.yaml] [--out training/eval_history/v0.2.0-stage2.json]
    (= python tasks.py eval-stage2 --weights ...)

--split golden 은 crops.csv 의 split=="golden" 전체(디듀프 후 golden colony 이미지 전부) — Stage-1
eval.py·단일 스테이지 베이스라인이 쓰는 golden.json 300장보다 넓다(모집단 다름, 비교 시 명시).

판정은 서빙과 동일: p = σ(a·logit + b) (vdi.yaml Platt) → p > τ.

출력 JSON (스키마 고정):
    {"overall": {recall, specificity, auroc, ece},
     "by_source": {...}, "by_device": {...}, "by_colony": {...},   # 그룹별 {recall, specificity, n_pos, n_neg}
     "size_only_auroc": float,     # [native_w, native_h, w/h] 만의 5-fold 로지스틱 AUROC — 게이트 < 0.7
     "source_probe_acc": float,    # penultimate 임베딩 → source 5-fold LogisticRegression 정확도
     "lodo": {device: {auroc, n}}} # leave-one-device-out 선형 프로브 (임베딩 고정)

LODO 는 백본 재학습이 아니라 **동결 임베딩 위 선형 프로브**다 — 한 기기를 빼고 학습한 로지스틱이 그 기기에서
얼마나 분리되는지로 기기 지름길 의존을 본다 (기기별 전체 재학습은 비용상 범위 밖).

torch/cv2 는 evaluate() 안에서 lazy import — 이 모듈은 numpy/pandas/sklearn 만으로 import 가능.
"""
from __future__ import annotations

import argparse
import json
import logging
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import StratifiedKFold, cross_val_predict
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

from training.data.make_split_manifest import source_group
from training.train_stage2 import ece, read_crops, sigmoid

logger = logging.getLogger(__name__)

N_FOLDS = 5


def _rates(pred: np.ndarray, y: np.ndarray) -> dict:
    pos, neg = y == 1, y == 0
    return {
        "recall": float(pred[pos].mean()) if pos.any() else None,
        "specificity": float((~pred[neg]).mean()) if neg.any() else None,
        "n_pos": int(pos.sum()),
        "n_neg": int(neg.sum()),
    }


def overall_metrics(p, y, tau: float) -> dict:
    p = np.asarray(p, np.float64)
    y = np.asarray(y).astype(int)
    r = _rates(p > tau, y)
    both = 0 < y.sum() < len(y)
    return {
        "recall": r["recall"],
        "specificity": r["specificity"],
        "auroc": float(roc_auc_score(y, p)) if both else None,
        "ece": ece(p, y, bins=15),
    }


def by_group(df: pd.DataFrame, key: str, p, y, tau: float) -> dict:
    """그룹(source/device/colony)별 recall·specificity @τ. 한 클래스가 없으면 그 지표는 None."""
    p = np.asarray(p, np.float64)
    y = np.asarray(y).astype(int)
    keys = df[key].astype(str).to_numpy()
    return {g: _rates(p[keys == g] > tau, y[keys == g]) for g in sorted(set(keys))}


def _cv(y, seed: int) -> StratifiedKFold:
    n_splits = min(N_FOLDS, int(np.bincount(np.unique(y, return_inverse=True)[1]).min()))
    return StratifiedKFold(n_splits=max(2, n_splits), shuffle=True, random_state=seed)


def size_only_auroc(native_w, native_h, y, seed: int = 0) -> float:
    """크기·종횡비만으로 감염을 맞히는 로지스틱의 out-of-fold AUROC — 높으면 크기 지름길 위험."""
    w = np.asarray(native_w, np.float64)
    h = np.asarray(native_h, np.float64)
    y = np.asarray(y).astype(int)
    x = np.column_stack([w, h, w / np.maximum(h, 1e-9)])
    clf = make_pipeline(StandardScaler(), LogisticRegression(max_iter=1000))
    prob = cross_val_predict(clf, x, y, cv=_cv(y, seed), method="predict_proba")[:, 1]
    return float(roc_auc_score(y, prob))


def source_probe_acc(emb, source, seed: int = 0) -> float:
    """임베딩 → source 선형 프로브 5-fold 정확도 — 높을수록 임베딩이 촬영 소스를 담고 있음."""
    emb = np.asarray(emb, np.float64)
    src = np.asarray(source).astype(str)
    if len(set(src)) < 2:
        return 1.0
    clf = make_pipeline(StandardScaler(), LogisticRegression(max_iter=2000))
    pred = cross_val_predict(clf, emb, src, cv=_cv(src, seed))
    return float((pred == src).mean())


def lodo_probe(emb, y, device) -> dict:
    """leave-one-device-out: 나머지 기기로 학습한 선형 프로브의 held-out 기기 AUROC."""
    emb = np.asarray(emb, np.float64)
    y = np.asarray(y).astype(int)
    dev = np.asarray(device).astype(str)
    out = {}
    for d in sorted(set(dev)):
        te, tr = dev == d, dev != d
        if len(set(y[tr])) < 2 or len(set(y[te])) < 2:
            out[d] = {"auroc": None, "n": int(te.sum())}
            continue
        clf = make_pipeline(StandardScaler(), LogisticRegression(max_iter=2000)).fit(emb[tr], y[tr])
        out[d] = {"auroc": float(roc_auc_score(y[te], clf.predict_proba(emb[te])[:, 1])), "n": int(te.sum())}
    return out


def build_report(df: pd.DataFrame, logits, emb, tau: float, platt: tuple[float, float]) -> dict:
    """df: crops.csv 행(source/device/colony/native_w/native_h/label). logits/emb 는 행 순서 일치."""
    p = sigmoid(platt[0] * np.asarray(logits, np.float64) + platt[1])
    y = df["label"].astype(int).to_numpy()
    df = df.assign(source=df["source"].map(source_group))  # 71667-val/71667-train → 71667 한 그룹
    return {
        "overall": overall_metrics(p, y, tau),
        "by_source": by_group(df, "source", p, y, tau),
        "by_device": by_group(df, "device", p, y, tau),
        "by_colony": by_group(df, "colony", p, y, tau),
        "size_only_auroc": size_only_auroc(df["native_w"].astype(float), df["native_h"].astype(float), y),
        "source_probe_acc": source_probe_acc(emb, df["source"]),
        "lodo": lodo_probe(emb, y, df["device"]),
    }


def predict(weights: Path, crops_dir: Path, rows: list[dict], batch: int = 64) -> tuple[np.ndarray, np.ndarray]:
    """best.pt → (logits (N,), penultimate 임베딩 (N,1024) = featmap 공간 평균). gate0_pxmm 과 같은 로드 방식."""
    import torch
    from torch.utils.data import DataLoader

    from training.train_stage2 import _dataset, build_model

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = build_model(pretrained=False).to(device)
    model.load_state_dict(torch.load(weights, map_location=device, weights_only=True))
    model.eval()
    loader = DataLoader(_dataset(rows, crops_dir, train=False, degrade_lo=None, seed=0), batch_size=batch)
    zs, es = [], []
    with torch.no_grad():
        for x, _ in loader:
            z, f = model(x.to(device))
            zs.append(z.float().cpu().numpy())
            es.append(f.mean((2, 3)).float().cpu().numpy())
    return np.concatenate(zs), np.concatenate(es)


def evaluate(weights: Path, crops_dir: Path, split: str, vdi_path: Path) -> dict:
    from app.services.vdi import load_vdi_config

    cfg = load_vdi_config(vdi_path)
    rows = [r for r in read_crops(crops_dir) if r["split"] == split]
    if not rows:
        raise SystemExit(f"crops.csv 에 split={split!r} 크롭이 없음: {crops_dir}")
    logits, emb = predict(weights, Path(crops_dir), rows)
    return build_report(pd.DataFrame(rows), logits, emb, cfg.tau, cfg.platt)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    p = argparse.ArgumentParser()
    p.add_argument("--weights", type=Path, required=True, help="Stage-2 best.pt (state_dict)")
    p.add_argument("--crops", type=Path, required=True, help="make_crops 산출 디렉터리 (crops.csv 포함)")
    p.add_argument("--split", default="golden")
    p.add_argument("--vdi", type=Path, default=Path("training/configs/vdi.yaml"))
    p.add_argument("--out", type=Path, default=Path("training/eval_history/v0.2.0-stage2.json"))
    a = p.parse_args()
    res = evaluate(a.weights, a.crops, a.split, a.vdi)
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(res, ensure_ascii=False, indent=2), encoding="utf-8")
    logger.info(f"overall={res['overall']} size_only_auroc={res['size_only_auroc']:.3f} → {a.out}")


if __name__ == "__main__":
    main()
