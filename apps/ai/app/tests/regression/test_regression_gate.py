"""회귀 게이트 — 서빙 경로 스냅샷 (apps/ai/CLAUDE.md §10-2).

무엇을 검증하나:
    매니페스트(app/tests/fixtures/regression_manifest.json)의 각 이미지를 **서빙과
    동일한 경로**(run_analysis(engine="yolo") → preprocess→YOLO(ONNX)→risk)로 돌려,
    기대 risk_score/tier 와 비교한다.
      - risk_score: abs(expected - actual) <= 10  (CLAUDE.md §10-2 허용 오차)
      - tier: 정확히 일치 (드리프트 0 허용)

언제 도는가:
    로컬에 (a) ONNX 모델과 (b) 71667 Sample 데이터셋이 모두 있을 때만 실제로 돈다.
    둘 중 하나라도 없으면(예: CI) 전 케이스 skip — 라이선스상 이미지를 커밋할 수
    없으므로 이게 설계 의도다. `-m regression` 으로 명시 선택해서 돌린다.

왜 스냅샷인가:
    기대값은 ground-truth 가 아니라 "현재 모델 서빙 출력". 프롬프트/모델핀/risk.yaml
    가중치 변경이 출력을 흔들면 게이트가 잡는다. 의도된 변경이면 매니페스트를
    make_regression_fixtures 로 재생성한다.
"""

from __future__ import annotations

import hashlib
import json
import os
import warnings
from pathlib import Path

import pytest

# app/tests/regression/test_regression_gate.py → parents[3] = apps/ai
AI_ROOT = Path(__file__).resolve().parents[3]
MANIFEST_PATH = AI_ROOT / "app" / "tests" / "fixtures" / "regression_manifest.json"
MODEL_CACHE = Path.home() / ".cache" / "helpbee" / "yolo"

RISK_TOLERANCE = 10  # abs(expected - actual) 허용

pytestmark = pytest.mark.regression


def _load_manifest() -> dict:
    if not MANIFEST_PATH.exists():
        return {"metadata": {}, "fixtures": []}
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


_MANIFEST = _load_manifest()
_FIXTURES = _MANIFEST.get("fixtures", [])
_MODEL_VERSION = _MANIFEST.get("metadata", {}).get("model_version", "v0.1.0")


def _model_path() -> Path:
    return MODEL_CACHE / _MODEL_VERSION / "best.onnx"


def _skip_reason() -> str | None:
    """모델/데이터셋 부재 → skip 사유 (없으면 None)."""
    if not _FIXTURES:
        return f"매니페스트 없음/비어있음: {MANIFEST_PATH}"
    if not _model_path().exists():
        return f"ONNX 모델 없음: {_model_path()} (S3 helpbee-models 에서 받아 캐시)"
    # 첫 fixture 이미지로 데이터셋 존재 확인
    first = AI_ROOT / _FIXTURES[0]["path"]
    if not first.exists():
        return f"71667 Sample 데이터셋 없음 (라이선스상 미커밋): {first}"
    return None


_SKIP = _skip_reason()


@pytest.fixture(scope="module")
def engine():
    """서빙과 동일한 ONNX 엔진 (모듈 1회 로드)."""
    os.environ.setdefault("OMP_NUM_THREADS", "1")
    from app.services.yolo_engine import OnnxYoloEngine

    return OnnxYoloEngine(_MODEL_VERSION, cache_dir=str(MODEL_CACHE))


def _fixture_id(fx: dict) -> str:
    return f"{fx['class_folder']}/{Path(fx['path']).name}"


@pytest.mark.skipif(_SKIP is not None, reason=_SKIP or "")
@pytest.mark.parametrize("fx", _FIXTURES, ids=[_fixture_id(f) for f in _FIXTURES])
def test_regression_gate(fx: dict, engine):
    from app.services.orchestrator import run_analysis

    img_path = AI_ROOT / fx["path"]
    if not img_path.exists():
        pytest.skip(f"이미지 없음: {fx['path']}")
    data = img_path.read_bytes()

    # sha256 검증 — 이미지가 바뀌면 기대값 무효 → 경고 후 skip (fail 아님)
    actual_sha = hashlib.sha256(data).hexdigest()
    if actual_sha != fx["sha256"]:
        warnings.warn(
            f"sha256 불일치 {fx['path']}: 기대 {fx['sha256'][:12]} != 실제 "
            f"{actual_sha[:12]} — 매니페스트 재생성 필요, 이 케이스 skip",
            stacklevel=2,
        )
        pytest.skip("sha256 mismatch (이미지 변경)")

    res = run_analysis(data, engine="yolo", yolo=engine)

    assert res.tier == fx["expected_tier"], (
        f"tier 드리프트 {_fixture_id(fx)}: 기대 {fx['expected_tier']} != 실제 {res.tier} "
        f"(risk {fx['expected_risk_score']}→{res.risk_score})"
    )
    delta = abs(res.risk_score - fx["expected_risk_score"])
    assert delta <= RISK_TOLERANCE, (
        f"risk_score 드리프트 {_fixture_id(fx)}: 기대 {fx['expected_risk_score']} vs "
        f"실제 {res.risk_score} (|Δ|={delta} > {RISK_TOLERANCE})"
    )
