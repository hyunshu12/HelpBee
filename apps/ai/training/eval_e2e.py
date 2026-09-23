"""합성 e2e — 의사-프레임 tier 일치율 vs 사소 베이스라인, 단일 스테이지 YOLO 베이스라인 (스펙 §7 e2e 게이트).

Usage (apps/ai 에서, 학습 박스):
    python -m training.eval_e2e --onnx runs/stage2/v0.2.0-native/stage2.onnx --crops training/crops \\
        [--split golden] [--vdi training/configs/vdi.yaml] [--targets 0,2,5,12,20] [--n-bees 300] \\
        [--n-frames 40] [--seed 42] \\
        [--baseline-weights training/runs/yolo/v0.2.0-baseline-single/weights/best.pt \\
         --baseline-labels <aihub_to_yolo --mapping single2 --manifest 산출>/labels/all \\
         --golden training/golden.json --imgsz 1024] \\
        [--out training/eval_history/v0.2.0-e2e.json]
    (= python tasks.py eval-e2e --onnx ...)

⚠️ golden 모집단 차이: 크롭은 split=="golden" **전체**(디듀프 후 golden colony 이미지 전부)에서 오고,
단일 스테이지 베이스라인·Stage-1 eval.py 는 golden.json 300장(응애 100 + 정상 200)만 쓴다 — 두 수치를
나란히 놓을 때 모집단이 다르다는 점을 표에 적을 것.

의사-프레임: golden 크롭에서 target% 양성이 되도록 n_bees 개를 복원추출해 한 "프레임"으로 본다
(Stage-1 은 완벽하다고 가정 → Stage-2 + VDI 집계만의 e2e). 각 크롭에 Stage-2(ONNX)를 돌려
p = σ(a·logit + b) > τ 개수 k 를 세고 aggregate([(k, n)], cfg) 로 tier 를 낸다.
참 tier 는 참 카운트를 같은 aggregate/display/tier 경로로 계산하되 **Rogan–Gladen 보정은 끈다**
(보정은 분류기 오차를 되돌리는 것 — 참 카운트에 적용하면 진실이 왜곡된다).

단일 스테이지 베이스라인 (baseline_single.yaml, 2-class bee_normal/bee_varroa): golden 이미지에서
bee_varroa 탐지 수 / 전체 벌 탐지 수를 raw 로 aggregate(보정 없음)에 넣어 같은 지표를 낸다.
참값은 single2 라벨(성충 정상=0, 성충 응애=1) 카운트.

출력 JSON (스키마 고정):
    {"tier_confusion": {true: {pred: n}}, "tier_agreement": float, "trivial_all_low": float,
     "healthy_frames_under_3_pct": float, "single_stage_baseline": {...} | null,
     "vdi_mae": float, "vdi_mae_by_target": {"<target>": float}}   # 스펙 §7 의사-프레임 VDI MAE

onnxruntime/cv2/ultralytics 는 함수 안에서 lazy import — 이 모듈은 numpy/pandas/yaml/scipy 만으로 import 가능.
"""
from __future__ import annotations

import argparse
import dataclasses
import json
import logging
from collections import Counter
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

from app.services.vdi import VdiConfig, aggregate
from training.data.make_split_manifest import is_71667
from training.train_stage2 import sigmoid

logger = logging.getLogger(__name__)

TIERS = ("low", "elevated", "high")
SINGLE2_NAMES = ["bee_normal", "bee_varroa"]


def frame_crops(rows: list[dict], split: str) -> pd.DataFrame:
    """의사-프레임 재료: split 이 일치하는 **71667** 크롭만 (manifest 태그 `71667-val` 등 접두 매칭).
    외부 소스(VarroaDataset/EV2)는 해상도·촬영 조건이 달라 한 프레임에 섞지 않는다."""
    df = pd.DataFrame([r for r in rows if r["split"] == split and is_71667(r["source"])])
    if not df.empty:
        df["label"] = df["label"].astype(int)
    return df


def build_pseudo_frames(df: pd.DataFrame, targets=(0, 2, 5, 12, 20), n_bees=300, n_frames=40, seed=42) -> list[dict]:
    """target% 양성 의사-프레임. 양성/음성 크롭을 각각 복원추출 (라벨은 paths 와 같은 순서).

    단순화: 스펙 §5.1 '층화 부트스트랩' 과 달리 colony 층화 없이 양성·음성 풀 전체에서 뽑는다
    (golden colony 가 3~몇 개뿐이라 층화 이득이 작음). colony 편중은 eval_stage2 by_colony 로 본다."""
    rng = np.random.default_rng(seed)
    pos = df[df.label == 1].path.to_numpy()
    neg = df[df.label == 0].path.to_numpy()
    if any(t > 0 for t in targets) and len(pos) == 0:
        raise ValueError("의사-프레임: 양성 크롭 0개 — target>0 프레임을 만들 수 없음 (crops.csv golden 양성 확인)")
    if any(t < 100 for t in targets) and len(neg) == 0:
        raise ValueError("의사-프레임: 음성 크롭 0개 (crops.csv golden 음성 확인)")
    out = []
    for t in targets:
        k = int(round(t * n_bees / 100))
        for _ in range(n_frames):
            ps = [str(p) for p in rng.choice(pos, k, replace=True)] if k else []
            ns = [str(p) for p in rng.choice(neg, n_bees - k, replace=True)]
            out.append({"target": t, "paths": ps + ns, "labels": [1] * k + [0] * (n_bees - k)})
    return out


