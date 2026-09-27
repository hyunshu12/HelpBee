"""회귀 게이트 v2 — two-stage 서빙 경로 스냅샷 (apps/ai/CLAUDE.md §10-2, 스펙 §7 회귀 row).

무엇을 검증하나:
    매니페스트(app/tests/fixtures/regression_manifest.json, v2)의 각 이미지를 **서빙과 동일한 경로**
    (run_analysis(engine="yolo", two_stage=OnnxTwoStageEngine) → Stage-1→Stage-2→VDI)로 돌려 비교:
      - tier: 정확히 일치 (변동 0)
      - vdi_display: |Δ| ≤ 1.0 (둘 다 null 이면 통과, 한쪽만 null 이면 실패)
      - bee_total: 상대 ±10% (기대 0 이면 정확히 0)

언제 도는가:
    two-stage 번들 캐시(~/.cache/helpbee/two-stage/v0.2.0/) + 71667 Sample 이 모두 있을 때만.
    하나라도 없으면(CI 등) 모듈 전체 skip. 케이스별 sha256 불일치 → 경고 + 그 케이스만 skip.
    `-m regression` 으로 명시 선택해서 돌린다 (기본 addopts 에서 제외).

v1(v0.1.0 단일 스테이지) 매니페스트는 fixtures/regression_manifest_v1.json 으로 보존(퇴역) —
v0.1.0 은 이제 롤백 경로 전용이라 게이트 대상이 아니다.
"""

from __future__ import annotations

import hashlib
import json
import os
import warnings
from pathlib import Path

import pytest

from training.data.make_regression_fixtures import (
    BUNDLE_VERSION,
    MANIFEST_PATH,
    analyze,
    bundle_dir,
    find_datasets_dir,
    load_engine,
)

VDI_TOL = 1.0
BEE_TOTAL_REL = 0.10

pytestmark = pytest.mark.regression


def _load_manifest() -> dict:
    if not MANIFEST_PATH.exists():
        return {"metadata": {}, "fixtures": []}
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


_MANIFEST = _load_manifest()
_FIXTURES = _MANIFEST.get("fixtures", [])
_DATASETS = find_datasets_dir()


def _skip_reason() -> str | None:
    if not _FIXTURES:
        return f"매니페스트 없음/비어있음: {MANIFEST_PATH}"
    if _MANIFEST.get("metadata", {}).get("manifest_version") != 2:
        return "매니페스트가 v2 가 아님 — make regression-fixtures 로 재생성"
    missing = [f for f in ("stage1.onnx", "stage2.onnx", "vdi.yaml", "metadata.json") if not (bundle_dir() / f).exists()]
    if missing:
        return f"two-stage 번들({BUNDLE_VERSION}) 캐시 없음: {bundle_dir()} {missing}"
    if _DATASETS is None:
        return "71667 Sample 데이터셋 없음 (라이선스상 미커밋) — HELPBEE_DATASETS_DIR 지정"
    return None


_SKIP = _skip_reason()
if _SKIP is not None:
    pytestmark = [pytest.mark.regression, pytest.mark.skip(reason=_SKIP)]


@pytest.fixture(scope="module")
def engine():
    """서빙과 동일한 two-stage 엔진 (모듈 1회 로드)."""
    os.environ.setdefault("OMP_NUM_THREADS", "1")
    return load_engine()


def _fixture_id(fx: dict) -> str:
    return f"{fx['case']}/{Path(fx['path']).name}"


@pytest.mark.parametrize("fx", _FIXTURES, ids=[_fixture_id(f) for f in _FIXTURES])
def test_regression_gate(fx: dict, engine):
    img_path = _DATASETS / fx["path"]
    if not img_path.exists():
        pytest.skip(f"이미지 없음: {fx['path']} (합성/블러는 make regression-fixtures 로 생성)")
    data = img_path.read_bytes()

    actual_sha = hashlib.sha256(data).hexdigest()
    if actual_sha != fx["sha256"]:
        warnings.warn(
            f"sha256 불일치 {fx['path']}: 기대 {fx['sha256'][:12]} != 실제 {actual_sha[:12]} "
            "— 매니페스트 재생성 필요, 이 케이스 skip",
            stacklevel=2,
        )
        pytest.skip("sha256 mismatch (이미지 변경)")

    res = analyze(engine, data)
    fid = _fixture_id(fx)

    assert res.tier == fx["expected_tier"], (
        f"tier 드리프트 {fid}: 기대 {fx['expected_tier']} != 실제 {res.tier} "
        f"(vdi {fx['expected_vdi_display']}→{res.vdi_display}, bees {fx['expected_bee_total']}→{res.bee_total})"
    )

    exp_v, act_v = fx["expected_vdi_display"], res.vdi_display
    assert (exp_v is None) == (act_v is None), f"vdi_display null 여부 변화 {fid}: {exp_v} → {act_v}"
    if exp_v is not None:
        dv = abs(float(act_v) - float(exp_v))
        assert dv <= VDI_TOL, f"vdi 드리프트 {fid}: {exp_v} → {act_v} (|Δ|={dv:.1f} > {VDI_TOL})"

    exp_n, act_n = fx["expected_bee_total"], int(res.bee_total or 0)
    if exp_n == 0:
        assert act_n == 0, f"bee_total 드리프트 {fid}: 0 → {act_n}"
    else:
        rel = abs(act_n - exp_n) / exp_n
        assert rel <= BEE_TOTAL_REL, f"bee_total 드리프트 {fid}: {exp_n} → {act_n} ({rel:.0%} > 10%)"
