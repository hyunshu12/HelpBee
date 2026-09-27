"""two-stage 추론 엔진 (스펙 v2.2 §4 ②~⑦, §8).

  ② Stage-1: YOLO11s 1-class `bee` ONNX, 입력 1024 letterbox, conf 0.15, NMS iou 0.7(ultralytics
     predict 기본 — 학습 크롭 생성 PRED_KW 와 동일), max_det 1500. ≥8MP 면 항상 2×2 타일(10% 겹침),
     타일 병합은 IoMin NMS(0.7).
  ③ 박스 → 원본 좌표 → 원본 크롭(여백 10%) → 종횡비 유지 검정 패딩 → img_size(metadata, v0.2.0=320).
     규칙 = app/services/crops.crop_pad (학습 make_crops.crop_pad_224 와 단일 소스).
  ④ Stage-2: ResNet-18 ONNX(`image`→`logit`,`featmap`), 64개 청크, p = sigmoid(a·logit + b)(Platt),
     infested = p > τ (vdi.yaml).
  ⑦ evidence: 감염 판정 상위 k=6 에 한해 닫힌 형식 CAM = ReLU(Σ_c fc_w[c]·featmap[c]) → [0,1].

소프트 크롭 상한 1,500(초과 시 랜덤 샘플 → sampled=True). 이미지 배열은 **RGB** uint8.
집계(VDI/tier)는 오케스트레이터가 vdi.aggregate 로 한다 — 엔진은 벌 단위 판정까지만.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Protocol

import numpy as np
from PIL import Image

from app.services.crops import crop_pad, normalize_box
from app.services.vdi import VdiConfig, load_vdi_config
from app.services.yolo_engine import _nms, _xywh_to_xyxy, letterbox

STAGE1_IMGSZ = 1024
STAGE1_CONF = 0.15
STAGE1_IOU = 0.7
MAX_DET = 1500
CHUNK = 64
CROP_CAP = 1500
CROP_MARGIN = 0.10
TOPK_EVIDENCE = 6
TILE_MIN_PIXELS = 8_000_000  # ≥8MP 면 항상 2×2 타일 (스펙 §4 ②)
TILE_OVERLAP = 0.10
IOMIN_THR = 0.7
IMAGENET_MEAN = np.array([0.485, 0.456, 0.406], np.float32)
IMAGENET_STD = np.array([0.229, 0.224, 0.225], np.float32)
BUNDLE_FILES = ("stage1.onnx", "stage2.onnx", "vdi.yaml", "metadata.json")

Box = tuple[float, float, float, float]


class BudgetExceeded(RuntimeError):
    """AI 내부 시간 예산 초과 — 오케스트레이터가 graceful/폴백으로 흡수."""


@dataclass
class BeeDet:
    box: Box
    p_infested: float
    infested: bool


@dataclass
class TwoStageResult:
    bees: list[BeeDet]
    bee_total: int
    bee_infested: int
    sampled: bool
    evidence: list[dict] = field(default_factory=list)
    model_versions: dict = field(default_factory=dict)
    stage_latency_ms: dict = field(default_factory=dict)


class TwoStageEngine(Protocol):
    model_versions: dict

    def analyze(self, image: np.ndarray, cfg: VdiConfig, *, deadline: float | None = None) -> TwoStageResult: ...


# ── 순수 로직 ───────────────────────────────────────────────────────────────
def chunk_indices(n: int, chunk: int) -> list[range]:
    return [range(i, min(i + chunk, n)) for i in range(0, n, chunk)]


def cap_crops(boxes: list, cap: int = CROP_CAP, rng=None) -> tuple[list, bool]:
    """cap 초과 시 랜덤 비복원 샘플(원래 순서 유지) → (boxes, sampled)."""
    if len(boxes) <= cap:
        return boxes, False
    rng = rng if rng is not None else np.random.default_rng(0)
    idx = np.sort(rng.choice(len(boxes), cap, replace=False))
    return [boxes[i] for i in idx], True


def needs_tiling(hw: tuple[int, int]) -> bool:
    return hw[0] * hw[1] >= TILE_MIN_PIXELS


def letterbox_tiles(hw: tuple[int, int], n: int = 2, overlap: float = TILE_OVERLAP) -> list[tuple[int, int, int, int]]:
    """n×n 타일 (x, y, w, h). 각 타일은 1/n 크기에 overlap 만큼 확장, 마지막 타일은 끝에 맞춘다."""
    h, w = hw
    tw, th = min(w, int(w / n * (1 + overlap))), min(h, int(h / n * (1 + overlap)))
    out = []
    for j in range(n):
        for i in range(n):
            x = max(0, min(int(i * w / n), w - tw))
            y = max(0, min(int(j * h / n), h - th))
            out.append((x, y, tw, th))
    return out


def iomin_nms(boxes: np.ndarray, scores: np.ndarray, thr: float = IOMIN_THR) -> list[int]:
    """타일 경계 중복 병합용 NMS: intersection / min(area) ≥ thr 이면 억제."""
    boxes = np.asarray(boxes, np.float32)
    order = np.asarray(scores).argsort()[::-1]
    areas = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
    keep: list[int] = []
    while order.size:
        i = int(order[0])
        keep.append(i)
        rest = order[1:]
        xx1 = np.maximum(boxes[i, 0], boxes[rest, 0])
        yy1 = np.maximum(boxes[i, 1], boxes[rest, 1])
        xx2 = np.minimum(boxes[i, 2], boxes[rest, 2])
        yy2 = np.minimum(boxes[i, 3], boxes[rest, 3])
        inter = np.clip(xx2 - xx1, 0, None) * np.clip(yy2 - yy1, 0, None)
        iomin = inter / (np.minimum(areas[i], areas[rest]) + 1e-9)
        order = rest[iomin < thr]
    return keep


def decode_boxes(output: np.ndarray, *, conf: float = STAGE1_CONF, iou: float = STAGE1_IOU,
                 max_det: int = MAX_DET) -> tuple[np.ndarray, np.ndarray]:
    """1-class raw ONNX 출력 [1, 5, N] → (xyxy[K,4] letterbox 좌표, score[K]) score 내림차순.

    yolo_engine.decode_detections 와 같은 정규화(channels-first 허용) + NMS, 박스를 보존한다.
    """
    arr = np.asarray(output, dtype=np.float32)
    if arr.ndim == 3:
        arr = arr[0]
    if arr.shape[0] == 5 and arr.shape[1] != 5:
        arr = arr.T
    if arr.size == 0:
        return np.zeros((0, 4), np.float32), np.zeros(0, np.float32)
    score = arr[:, 4]
    mask = score >= conf
    if not mask.any():
        return np.zeros((0, 4), np.float32), np.zeros(0, np.float32)
    boxes = _xywh_to_xyxy(arr[mask, :4])
    score = score[mask]
    keep = _nms(boxes, score, iou)[:max_det]  # _nms 는 score 내림차순으로 보존
    return boxes[keep], score[keep]


def _detect_once(sess1, img: np.ndarray, imgsz: int, conf: float, max_det: int) -> tuple[np.ndarray, np.ndarray]:
    h, w = img.shape[:2]
    inp = letterbox(Image.fromarray(img), size=imgsz)
    out = sess1.run(None, {sess1.get_inputs()[0].name: inp})[0]
    boxes, scores = decode_boxes(out, conf=conf, max_det=max_det)
    if len(boxes):
        scale = min(imgsz / w, imgsz / h)
        nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
        px, py = (imgsz - nw) // 2, (imgsz - nh) // 2
        boxes = boxes.copy()
        boxes[:, [0, 2]] = np.clip((boxes[:, [0, 2]] - px) / scale, 0, w)
        boxes[:, [1, 3]] = np.clip((boxes[:, [1, 3]] - py) / scale, 0, h)
    return boxes, scores


def detect_bees(sess1, img: np.ndarray, imgsz: int = STAGE1_IMGSZ, conf: float = STAGE1_CONF,
                max_det: int = MAX_DET, tile: bool = False) -> list[Box]:
    """Stage-1 → 원본 좌표 xyxy 박스 목록(score 내림차순, 퇴화 박스 제외)."""
    if not tile:
        boxes, scores = _detect_once(sess1, img, imgsz, conf, max_det)
    else:
        all_b, all_s = [], []
        for x, y, tw, th in letterbox_tiles(img.shape[:2]):
            b, s = _detect_once(sess1, np.ascontiguousarray(img[y:y + th, x:x + tw]), imgsz, conf, max_det)
            if len(b):
                all_b.append(b + np.array([x, y, x, y], np.float32))
                all_s.append(s)
        if not all_b:
            return []
        boxes, scores = np.concatenate(all_b), np.concatenate(all_s)
        keep = iomin_nms(boxes, scores, IOMIN_THR)[:max_det]
        boxes, scores = boxes[keep], scores[keep]
    ok = (boxes[:, 2] - boxes[:, 0] >= 1) & (boxes[:, 3] - boxes[:, 1] >= 1) if len(boxes) else []
    return [tuple(float(v) for v in b) for b in boxes[ok]] if len(boxes) else []


def normalize_crops(crops: np.ndarray) -> np.ndarray:
    """uint8 [N,H,W,3] RGB → float32 [N,3,H,W] ImageNet 정규화 (train_stage2 와 동일)."""
    x = (crops.astype(np.float32) / 255.0 - IMAGENET_MEAN) / IMAGENET_STD
    return np.ascontiguousarray(x.transpose(0, 3, 1, 2), dtype=np.float32)


def classify_crops(sess2, crops: np.ndarray, chunk: int = CHUNK,
                   deadline: float | None = None) -> tuple[np.ndarray, np.ndarray]:
    """Stage-2 청크 추론 → (logits[N], featmaps[N,C,h,w]). deadline(monotonic) 초과 시 BudgetExceeded."""
    logits, feats = [], []
    for idx in chunk_indices(len(crops), chunk):
        if deadline is not None and time.monotonic() > deadline:
            raise BudgetExceeded("stage2 budget exceeded")
        lo, fm = sess2.run(["logit", "featmap"], {"image": crops[idx.start:idx.stop]})
        logits.append(np.asarray(lo, np.float32).reshape(-1))
        feats.append(np.asarray(fm, np.float32))
    if not logits:
        return np.zeros(0, np.float32), np.zeros((0,), np.float32)
    return np.concatenate(logits), np.concatenate(feats)


def classify_boxes(sess2, image: np.ndarray, boxes: list, *, img_size: int, chunk: int = CHUNK,
                   platt: tuple[float, float] = (1.0, 0.0), topk: int = TOPK_EVIDENCE,
                   deadline: float | None = None) -> tuple[np.ndarray, dict[int, np.ndarray]]:
    """Stage-2 스트리밍: 청크(≤chunk)마다 크롭→정규화→추론. 전체 크롭 텐서를 만들지 않는다.

    1,500 크롭 @320을 한 번에 쌓으면 uint8+float32+transpose 사본으로 요청당 4~6 GB(t3.medium OOM).
    청크 단위면 동시 상주 텐서가 chunk개로 묶인다. featmap은 CAM에 쓰는 **p 상위 topk**만 유지.
    반환: (Platt 보정 p[N], {박스 인덱스: featmap}).
    """
    a, b = platt
    ps: list[np.ndarray] = []
    kept: list[tuple[float, int, np.ndarray]] = []  # (p, idx, featmap) 상위 topk
    for idx in chunk_indices(len(boxes), chunk):
        if deadline is not None and time.monotonic() > deadline:
            raise BudgetExceeded("stage2 budget exceeded")
        batch = normalize_crops(np.stack([crop_pad(image, boxes[i], margin=CROP_MARGIN, size=img_size)[0]
                                          for i in range(idx.start, idx.stop)]))
        lo, fm = sess2.run(["logit", "featmap"], {"image": batch})
        del batch
        logit = np.asarray(lo, np.float32).reshape(-1)
        pc = 1.0 / (1.0 + np.exp(-(a * logit + b)))
        ps.append(pc)
        if topk > 0:
            fm = np.asarray(fm, np.float32)
            for j in np.argsort(-pc, kind="stable")[:topk]:
                kept.append((float(pc[j]), idx.start + int(j), fm[j].copy()))
            kept.sort(key=lambda x: (-x[0], x[1]))
            del kept[topk:]
        del fm
    p = np.concatenate(ps) if ps else np.zeros(0, np.float32)
    return p, {i: f for _, i, f in kept}


def cam_from_featmap(featmap: np.ndarray, fc_w: np.ndarray) -> np.ndarray:
    """닫힌 형식 CAM: ReLU(Σ_c fc_w[c]·featmap[c]) → [0,1] 정규화, featmap 공간 크기 그대로."""
    cam = np.maximum(np.tensordot(np.asarray(fc_w, np.float32), featmap, axes=(0, 0)), 0.0)
    mx = float(cam.max())
    return cam / mx if mx > 0 else cam


def _crop_region(box: Box, hw: tuple[int, int], margin: float = CROP_MARGIN) -> list[int]:
    """crop_pad 와 같은 여백 확장 영역(원본 좌표) — CAM 오버레이 위치 복원용."""
    H, W = hw
    x1, y1, x2, y2 = normalize_box(box)
    w, h = x2 - x1, y2 - y1
    return [max(0, int(x1 - w * margin)), max(0, int(y1 - h * margin)),
            min(W, int(x2 + w * margin)), min(H, int(y2 + h * margin))]


# ── 엔진 ───────────────────────────────────────────────────────────────────
class OnnxTwoStageEngine:
    """two-stage 번들(`two-stage/<ver>/{stage1.onnx,stage2.onnx,vdi.yaml,metadata.json}`) 엔진.

    OnnxYoloEngine._ensure_model 과 같은 패턴: 로컬 캐시 → 없으면 S3 다운로드, 세션은 lazy.
    img_size·feat_channels·fc_weight 는 metadata.json 에서 읽는다(하드코딩 없음).
    """

    def __init__(self, version: str, *, cache_dir: str, s3_bucket: str | None = "helpbee-models",
                 crop_cap: int = CROP_CAP, chunk: int = CHUNK, topk: int = TOPK_EVIDENCE,
                 seed: int = 0) -> None:
        self.version = version
        self._dir = Path(cache_dir) / version
        self._bucket = s3_bucket
        self.crop_cap, self.chunk, self.topk = crop_cap, chunk, topk
        self._seed = seed  # cap 샘플링 rng는 호출마다 생성(Generator는 스레드 비안전 — threadpool 공유 금지)
        self._s1 = self._s2 = None
        self._meta: dict | None = None
        self._vdi_cfg: VdiConfig | None = None
        self._vdi_extras: dict | None = None
        self.model_versions = {"stage1": f"{version}/stage1", "stage2": f"{version}/stage2", "vdi_config": version}
        self.model_version = f"helpbee-two-stage-{version.lstrip('v')}"

    def _fetch(self) -> None:  # pragma: no cover - S3 의존(로컬 캐시 우선)
        missing = [f for f in BUNDLE_FILES if not (self._dir / f).exists()]
        if not missing:
            return
        if not self._bucket:
            raise FileNotFoundError(f"two-stage 번들 없음: {self._dir} ({missing})")
        import boto3  # lazy

        self._dir.mkdir(parents=True, exist_ok=True)
        s3 = boto3.client("s3")
        for f in missing:
            s3.download_file(self._bucket, f"two-stage/{self.version}/{f}", str(self._dir / f))

    def _ensure(self) -> None:
        if self._s1 is not None and self._s2 is not None and self._meta is not None:
            return
        self._fetch()
        import os

        import onnxruntime as ort  # lazy

        os.environ.setdefault("OMP_NUM_THREADS", "1")
        if self._meta is None:
            self._meta = json.loads((self._dir / "metadata.json").read_text(encoding="utf-8"))
        if self._s1 is None:
            self._s1 = ort.InferenceSession(str(self._dir / "stage1.onnx"), providers=["CPUExecutionProvider"])
        if self._s2 is None:
            self._s2 = ort.InferenceSession(str(self._dir / "stage2.onnx"), providers=["CPUExecutionProvider"])

    def _load_vdi(self) -> None:
        if self._vdi_cfg is None:
            self._fetch()
            import yaml

            path = self._dir / "vdi.yaml"
            self._vdi_cfg = load_vdi_config(path)
            self._vdi_extras = yaml.safe_load(path.read_text(encoding="utf-8"))

    def prewarm(self) -> None:
        """번들 다운로드 + ONNX 세션 + vdi.yaml 로드를 미리 수행(FastAPI startup, best-effort)."""
        self._ensure()
        self._load_vdi()

    def vdi_config(self) -> VdiConfig:
        self._load_vdi()
        return self._vdi_cfg  # type: ignore[return-value]

    def vdi_extras(self) -> dict:
        """vdi.yaml 전체(quality 임계·recommendations·capture_floor 등 VdiConfig 외 키)."""
        self._load_vdi()
        return self._vdi_extras or {}

    def analyze(self, image: np.ndarray, cfg: VdiConfig, *, deadline: float | None = None) -> TwoStageResult:
        self._ensure()
        meta = self._meta or {}
        img_size = int(meta.get("img_size", 224))
        fc_w = np.asarray(meta["fc_weight"], np.float32)
        t: dict[str, int] = {}

        t0 = time.monotonic()
        tile = needs_tiling(image.shape[:2])
        boxes = detect_bees(self._s1, image, tile=tile)
        t["stage1"] = int((time.monotonic() - t0) * 1000)
        boxes, sampled = cap_crops(boxes, self.crop_cap, np.random.default_rng(self._seed))
        if not boxes:
            t["stage2"] = 0
            return TwoStageResult([], 0, 0, sampled, [], dict(self.model_versions), t)
        if deadline is not None and time.monotonic() > deadline:
            raise BudgetExceeded("stage1 budget exceeded")

        t1 = time.monotonic()
        a, b = cfg.platt
        p, top_feats = classify_boxes(self._s2, image, boxes, img_size=img_size, chunk=self.chunk,
                                      platt=(a, b), topk=self.topk, deadline=deadline)
        t["stage2"] = int((time.monotonic() - t1) * 1000)

        bees = [BeeDet(bx, float(pi), bool(pi > cfg.tau)) for bx, pi in zip(boxes, p)]
        evidence = []
        # top_feats 는 classify_boxes 가 유지한 p 상위 topk(동률은 낮은 인덱스 우선) — 그 키만 순회.
        for i in sorted(top_feats, key=lambda j: (-float(p[j]), j)):
            if p[i] <= cfg.tau:
                break
            evidence.append({
                "index": int(i),
                "box": list(boxes[i]),
                "crop_region": _crop_region(boxes[i], image.shape[:2]),
                "p_infested": float(p[i]),
                "cam": np.round(cam_from_featmap(top_feats[int(i)], fc_w), 3).tolist(),
            })
        return TwoStageResult(bees, len(bees), sum(x.infested for x in bees), sampled, evidence,
                              dict(self.model_versions), t)