def tier_agreement(truth, pred) -> float:
    return float(np.mean([a == b for a, b in zip(truth, pred)]))


def trivial_baseline(truth) -> float:
    """사소 베이스라인: 모든 프레임을 'low' 로 답했을 때의 일치율."""
    return float(np.mean([t == "low" for t in truth]))


def _uncorrected(cfg: VdiConfig) -> VdiConfig:
    return dataclasses.replace(cfg, corrected=False)


def true_tier(k: int, n: int, cfg: VdiConfig) -> str:
    """참 카운트의 tier — 예측과 같은 display/tier 경로, Rogan–Gladen 보정 없음."""
    return aggregate([(k, n)], _uncorrected(cfg))["tier"]


def tier_confusion(truth, pred, tiers=TIERS) -> dict:
    labels = list(tiers) + sorted((set(truth) | set(pred)) - set(tiers))
    c = Counter(zip(truth, pred))
    return {t: {p: int(c[(t, p)]) for p in labels} for t in labels}


def frame_tiers(frames: list[dict], logits: dict, cfg: VdiConfig) -> list[dict]:
    """frames × {path: Stage-2 logit} → 프레임별 예측/참 tier. 판정은 서빙과 동일 (Platt → p > τ)."""
    a, b = cfg.platt
    rows = []
    for f in frames:
        z = np.array([logits[p] for p in f["paths"]], np.float64)
        k_pred = int((sigmoid(a * z + b) > cfg.tau).sum())
        n, k_true = len(f["paths"]), int(sum(f["labels"]))
        agg = aggregate([(k_pred, n)], cfg)
        rows.append({"target": f["target"], "n": n, "k_true": k_true, "k_pred": k_pred, "vdi": agg["vdi"],
                     "pred_tier": agg["tier"], "true_tier": true_tier(k_true, n, cfg)})
    return rows


def summarize(rows: list[dict]) -> dict:
    truth = [r["true_tier"] for r in rows]
    pred = [r["pred_tier"] for r in rows]
    healthy = [r["vdi"] < 3 for r in rows if r["k_true"] == 0]
    return {
        "tier_confusion": tier_confusion(truth, pred),
        "tier_agreement": tier_agreement(truth, pred),
        "trivial_all_low": trivial_baseline(truth),
        "healthy_frames_under_3_pct": float(np.mean(healthy)) if healthy else None,
    }


def vdi_mae(rows: list[dict]) -> dict:
    """의사-프레임 VDI MAE: |앱이 보여줄 vdi(aggregate, 보정 포함) − 참 raw %(k_true/n·100)| 평균, 전체 + target별."""
    err = [(r["target"], abs(r["vdi"] - r["k_true"] / r["n"] * 100)) for r in rows]
    by_t: dict[str, list[float]] = {}
    for t, e in err:
        by_t.setdefault(f"{float(t):g}", []).append(e)
    return {
        "vdi_mae": float(np.mean([e for _, e in err])) if err else None,
        "vdi_mae_by_target": {t: float(np.mean(v)) for t, v in by_t.items()},
    }


def make_single2_data_yaml(src: Path, out: Path) -> Path:
    """make_fold_lists 산출 yaml(nc=1, names=[bee]) → 2-class(bee_normal/bee_varroa) 판.

    리스트·label_root 는 그대로 쓰고 nc/names 만 바꾼다. label_root 는 --mapping single2 변환 산출이어야 한다.
    """
    d = yaml.safe_load(Path(src).read_text(encoding="utf-8"))
    d.update(nc=len(SINGLE2_NAMES), names=list(SINGLE2_NAMES))
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(yaml.safe_dump(d, allow_unicode=True, sort_keys=False), encoding="utf-8")
    return out


