"""자체 YOLO 추론 엔진.

설계 근거: backend-design §3.3, apps/ai/CLAUDE.md §8, ADR-0001(YOLOv11s@640).

v0.1.0 가중치는 `export(format="onnx", dynamic=True, simplify=True, imgsz=640)`로
산출 — **nms=False** 이므로 ONNX 출력은 NMS 미적용 raw 텐서 `[1, 4+nc, N]`이다
(N=8400 anchors @ 640). 따라서 추론 후처리는 이 모듈이 직접 수행한다:
  1) letterbox 640 전처리 (학습/eval과 동일한 aspect-preserving + 회색 114 패딩)
  2) raw 출력 디코드: 클래스 score argmax → conf 필터(0.25) → per-class NMS(iou 0.5)

단위 검증 대상(모델 불필요, 합성 배열): letterbox / decode_detections /
counts_from_detections — 순수 로직. OnnxYoloEngine._infer 의 onnxruntime 세션
실행만 통합 검증 대상(pragma no cover).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from io import BytesIO
from typing import Protocol, Sequence

import numpy as np
from PIL import Image, ImageOps

CLASS_IDS = (0, 1, 2)  # 0=bee_normal, 1=bee_with_varroa, 2=bee_other_disease
NUM_CLASSES = 3
DEFAULT_IMGSZ = 640
DEFAULT_CONF = 0.25  # metadata.json / configs/yolo.yaml 운영 기본값
DEFAULT_IOU = 0.5
_PAD_VALUE = 114  # ultralytics letterbox 기본 패딩(회색)


@dataclass
class YoloResult:
    class_counts: dict[int, int]
    confidence: float  # 검출 평균 신뢰도 (0~1)
    model_version: str
    raw: dict = field(default_factory=dict)


def counts_from_detections(
    detections: Sequence[dict],
    conf_threshold: float = DEFAULT_CONF,
) -> tuple[dict[int, int], float]:
    """검출 리스트 → (class_counts, mean_confidence).

    detections: [{"class_id": int, "score": float}, ...]
    conf_threshold 미만은 제외, 알 수 없는 class_id는 무시.
    """
    counts = {c: 0 for c in CLASS_IDS}
    kept: list[float] = []
    for det in detections:
        score = float(det["score"])
        cid = int(det["class_id"])
        if score >= conf_threshold and cid in counts:
            counts[cid] += 1
            kept.append(score)
    mean = sum(kept) / len(kept) if kept else 0.0
    return counts, mean


def letterbox(img: Image.Image, size: int = DEFAULT_IMGSZ) -> np.ndarray:
    """PIL 이미지 → letterbox 정규화 텐서 [1, 3, size, size] (float32, 0~1, RGB).

    aspect-preserving 다운/업스케일 후 회색(114) 패딩으로 정사각 캔버스 중앙 배치.
    ultralytics 학습/예측 전처리와 동일 → golden 평가 분포와 일치.
    """
    img = ImageOps.exif_transpose(img).convert("RGB")
    w, h = img.size
    scale = min(size / w, size / h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    resized = img.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (size, size), (_PAD_VALUE, _PAD_VALUE, _PAD_VALUE))
    canvas.paste(resized, ((size - nw) // 2, (size - nh) // 2))
    arr = np.asarray(canvas, dtype=np.float32) / 255.0  # [H,W,3]
    return arr.transpose(2, 0, 1)[None, ...]  # [1,3,H,W]


def _xywh_to_xyxy(boxes: np.ndarray) -> np.ndarray:
    """[N,4] center-xywh → [N,4] xyxy."""
    xy = boxes[:, :2]
    wh = boxes[:, 2:4]
    return np.concatenate([xy - wh / 2.0, xy + wh / 2.0], axis=1)


def _iou(box: np.ndarray, boxes: np.ndarray) -> np.ndarray:
    """box[4] vs boxes[N,4] (xyxy) → IoU[N]."""
    x1 = np.maximum(box[0], boxes[:, 0])
    y1 = np.maximum(box[1], boxes[:, 1])
    x2 = np.minimum(box[2], boxes[:, 2])
    y2 = np.minimum(box[3], boxes[:, 3])
    inter = np.clip(x2 - x1, 0, None) * np.clip(y2 - y1, 0, None)
    a1 = (box[2] - box[0]) * (box[3] - box[1])
    a2 = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
    return inter / (a1 + a2 - inter + 1e-9)


def _nms(boxes: np.ndarray, scores: np.ndarray, iou_threshold: float) -> list[int]:
    """단일 클래스 greedy NMS → 보존 인덱스(입력 배열 기준)."""
    order = scores.argsort()[::-1]
    keep: list[int] = []
    while order.size > 0:
        i = int(order[0])
        keep.append(i)
        if order.size == 1:
            break
        ious = _iou(boxes[i], boxes[order[1:]])
        order = order[1:][ious < iou_threshold]
    return keep


def decode_detections(
    output: np.ndarray,
    *,
    conf_threshold: float = DEFAULT_CONF,
    iou_threshold: float = DEFAULT_IOU,
    num_classes: int = NUM_CLASSES,
) -> list[dict]:
    """raw ONNX 출력 → 검출 리스트 [{"class_id", "score"}].

    출력 형태는 [1, 4+nc, N](channels-first, ultralytics 기본) 또는 [1, N, 4+nc]
    모두 허용. 행=anchor, 열=[cx,cy,w,h, cls0..clsN-1] 로 정규화한 뒤
    클래스 argmax → conf 필터 → per-class NMS(ultralytics 기본 agnostic=False).
    """
    arr = np.asarray(output, dtype=np.float32)
    if arr.ndim == 3:
        arr = arr[0]
    expected = 4 + num_classes
    if arr.shape[0] == expected and arr.shape[1] != expected:
        arr = arr.T  # channels-first → [N, 4+nc]
    if arr.size == 0:
        return []

    boxes_xywh = arr[:, :4]
    cls_scores = arr[:, 4 : 4 + num_classes]
    class_id = cls_scores.argmax(axis=1)
    conf = cls_scores.max(axis=1)

    mask = conf >= conf_threshold
    if not mask.any():
        return []
    boxes = _xywh_to_xyxy(boxes_xywh[mask])
    class_id = class_id[mask]
    conf = conf[mask]

    dets: list[dict] = []
    for c in range(num_classes):
        idx = np.where(class_id == c)[0]
        if idx.size == 0:
            continue
        keep = _nms(boxes[idx], conf[idx], iou_threshold)
        for k in keep:
            dets.append({"class_id": c, "score": float(conf[idx][k])})
    return dets


class YoloEngine(Protocol):
    """추론 엔진 인터페이스 — 라우터/오케스트레이터는 이 형태에만 의존."""

    model_version: str

    def detect(self, jpeg: bytes) -> YoloResult: ...


class OnnxYoloEngine:  # pragma: no cover - onnxruntime 세션 실행은 통합 검증 대상
    """ONNX(CPU) YOLO 엔진. 부팅 시 S3에서 가중치 lazy-load 후 캐시.

    전처리(letterbox)·후처리(decode_detections)는 순수 함수로 분리해 단위 검증하고,
    본 클래스는 S3 다운로드 + onnxruntime 세션 실행의 얇은 글루만 담당한다.
    """

    def __init__(
        self,
        model_version: str,
        *,
        s3_bucket: str = "helpbee-models",
        cache_dir: str = "/var/cache/helpbee/yolo",
        conf_threshold: float = DEFAULT_CONF,
        iou_threshold: float = DEFAULT_IOU,
        imgsz: int = DEFAULT_IMGSZ,
    ) -> None:
        self.model_version = model_version
        self._s3_bucket = s3_bucket
        self._cache_dir = cache_dir
        self._conf_threshold = conf_threshold
        self._iou_threshold = iou_threshold
        self._imgsz = imgsz
        self._session = None  # lazy

    def _ensure_model(self) -> None:
        import os
        from pathlib import Path

        local = Path(self._cache_dir) / self.model_version / "best.onnx"
        if not local.exists():
            import boto3  # lazy import

            local.parent.mkdir(parents=True, exist_ok=True)
            key = f"yolo/{self.model_version}/best.onnx"
            boto3.client("s3").download_file(self._s3_bucket, key, str(local))
        if self._session is None:
            import onnxruntime as ort  # lazy import

            os.environ.setdefault("OMP_NUM_THREADS", "1")
            self._session = ort.InferenceSession(
                str(local), providers=["CPUExecutionProvider"]
            )

    def detect(self, jpeg: bytes) -> YoloResult:
        self._ensure_model()
        detections = self._infer(jpeg)
        counts, mean = counts_from_detections(detections, self._conf_threshold)
        return YoloResult(
            class_counts=counts,
            confidence=mean,
            model_version=self.model_version,
            raw={"num_detections": len(detections)},
        )

    def _infer(self, jpeg: bytes) -> list[dict]:
        """letterbox → onnxruntime 세션 → raw 출력 디코드 → 검출 리스트."""
        inp = letterbox(Image.open(BytesIO(jpeg)), size=self._imgsz)
        outputs = self._session.run(
            None, {self._session.get_inputs()[0].name: inp}
        )
        return decode_detections(
            outputs[0],
            conf_threshold=self._conf_threshold,
            iou_threshold=self._iou_threshold,
            num_classes=NUM_CLASSES,
        )
