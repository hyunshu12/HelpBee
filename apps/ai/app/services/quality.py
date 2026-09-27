"""사진 품질 체크 (스펙 v2.2 §3 quality, §4 ①).

- 블러: 긴 변 1024 축소본의 Laplacian 분산 < blur_min(100) → 실패
- 노출: 그레이 평균 ∉ [40, 215] → 실패
- 해상도: px_per_mm_est = 중앙값 벌 폭(px) / 12mm — **경고만**(게이트 아님).
  v0.2.0 은 `capture_floor_px_per_mm: null` 이라 경고도 나지 않는다(보고만).
임계값은 vdi.yaml `quality` 섹션이 단일 소스 — 호출부가 넘긴다.
"""

from __future__ import annotations

import numpy as np

BEE_WIDTH_MM = 12.0
_ANALYSIS_EDGE = 1024


def assess_quality(
    img: np.ndarray,
    boxes: list | None,
    floor_px_per_mm: float | None,
    *,
    blur_min: float = 100.0,
    exposure: tuple[float, float] = (40.0, 215.0),
) -> dict:
    """img: uint8 [H,W,3] **RGB**. boxes: 원본 좌표 xyxy 목록(없으면 px/mm 미산출)."""
    import cv2

    h, w = img.shape[:2]
    small = img
    if max(h, w) > _ANALYSIS_EDGE:
        s = _ANALYSIS_EDGE / max(h, w)
        small = cv2.resize(img, (max(1, round(w * s)), max(1, round(h * s))), interpolation=cv2.INTER_AREA)
    gray = cv2.cvtColor(np.ascontiguousarray(small), cv2.COLOR_RGB2GRAY)
    blur = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    mean = float(gray.mean())

    reasons: list[str] = []
    warnings: list[str] = []
    if blur < blur_min:
        reasons.append("blur")
    if not (exposure[0] <= mean <= exposure[1]):
        reasons.append("exposure")

    px = None
    if boxes:
        med_w = float(np.median([float(b[2]) - float(b[0]) for b in boxes]))
        px = round(med_w / BEE_WIDTH_MM, 2)
        if floor_px_per_mm is not None and px < floor_px_per_mm:
            warnings.append("resolution")
    return {
        "ok": not reasons,
        "blur_score": round(blur, 2),
        "exposure_mean": round(mean, 2),
        "px_per_mm_est": px,
        "reasons": reasons,
        "warnings": warnings,
    }
