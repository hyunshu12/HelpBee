"""Gate 0(b) — px/mm 별 Stage-2 recall/specificity 곡선 (촬영 해상도 하한 탐색).

Usage (apps/ai 에서, 학습 박스):
    python -m training.gate0_pxmm --weights runs/stage2/v0.2.0-native/best.pt --crops training/crops \\
        --split golden --targets 22,15,12,9 [--vdi training/configs/vdi.yaml] \\
        [--out training/eval_history/v0.2.0-gate0.json] [--native-px-per-mm 22] [--seed 42]
    (= python tasks.py gate0 --weights ...)

71667 원본은 ≈22 px/mm. 목표 px/mm(target)로 찍힌 폰 사진을 흉내내려고 native 크롭의 긴 변을
round(long · target/native) px 로 고정해 Task 9 의 phone_degrade(lo=hi=tgt)를 적용한다.
판정은 서빙과 동일: p = σ(a·logit + b) (vdi.yaml Platt) → p > τ.

크롭 재구성: crops.csv 의 PNG 는 crop_pad_224 결과(긴 변 224 + 검정 패딩)라 native 픽셀이 없다.
native_w/native_h 로 패딩을 벗겨 native 크기로 되돌린 뒤(native_from_padded) 시뮬레이션한다.
모델 입력이 어차피 img_size(기본 224) 라 긴 변 > img_size 의 디테일은 원래도 모델에 닿지 않는다.
backbone/img_size 는 --backbone/--img-size 또는 weights 옆 metadata.json 에서 읽는다(train_stage2.model_spec).

출력 JSON: {"22": {"recall", "specificity", "n_pos", "n_neg"}, ..., "_meta": {...}}.
붕괴 지점 = recall 이 reference(native) 대비 15%p 이상 떨어지는 첫 target (collapse_target).

torch/cv2 는 함수 안에서 lazy import — 이 모듈은 numpy/yaml 만으로 import 가능.
"""
from __future__ import annotations

import argparse
import json
import logging
from pathlib import Path

import numpy as np

from training.train_stage2 import (DEFAULT_IMG_SIZE, IMAGENET_MEAN, IMAGENET_STD, build_model, model_spec,
                                   phone_degrade, read_crops, sigmoid)

logger = logging.getLogger(__name__)

NATIVE_PX_PER_MM = 22.0  # AI Hub 71667
MIN_TGT_PX = 8  # cv2.resize 0 방지


def scale_for_target(native_px_per_mm: float, target: float) -> float:
    return target / native_px_per_mm


def simulate_px_per_mm(native_crop: np.ndarray, native_px_per_mm: float, target: float, rng,
                       size: int = DEFAULT_IMG_SIZE) -> np.ndarray:
    """native 크롭 → target px/mm 폰 촬영 모사 size×size×3."""
    from training.data.make_crops import crop_pad_224

    h, w = native_crop.shape[:2]
    tgt = max(MIN_TGT_PX, int(round(max(h, w) * scale_for_target(native_px_per_mm, target))))
    padded, _ = crop_pad_224(native_crop, (0, 0, w, h), margin=0.0, size=size)
    return phone_degrade(padded, rng, lo_px=tgt, hi_px=tgt)


def native_from_padded(img224: np.ndarray, native_w: int, native_h: int) -> np.ndarray:
    """crop_pad_224 의 역: 검정 패딩 제거 후 native 크기로 복원."""
    import cv2

    size = img224.shape[0]
    s = size / max(native_w, native_h)
    rw, rh = max(1, int(native_w * s)), max(1, int(native_h * s))
    oy, ox = (size - rh) // 2, (size - rw) // 2
    inner = img224[oy:oy + rh, ox:ox + rw]
    return cv2.resize(inner, (native_w, native_h), interpolation=cv2.INTER_LINEAR)


def rates_at_tau(logits, y, tau: float, platt: tuple[float, float]) -> dict:
    """서빙과 동일하게 Platt → τ 비교. 한 클래스가 없으면 해당 지표는 None."""
    p = sigmoid(platt[0] * np.asarray(logits, np.float64) + platt[1])
    y = np.asarray(y).astype(int)
    pred = p > tau
    pos, neg = y == 1, y == 0
    return {
        "recall": float(pred[pos].mean()) if pos.any() else None,
        "specificity": float((~pred[neg]).mean()) if neg.any() else None,
        "n_pos": int(pos.sum()),
        "n_neg": int(neg.sum()),
    }


