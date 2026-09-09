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
    assert c["sickCount"] == 2
    assert len(c["recommendations"]) == 5


def test_all_bee_boxes_are_kept():
    """좌표가 정확하면(2026-08-30 xyxy 수정) 정상 벌 박스도 겹치거나 잘리지 않는다 — 전부 그린다 (설계 §6 갱신)."""
    c = _case("danger-100")
    assert len(c["boxes"]) == c["beeTotal"]
    assert sum(1 for b in c["boxes"] if b["cls"] == "varroa") == c["sickCount"]


def test_safe_case_has_no_varroa_boxes():
    c = _case("safe-0")
    assert c["riskScore"] == 0
    assert c["tier"] == "safe"
    assert c["sickCount"] == 0
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


def test_pool_covers_the_difficulty_ladder():
    """R1 쉬움 / R2 응애 위험 / R3 응애 주의·정상 — 세 후보군이 다 있어야 배정이 성립한다.

    2026-09-08: 4장 자유선택에서 10장 3라운드 투어로 바뀌었다.
    """
    cases = [build_case(s) for s in BOOTH_CASES]
    danger = [c for c in cases if c["kind"] == "varroa" and c["tier"] == "danger"]
    watch = [c for c in cases if c["kind"] == "varroa" and c["tier"] == "watch"]
    assert len(danger) >= 1, "R2(응애 위험) 후보가 없다"
    assert len(watch) >= 1, "R3(응애 주의) 후보가 없다"
    assert sum(1 for c in cases if c["kind"] == "visible") >= 1, "R1 후보가 없다"
    assert sum(1 for c in cases if c["kind"] == "healthy") >= 1, "R3 함정 후보가 없다"


def test_visible_case_has_disease_fields():
    """다른 병 케이스는 병 이름을 달고, 응애 카운트가 아니라 병 개체 수를 센다."""
    from training.data.make_booth_cases import BOOTH_CASES, build_case

    spec = next(s for s in BOOTH_CASES if s.kind == "visible")
    case = build_case(spec)

    assert case["kind"] == "visible"
    assert case["disease"] in ("dwv", "chalkbrood")
    assert case["diseaseLabel"]
    assert case["sickCount"] >= 2, "감염 개체가 2마리 이상인 사진을 골라야 한다"
    assert "varroaCount" not in case, "varroaCount 는 sickCount 로 대체됐다"
    # 다른 병 박스는 'disease' 로 나가야 결과 화면이 주황으로 그린다.
    assert any(b["cls"] == "disease" for b in case["boxes"])
    assert not any(b["cls"] == "varroa" for b in case["boxes"])
    # 처방은 제품 코드(risk.yaml)에서 온다 — 부스에서 지어내지 않는다.
    assert any("다른 질병" in r for r in case["recommendations"])


def test_varroa_case_still_counts_varroa():
    from training.data.make_booth_cases import BOOTH_CASES, build_case

    spec = next(s for s in BOOTH_CASES if s.kind == "varroa")
    case = build_case(spec)
    assert case["kind"] == "varroa"
    assert case["disease"] == "varroa"
    assert case["sickCount"] >= 1
    assert any(b["cls"] == "varroa" for b in case["boxes"])


def test_healthy_case_has_no_sick_boxes():
    from training.data.make_booth_cases import BOOTH_CASES, build_case

    for spec in (s for s in BOOTH_CASES if s.kind == "healthy"):
        case = build_case(spec)
        assert case["kind"] == "healthy"
        assert case["disease"] is None
        assert case["sickCount"] == 0, f"{spec.id}: 정상 사진에 감염 개체가 섞였다"
        assert all(b["cls"] == "normal" for b in case["boxes"])


def test_pool_covers_every_round():
    """라운드 배정이 성립하려면 세 종류가 모두 있어야 한다."""
    from training.data.make_booth_cases import BOOTH_CASES

    kinds = [s.kind for s in BOOTH_CASES]
    assert kinds.count("visible") >= 3
    assert kinds.count("varroa") >= 5
    assert kinds.count("healthy") >= 2
    assert len(BOOTH_CASES) == 10
    assert len({s.id for s in BOOTH_CASES}) == 10, "id 중복"
