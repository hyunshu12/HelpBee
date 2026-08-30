"""make_booth_cases 계약 검증.

Sample 데이터셋(gitignored)이 로컬에 있을 때만 실행된다. CI에서는 skip.
"""
import pytest

from training.data.make_booth_cases import BOOTH_CASES, SAMPLE_ROOT, build_case

pytestmark = pytest.mark.skipif(
    not (SAMPLE_ROOT / "02.라벨링데이터").exists(),
    reason="AI Hub Sample 데이터셋이 로컬에 없음",
)


def _case(case_id: str) -> dict:
    spec = next(s for s in BOOTH_CASES if s.id == case_id)
    return build_case(spec)


def test_danger_case_matches_verified_label_values():
    c = _case("danger-100")
    assert c["riskScore"] == 100
    assert c["tier"] == "danger"
    assert c["beeTotal"] == 7
    assert c["varroaCount"] == 2
    assert len(c["recommendations"]) == 5


def test_all_bee_boxes_are_kept():
    """좌표가 정확하면(2026-08-30 xyxy 수정) 정상 벌 박스도 겹치거나 잘리지 않는다 — 전부 그린다 (설계 §6 갱신)."""
    c = _case("danger-100")
    assert len(c["boxes"]) == c["beeTotal"]
    assert sum(1 for b in c["boxes"] if b["cls"] == "varroa") == c["varroaCount"]


def test_safe_case_has_no_varroa_boxes():
    c = _case("safe-0")
    assert c["riskScore"] == 0
    assert c["tier"] == "safe"
    assert c["varroaCount"] == 0
    assert all(b["cls"] != "varroa" for b in c["boxes"])
    assert len(c["boxes"]) == 6


@pytest.mark.parametrize("spec", BOOTH_CASES, ids=lambda s: s.id)
def test_every_box_is_inside_image_bounds(spec):
    """잘린 박스는 부스에서 사각형이 화면 밖으로 나가 보인다 (설계 §6 선정 기준 2)."""
    c = build_case(spec)
    for b in c["boxes"]:
        assert b["x"] >= 0 and b["y"] >= 0
        assert b["x"] + b["w"] <= c["imageWidth"]
        assert b["y"] + b["h"] <= c["imageHeight"]


def test_four_cases_cover_three_tiers():
    tiers = [build_case(s)["tier"] for s in BOOTH_CASES]
    assert len(BOOTH_CASES) == 4
    assert tiers.count("danger") == 2
    assert tiers.count("watch") == 1
    assert tiers.count("safe") == 1