# ── 학습 박스 실행부 ──────────────────────────────────────────────────────────
def onnx_logits(onnx_path: Path, crops_dir: Path, paths: list[str], batch: int = 64) -> dict:
    """고유 크롭 경로별 Stage-2 logit (ONNX 출력 'logit'). 전처리는 train_stage2._dataset 과 동일."""
    import cv2
    import onnxruntime as ort

    from training.train_stage2 import IMAGENET_MEAN, IMAGENET_STD

    sess = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    uniq = sorted(set(paths))
    out: dict = {}
    for i in range(0, len(uniq), batch):
        xs = []
        for p in uniq[i:i + batch]:
            img = cv2.imdecode(np.fromfile(str(Path(crops_dir) / p), np.uint8), cv2.IMREAD_COLOR)
            img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            if img.shape[:2] != (224, 224):
                img = cv2.resize(img, (224, 224), interpolation=cv2.INTER_LINEAR)
            xs.append(((img.astype(np.float32) / 255 - IMAGENET_MEAN) / IMAGENET_STD).transpose(2, 0, 1))
        (z,) = sess.run(["logit"], {"image": np.stack(xs).astype(np.float32)})
        out.update(zip(uniq[i:i + batch], (float(v) for v in np.asarray(z).reshape(-1))))
    return out


def single_stage_baseline(weights: Path, label_root: Path, golden: Path, cfg: VdiConfig, imgsz: int,
                          conf: float) -> dict:
    from ultralytics import YOLO  # type: ignore

    from training.data.yolo_list_dataset import label_path_for

    g = json.loads(Path(golden).read_text(encoding="utf-8"))
    images = [*g.get("varroa", []), *g.get("normal", [])]
    model = YOLO(str(weights))
    raw_cfg = _uncorrected(cfg)
    rows = []
    for img in images:
        lbl = label_path_for(img, Path(label_root))
        if not lbl.exists():
            logger.warning(f"single2 라벨 없음 — 제외: {lbl}")
            continue
        cls = [int(line.split()[0]) for line in lbl.read_text(encoding="utf-8").splitlines() if line.strip()]
        k_true, n_true = sum(c == 1 for c in cls), len(cls)
        res = model.predict(source=str(img), imgsz=imgsz, conf=conf, max_det=1500, verbose=False)
        pc = res[0].boxes.cls.cpu().numpy().astype(int) if res and res[0].boxes is not None else np.array([], int)
        agg = aggregate([(int((pc == 1).sum()), int(len(pc)))], raw_cfg)
        rows.append({"k_true": k_true, "vdi": agg["vdi"], "pred_tier": agg["tier"],
                     "true_tier": true_tier(k_true, n_true, cfg)})
    return {**summarize(rows), "n_images": len(rows), "weights": str(weights), "imgsz": imgsz, "conf": conf}


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    p = argparse.ArgumentParser()
    p.add_argument("--onnx", type=Path, required=True, help="Stage-2 ONNX (outputs: logit, featmap)")
    p.add_argument("--crops", type=Path, required=True, help="make_crops 산출 디렉터리 (crops.csv 포함)")
    p.add_argument("--split", default="golden")
    p.add_argument("--vdi", type=Path, default=Path("training/configs/vdi.yaml"))
    p.add_argument("--targets", default="0,2,5,12,20", help="쉼표 구분 감염 %%")
    p.add_argument("--n-bees", dest="n_bees", type=int, default=300)
    p.add_argument("--n-frames", dest="n_frames", type=int, default=40)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--baseline-weights", dest="baseline_weights", type=Path, default=None)
    p.add_argument("--baseline-labels", dest="baseline_labels", type=Path, default=None,
                   help="aihub_to_yolo --mapping single2 --manifest 산출 labels/all")
    p.add_argument("--golden", type=Path, default=Path("training/golden.json"))
    p.add_argument("--imgsz", type=int, default=1024)
    p.add_argument("--baseline-conf", dest="baseline_conf", type=float, default=0.25)
    p.add_argument("--out", type=Path, default=Path("training/eval_history/v0.2.0-e2e.json"))
    a = p.parse_args()

    from app.services.vdi import load_vdi_config
    from training.train_stage2 import read_crops

    cfg = load_vdi_config(a.vdi)
    df = frame_crops(read_crops(a.crops), a.split)
    if df.empty:
        raise SystemExit(f"crops.csv 에 split={a.split!r} 71667 크롭이 없음: {a.crops}")
    targets = tuple(float(t) for t in a.targets.split(",") if t.strip())
    frames = build_pseudo_frames(df, targets=targets, n_bees=a.n_bees, n_frames=a.n_frames, seed=a.seed)
    logits = onnx_logits(a.onnx, a.crops, [p for f in frames for p in f["paths"]])
    rows = frame_tiers(frames, logits, cfg)
    res = {**summarize(rows), **vdi_mae(rows)}

    if a.baseline_weights and a.baseline_labels:
        res["single_stage_baseline"] = single_stage_baseline(a.baseline_weights, a.baseline_labels, a.golden, cfg,
                                                             a.imgsz, a.baseline_conf)
    else:
        logger.warning("--baseline-weights/--baseline-labels 미지정 → single_stage_baseline=null")
        res["single_stage_baseline"] = None

    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(res, ensure_ascii=False, indent=2), encoding="utf-8")
    logger.info(f"tier_agreement={res['tier_agreement']:.3f} trivial_all_low={res['trivial_all_low']:.3f} → {a.out}")


if __name__ == "__main__":
    main()
