"""자체 YOLO 추론 엔진.

설계 근거: backend-design §3.3, apps/ai/CLAUDE.md §8, ADR-0001(YOLOv11s@640).
- 단위 검증 대상: counts_from_detections (검출 → 클래스 카운트, 순수 로직).
- OnnxYoloEngine: S3 lazy-load + onnxruntime CPU 추론. 실모델 의존이라
  본 환경에서 단위 테스트하지 않음(통합 검증 대상, pragma no cover).
  B5 라우터는 YoloEngine 프로토콜에 의존 → 테스트에선 Fake 주입.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol, Sequence

CLASS_IDS = (0, 1, 2)  # 0=bee_normal, 1=bee_with_varroa, 2=bee_other_disease


@dataclass
class YoloResult:
    class_counts: dict[int, int]
    confidence: float  # 검출 평균 신뢰도 (0~1)
    model_version: str
    raw: dict = field(default_factory=dict)


def counts_from_detections(
    detections: Sequence[dict],
    conf_threshold: float = 0.25,
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


class YoloEngine(Protocol):
    """추론 엔진 인터페이스 — 라우터/오케스트레이터는 이 형태에만 의존."""

    model_version: str

    def detect(self, jpeg: bytes) -> YoloResult: ...


class OnnxYoloEngine:  # pragma: no cover - 실모델/onnxruntime 의존, 통합 검증 대상
    """ONNX(CPU) YOLO 엔진. 부팅 시 S3에서 가중치 lazy-load 후 캐시.

    가정: ultralytics `export(format="onnx", nms=True)` 산출물 →
          출력[0] shape [N, 6] = [x1, y1, x2, y2, score, class_id].
    실제 출력 스펙은 export 산출물에 맞춰 통합 테스트에서 검증할 것.
    """

    def __init__(
        self,
        model_version: str,
        *,
        s3_bucket: str = "helpbee-models",
        cache_dir: str = "/var/cache/helpbee/yolo",
        conf_threshold: float = 0.25,
        imgsz: int = 640,
    ) -> None:
        self.model_version = model_version
        self._s3_bucket = s3_bucket
        self._cache_dir = cache_dir
        self._conf_threshold = conf_threshold
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

            self._session = ort.InferenceSession(
                str(local), providers=["CPUExecutionProvider"]
            )
        os.environ.setdefault("OMP_NUM_THREADS", "1")

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
        """ONNX 세션 실행 → 검출 리스트. (통합 검증 대상)"""
        import numpy as np
        from PIL import Image
        from io import BytesIO

        img = Image.open(BytesIO(jpeg)).convert("RGB").resize((self._imgsz, self._imgsz))
        arr = (np.asarray(img, dtype="float32") / 255.0).transpose(2, 0, 1)[None, ...]
        outputs = self._session.run(None, {self._session.get_inputs()[0].name: arr})
        out = outputs[0]
        rows = out[0] if out.ndim == 3 else out  # [N, 6]
        dets: list[dict] = []
        for row in rows:
            if len(row) >= 6:
                dets.append({"class_id": int(row[5]), "score": float(row[4])})
        return dets
