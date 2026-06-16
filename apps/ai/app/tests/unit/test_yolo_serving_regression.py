"""실모델 서빙경로 회귀 — train/serve 전처리 skew 가드.

preprocess_image의 JPEG 재압축 품질이 너무 낮으면 응애의 미세 신호가 약화되어
검출 앵커의 argmax가 varroa→normal로 뒤집혀 **false negative**가 발생한다
(safe로 오진). 이 테스트는 알려진 응애 양성 이미지가 서빙 전 파이프라인
(preprocess_image → letterbox → ONNX → decode → compute_risk)을 통과했을 때
응애가 검출되고 tier가 'safe'가 아님을 보장한다.

모델(best.onnx)과 샘플 이미지는 git-ignored(로컬/통합 전용)라 부재 시 skip.
정식 라벨 기반 golden 서빙경로 평가는 별도 과제(eval 정렬) — 이 테스트는 그 대용
스모크 가드다.
"""

from __future__ import annotations

import glob
import os
from pathlib import Path

import pytest

_ONNX_CANDIDATES = [
    os.getenv("HELPBEE_YOLO_ONNX", ""),
    "/tmp/hbcache/v0.1.0/best.onnx",
    "/var/cache/helpbee/yolo/v0.1.0/best.onnx",
    str(Path.home() / ".cache/helpbee/yolo/v0.1.0/best.onnx"),
]

# 응애 양성으로 알려진 샘플(폴더 성충_응애/012). 데이터셋 루트는 git-ignored.
_IMG_ENV = os.getenv("HELPBEE_VARROA_SAMPLE", "")
_IMG_GLOBS = [
    "training/datasets/Sample/**/성충_응애/012/*.jpg",
    "training/datasets/**/성충_응애/012/*.jpg",
]


def _find(paths: list[str]) -> str | None:
    for p in paths:
        if p and Path(p).is_file():
            return p
    return None


def _find_glob(globs: list[str]) -> str | None:
    for g in globs:
        hits = sorted(glob.glob(g, recursive=True))
        if hits:
            return hits[0]
    return None


@pytest.mark.regression
def test_serving_pipeline_detects_known_varroa_not_safe():
    onnx = _find(_ONNX_CANDIDATES)
    img = _find([_IMG_ENV]) or _find_glob(_IMG_GLOBS)
    if not onnx or not img:
        pytest.skip("model(best.onnx) 또는 샘플 이미지 부재 — 로컬/통합 전용")

    from app.services.orchestrator import run_analysis
    from app.services.yolo_engine import OnnxYoloEngine

    onnx_path = Path(onnx)
    engine = OnnxYoloEngine(
        model_version=onnx_path.parent.name,
        cache_dir=str(onnx_path.parent.parent),
    )
    resp = run_analysis(Path(img).read_bytes(), engine="yolo", yolo=engine, openai=None)

    counts = resp.raw_payload.get("class_counts", {})
    varroa = counts.get(1, 0)
    # 핵심 불변식: 알려진 응애 양성이 서빙 경로에서 '검출되고' 'safe로 오진되지 않는다'.
    assert varroa >= 1, f"varroa false negative (counts={counts}) — 전처리 skew 회귀"
    assert resp.tier != "safe", f"varroa 양성이 safe로 오진 (tier={resp.tier})"