def collapse_target(results: dict, reference: str, drop: float = 0.15) -> float | None:
    """reference 대비 recall 이 drop 이상 떨어지는 첫 target(내림차순 순회). 없으면 None."""
    ref = results[reference]["recall"]
    keys = sorted((k for k in results if not k.startswith("_")), key=float, reverse=True)
    for k in keys:
        r = results[k]["recall"]
        if ref is not None and r is not None and ref - r >= drop - 1e-9:
            return float(k)
    return None


def _fmt(t: float) -> str:
    return f"{t:g}"


def evaluate(weights: Path, crops_dir: Path, split: str, targets: list[float], vdi_path: Path,
             native_px_per_mm: float, seed: int, batch: int = 64, backbone: str | None = None,
             img_size: int | None = None) -> dict:
    import cv2
    import torch

    from app.services.vdi import load_vdi_config

    cfg = load_vdi_config(vdi_path)
    rows = [r for r in read_crops(crops_dir) if r["split"] == split]
    if not rows:
        raise SystemExit(f"crops.csv 에 split={split!r} 크롭이 없음: {crops_dir}")
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    backbone, img_size = model_spec(weights, backbone, img_size)
    model = build_model(pretrained=False, backbone=backbone).to(device)
    model.load_state_dict(torch.load(weights, map_location=device, weights_only=True))
    model.eval()

    natives = []
    for r in rows:
        img = cv2.imdecode(np.fromfile(str(crops_dir / r["path"]), np.uint8), cv2.IMREAD_COLOR)
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        natives.append(native_from_padded(img, int(r["native_w"]), int(r["native_h"])))
    y = np.array([int(r["label"]) for r in rows])

    results: dict = {}
    for t in targets:
        rng = np.random.default_rng([seed, int(round(t * 1000))])
        zs = []
        with torch.no_grad():
            for i in range(0, len(natives), batch):
                xs = [simulate_px_per_mm(n, native_px_per_mm, t, rng, img_size) for n in natives[i:i + batch]]
                x = (np.stack(xs).astype(np.float32) / 255 - IMAGENET_MEAN) / IMAGENET_STD
                z, _ = model(torch.from_numpy(x.transpose(0, 3, 1, 2).copy()).to(device))
                zs.append(z.float().cpu().numpy())
        results[_fmt(t)] = rates_at_tau(np.concatenate(zs), y, cfg.tau, cfg.platt)
        logger.info(f"{_fmt(t)} px/mm: {results[_fmt(t)]}")

    ref = _fmt(native_px_per_mm) if _fmt(native_px_per_mm) in results else _fmt(max(targets))
    results["_meta"] = {
        "weights": str(weights), "split": split, "n": len(rows), "native_px_per_mm": native_px_per_mm,
        "tau": cfg.tau, "platt": {"a": cfg.platt[0], "b": cfg.platt[1]}, "seed": seed, "reference": ref,
        "backbone": backbone, "img_size": img_size,
        "collapse_px_per_mm": collapse_target(results, ref),
    }
    return results


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    p = argparse.ArgumentParser()
    p.add_argument("--weights", type=Path, required=True, help="Stage-2 best.pt (state_dict)")
    p.add_argument("--crops", type=Path, required=True, help="make_crops 산출 디렉터리 (crops.csv 포함)")
    p.add_argument("--split", default="golden")
    p.add_argument("--targets", default="22,15,12,9", help="쉼표 구분 px/mm")
    p.add_argument("--vdi", type=Path, default=Path("training/configs/vdi.yaml"))
    p.add_argument("--out", type=Path, default=Path("training/eval_history/v0.2.0-gate0.json"))
    p.add_argument("--native-px-per-mm", dest="native_px_per_mm", type=float, default=NATIVE_PX_PER_MM)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--backbone", default=None, help="기본: weights 옆 metadata.json → shufflenet_v2_x1_0")
    p.add_argument("--img-size", dest="img_size", type=int, default=None, help="기본: metadata.json → 224")
    a = p.parse_args()
    targets = [float(t) for t in a.targets.split(",") if t.strip()]
    res = evaluate(a.weights, a.crops, a.split, targets, a.vdi, a.native_px_per_mm, a.seed,
                   backbone=a.backbone, img_size=a.img_size)
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(res, ensure_ascii=False, indent=2), encoding="utf-8")
    logger.info(f"collapse={res['_meta']['collapse_px_per_mm']} → {a.out}")


if __name__ == "__main__":
    main()
