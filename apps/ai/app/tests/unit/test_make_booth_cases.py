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
    # varroa-4 (성충_응애/012): 응애 1 + 날개불구 1 / 8 — 2026-09-16 라벨 검증값.
    c = _case("varroa-4")
    assert c["riskScore"] == 78
    assert c["tier"] == "danger"
    assert c["beeTotal"] == 8
    assert c["sickCount"] == 2
    assert len(c["recommendations"]) == 5


def test_all_bee_boxes_are_kept():
    """좌표가 정확하면(2026-08-30 xyxy 수정) 정상 벌 박스도 겹치거나 잘리지 않는다 — 전부 그린다 (설계 §6 갱신)."""
    c = _case("varroa-4")
    assert len(c["boxes"]) == c["beeTotal"]
    # sickCount = 응애 + 다른 병 (2026-09-16 부터 응애 사진에 다른 병이 같이 있다)
    assert sum(1 for b in c["boxes"] if b["cls"] in ("varroa", "disease")) == c["sickCount"]


def test_safe_case_has_no_varroa_boxes():
    c = _case("healthy-1")
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


def test_pool_is_hard_by_eye():
    """2026-09-16: 세 라운드가 독립 동전던지기(병 | 정상)라 두 무리가 겉보기에 같아야 한다.

    - 병든 사진은 병든 개체가 소수(≤ 20%)여야 한다 — 12/12 부저병 같은 건 퀴즈가 아니다.
    - 응애 사진은 compute_risk 가 safe 를 주면 안 된다 — 화면에 '안전' 배지가 떠서
      정답('문제 있음')과 모순된다.
    """
    cases = [build_case(s) for s in BOOTH_CASES]
    for c in cases:
        if c["kind"] == "healthy":
            assert c["sickCount"] == 0, c["id"]
            continue
        assert c["sickCount"] / c["beeTotal"] <= 1 / 3, f"{c['id']}: 병든 개체가 너무 많아 눈에 띈다"
        if c["kind"] == "varroa":
            assert c["tier"] != "safe", f"{c['id']}: 응애인데 안전 등급 — 정답과 모순"


def test_varroa_cases_carry_a_second_disease():
    """2026-09-16: 2·3라운드 사진은 응애 + 다른 병이 같이 있어야 한다.

    결과 화면에서 "응애 말고도 이런 게 있었다"가 함께 보여야 하고, 다른 병을 보고
    '문제 있음'을 맞힌 관람객에게도 "그래도 응애는 못 봤다"는 대비가 선다.
    """
    for spec in (s for s in BOOTH_CASES if s.kind == "varroa"):
        c = build_case(spec)
        assert any(b["cls"] == "varroa" for b in c["boxes"]), spec.id
        assert any(b["cls"] == "disease" for b in c["boxes"]), f"{spec.id}: 다른 병이 없다"


def test_round1_pool_has_no_chalkbrood():
    """1라운드 선택지는 정상·날개불구·부저병 — 석고병이 나오면 맞힐 방법이 없다."""
    for spec in (s for s in BOOTH_CASES if s.kind == "visible"):
        assert build_case(spec)["disease"] in ("dwv", "foulbrood"), spec.id


def test_visible_case_has_disease_fields():
    """다른 병 케이스는 병 이름을 달고, 응애 카운트가 아니라 병 개체 수를 센다."""
    from training.data.make_booth_cases import BOOTH_CASES, build_case

    spec = next(s for s in BOOTH_CASES if s.kind == "visible")
    case = build_case(spec)

    assert case["kind"] == "visible"
    assert case["disease"] in ("dwv", "chalkbrood")
    assert case["diseaseLabel"]
    assert case["sickCount"] >= 1
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
    # 정상은 최소 3장 — 세 라운드가 다 정상으로 떨어져도 채울 수 있어야 한다.
    assert kinds.count("healthy") >= 3
    assert kinds.count("varroa") >= 3
    assert kinds.count("visible") >= 3
    assert len(BOOTH_CASES) == 14
    assert len({s.id for s in BOOTH_CASES}) == 14, "id 중복"
