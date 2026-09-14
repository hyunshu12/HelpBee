"""부스 체험 앱(apps/booth)용 고정 결과 데이터 생성기 — 1회성 도구.

모델 추론을 돌리지 않는다. AI Hub 71667 정답 라벨을 3-class로 매핑한 뒤
프로덕션 코드인 app.services.risk.compute_risk()를 그대로 호출해
risk / tier / recommendations 를 얻는다. risk.yaml 이 바뀌면 이 스크립트만
다시 돌리면 되고, 부스 앱 문구가 실제 앱과 어긋나지 않는다.

사진 선정 기준과 근거는 plans/2026-08-30_부스체험앱-설계.md §4·§6.

실행:
    cd apps/ai && ./.venv/bin/python -m training.data.make_booth_cases
"""

from __future__ import annotations

import json
import pathlib
from collections import Counter
from dataclasses import dataclass

from PIL import Image, ImageEnhance

from app.services.risk import CLASS_OTHER, CLASS_VARROA, compute_risk
from training.data.aihub_to_yolo import CLASS_MAPPING

SAMPLE_ROOT = pathlib.Path(__file__).resolve().parents[2] / "training/datasets/Sample"
BOOTH_ASSETS = pathlib.Path(__file__).resolve().parents[3] / "booth/assets"

LONG_EDGE = 1600

# 71667 7-class → 박스 위에 찍을 한국어 태그.
#
# 3-class(varroa/disease/normal)는 색을 정하는 데만 쓴다. 관람객에게는 초록 박스가
# 전부 "정상 벌"로 보이는데, 실제로는 성충과 유충(애벌레)이 섞여 있어서 "이게 왜
# 벌이냐"는 질문이 나온다(2026-09-14 피드백). 원본 라벨이 이미 구분하고 있으니
# 그대로 내보낸다.
BOX_LABELS = {
    0: "유충",
    1: "응애",
    2: "석고병",
    3: "부저병",
    4: "정상 벌",
    5: "응애",
    6: "날개불구",
}


@dataclass(frozen=True)
class BoothCaseSpec:
    id: str
    rel: str          # 01.원천데이터 / 02.라벨링데이터 공통 상대경로 (확장자 없음)
    brightness: float  # 표시용 보정 — 원본이 어두워 아이패드에서 안 보인다
    contrast: float
    kind: str          # "visible" | "varroa" | "healthy" — 라운드 배정 키
    disease: str | None       # "dwv" | "chalkbrood" | "varroa" | None
    disease_label: str | None  # 화면 표시명


# 2026-08-30 fix round 1: 이전 선정(danger-90/83, safe-0/076)은 bbox 를 [x,y,w,h] 로 잘못
# 해석해 계산한 면적 기준으로 골랐던 것이라 무효화됐다 — 아래 build_case() 주석 참고.
# 새 선정: danger-100(082, 응애 박스 2개 겹침 없이 잘 분리됨) · danger-90(089) · watch-50(033) ·
# safe-0(005, 신규). 교체 시 §4 선정 기준을 xyxy 해석으로 재적용할 것.
BOOTH_CASES: list[BoothCaseSpec] = [
    # ── R1 후보: 눈에 보이는 병 (하얗게 굳은 애벌레는 누가 봐도 이상하다)
    # ⚠️ 폴더명은 "석고병"이지만 실제 라벨은 **부저병**이 다수다(044: 부저병 14 / 석고병 1,
    # 032: 부저병 12). AIHUB_71667.md §3 "폴더명 ≠ 라벨" 그대로다. 2026-09-14 박스 태그를
    # 붙이면서 드러났고, 화면 병명은 아래 build_case() 가 라벨 최빈값에서 유도한다 —
    # 여기 disease_label 은 병든 박스가 하나도 없을 때의 폴백일 뿐이다.
    BoothCaseSpec("foul-1", "유충/유충_석고병/044/B_001_001_20230819135429_001_004_000_002",
                  1.35, 1.20, "visible", "foulbrood", "부저병"),
    BoothCaseSpec("foul-2", "유충/유충_석고병/032/B_001_001_20230819135415_001_004_000_002",
                  1.35, 1.20, "visible", "foulbrood", "부저병"),
    BoothCaseSpec("dwv-1", "성충/성충_날개불구바이러스감염증/015/B_001_001_20230824130702_001_004_001_002",
                  1.25, 1.15, "visible", "dwv", "날개불구 바이러스"),
    # ── R2 후보: 응애 위험
    #
    # 2026-09-14 교체: 이전 선정(082/089/057)은 벌 한두 마리를 꽉 채운 클로즈업이라
    # 관람객이 응애를 그냥 찾아냈다(아이패드 실측). 부스의 요지는 "육안으로는
    # 어렵다"이므로, 벌이 화면에서 작게 잡힌 프레임으로 바꾼다 — 박스 중앙값
    # 면적이 이미지의 3~4%(이전 12~30%) 수준이다.
    BoothCaseSpec("danger-100", "성충/성충_응애/024/B_001_003_20230820110731_001_002_001_001",
                  1.25, 1.15, "varroa", "varroa", "응애"),
    BoothCaseSpec("danger-90", "성충/성충_응애/021/B_001_002_20230827131140_001_001_001_001",
                  1.25, 1.15, "varroa", "varroa", "응애"),
    BoothCaseSpec("danger-78", "성충/성충_응애/029/B_001_003_20230822084843_001_004_001_001",
                  1.25, 1.15, "varroa", "varroa", "응애"),
    # ── R3 후보: 응애 주의 (33마리 중 1마리급 — R2보다 더 미세하다)
    BoothCaseSpec("watch-58", "성충/성충_응애/074/B_001_008_20230825084547_001_004_001_001",
                  1.55, 1.25, "varroa", "varroa", "응애"),
    BoothCaseSpec("watch-21", "성충/성충_응애/068/B_001_007_20230827133939_001_001_001_001",
                  1.55, 1.25, "varroa", "varroa", "응애"),
    # ── R3 후보: 정상(함정) — 응애 0 · 다른 병 0 인 것만
    BoothCaseSpec("safe-0", "성충/성충_정상/005/B_001_001_20230819135627_001_003_001_000",
                  1.50, 1.25, "healthy", None, None),
    BoothCaseSpec("safe-2", "성충/성충_정상/057/B_001_001_20230822083827_001_004_001_000",
                  1.50, 1.25, "healthy", None, None),
]

# [1] "응애가 뭐죠?" 화면 전용. 유충에 붙은 응애 2마리가 육안으로 보이는 유일한 계열.
# 진단 흐름에는 쓰지 않는다 (벌 1마리 = 저신뢰, 벌통 사진으로 보이지 않음).
VARROA_CLOSEUP = "유충/유충_응애/046/C_001_001_20230829142857_001_001_000_001"

# [2] "이런 병들을 찾습니다" 화면 전용 클로즈업 2장 (2026-09-14 추가).
# 1라운드에 석고병이 나오는데 인트로가 응애만 설명해서, 관람객이 처음 보는 병을
# 아무 맥락 없이 맞닥뜨렸다(아이패드 실측 피드백). 진단 흐름에는 쓰지 않는다.
FOUL_CLOSEUP = "유충/유충_석고병/044/B_001_001_20230819135429_001_004_000_002"
DWV_CLOSEUP = "성충/성충_날개불구바이러스감염증/015/B_001_001_20230824130702_001_004_001_002"


def _label(rel: str) -> dict:
    return json.loads((SAMPLE_ROOT / "02.라벨링데이터" / f"{rel}.json").read_text(encoding="utf-8"))


def _source(rel: str) -> pathlib.Path:
    return SAMPLE_ROOT / "01.원천데이터" / f"{rel}.jpg"


def build_case(spec: BoothCaseSpec) -> dict:
    """라벨 JSON 1개 → cases.json 의 케이스 1개. 파일을 쓰지 않는다(테스트 가능)."""
    label = _label(spec.rel)
    width = int(label["image"]["width"])
    height = int(label["image"]["height"])

    counts = {0: 0, 1: 0, 2: 0}
    boxes: list[dict] = []
    for ann in label["annotations"]:
        cls = CLASS_MAPPING.get(ann["category_id"])
        if cls is None:
            continue
        counts[cls] += 1
        # 2026-08-30 fix round 1: AI Hub 71667 raw bbox 는 실제로 [x1, y1, x2, y2] 다.
        # AIHUB_71667.md·aihub_to_yolo.py 가 문서화한 "COCO [x, y, w, h]" 가정은 틀렸다 —
        # Sample 4210개 annotation 중 4208개(100.0%)가 annotation.area 필드와 xyxy 공식으로
        # 일치했고, xywh 공식과 일치한 건 14개(0.3%)뿐이었다(팀장 재검증 완료). 다시 xywh 로
        # "고치지" 말 것 — cases.json 에는 계속 x/y/w/h(좌상단+크기) 키로 내보낸다.
        x1, y1, x2, y2 = (float(v) for v in ann["bbox"])
        boxes.append({
            "x": x1,
            "y": y1,
            "w": x2 - x1,
            "h": y2 - y1,
            # 3-class → 화면 색. varroa=빨강 / disease=주황 / normal=초록
            "cls": {CLASS_VARROA: "varroa", CLASS_OTHER: "disease"}.get(cls, "normal"),
            "label": BOX_LABELS[int(ann["category_id"])],
        })  # 좌표가 정확하면 정상 벌 박스도 겹치거나 잘리지 않는다 — 전부 그린다 (설계 §6 갱신)

    # 화면에 띄울 병명은 **라벨에서** 정한다. 폴더명(그리고 그걸 보고 적은 spec)은
    # 틀릴 수 있다 — 2026-09-14 "석고병" 폴더 사진 두 장이 실제로는 부저병이었다.
    # 다만 spec 이 지목한 병이 라벨에 실제로 있으면 그걸 쓴다 — 동률일 때
    # (dwv-1: 날개불구 2 · 부저병 2) Counter 가 임의로 고르면 사진의 주인공이
    # 아닌 병명이 제목에 올라간다.
    sick_labels = [b["label"] for b in boxes if b["cls"] in ("varroa", "disease")]
    if spec.disease_label and any(
        lbl.startswith(spec.disease_label[:3]) for lbl in sick_labels
    ):
        disease_label = spec.disease_label
    elif sick_labels:
        disease_label = Counter(sick_labels).most_common(1)[0][0]
    else:
        disease_label = spec.disease_label

    risk = compute_risk(counts)
    # 응애든 다른 병이든 "이상 개체 수" 하나로 셈한다 — 화면 문구가 하나면 된다.
    sick = counts[CLASS_VARROA] + counts[CLASS_OTHER]
    return {
        "id": spec.id,
        "photo": f"photos/{spec.id}.jpg",
        "kind": spec.kind,
        "disease": spec.disease,
        "diseaseLabel": disease_label,
        "imageWidth": width,
        "imageHeight": height,
        "riskScore": risk.risk_score,
        "tier": risk.tier,
        "beeTotal": risk.bee_total,
        "sickCount": sick,
        # 처방은 제품 코드(compute_risk → risk.yaml)에서 온다. 다른 병 케이스는
        # CLASS_OTHER 카운트 때문에 other_disease 문구가 자동으로 붙는다 —
        # 부스에서 문구를 지어내지 않는다.
        "recommendations": list(risk.recommendations),
        "boxes": boxes,
    }


def _export_photo(rel: str, dest: pathlib.Path, brightness: float, contrast: float) -> None:
    """표시용 밝기·대비 보정 + 긴 변 축소. 좌표는 정규화 전 원본 픽셀 기준이므로
    cases.json 의 박스 좌표는 imageWidth/imageHeight 에 대해 그대로 유효하다."""
    img = Image.open(_source(rel)).convert("RGB")
    img = ImageEnhance.Brightness(img).enhance(brightness)
    img = ImageEnhance.Contrast(img).enhance(contrast)
    scale = LONG_EDGE / max(img.width, img.height)
    if scale < 1.0:
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    img.save(dest, quality=90)


def _export_closeup(rel: str, dest: pathlib.Path, cls: int = CLASS_VARROA) -> None:
    """[1] 인트로용 클로즈업. 전체 프레임으로 내보내면 유충이 8% 크기라 응애가
    안 보인다 — 관람객이 3초 보고 지나가는 화면이므로 라벨 bbox 기준으로 잘라
    유충이 화면을 채우게 한다. (진단용 4장은 박스 좌표가 전체 프레임 기준이라
    절대 크롭하지 않는다.)

    `annotations[0]`을 그대로 쓰지 않고 varroa 클래스 annotation을 명시적으로
    찾는다 — 지금 VARROA_CLOSEUP 라벨은 첫 annotation이 우연히 응애라 맞았지만,
    라벨을 다른 사진으로 교체하면 첫 annotation이 응애가 아닐 수도 있다. 그러면
    "응애가 안 보이는" 크롭이 조용히 만들어지고 에러 없이 통과해 버린다.
    """
    label = _label(rel)
    img = Image.open(_source(rel)).convert("RGB")
    W, H = img.width, img.height
    varroa_anns = [
        ann
        for ann in label["annotations"]
        if CLASS_MAPPING.get(ann["category_id"]) == cls
    ]
    assert varroa_anns, (
        f"{rel} 라벨에 클래스 {cls} annotation이 없다 — 인트로 클로즈업은 그 병이 "
        "보이는 크롭이어야 한다. 사진을 교체했다면 그 라벨에 해당 클래스 "
        "annotation이 있는지 확인할 것."
    )
    # 가장 큰 박스를 고른다 — 같은 병이라도 라벨에는 소방 한 칸짜리 작은 영역이
    # 섞여 있어서, 첫 번째를 집으면 병든 개체가 안 보이는 크롭이 나온다
    # (2026-09-14 날개불구 크롭이 빈 소방 구멍만 담겼다).
    def _area(ann: dict) -> float:
        a, b, c, d = (float(v) for v in ann["bbox"])
        return abs((c - a) * (d - b))

    x1, y1, x2, y2 = (float(v) for v in max(varroa_anns, key=_area)["bbox"])
    cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
    ch = min(H, (y2 - y1) * 1.35)
    cw = ch * 16 / 9
    if cw > W:
        cw, ch = W, W * 9 / 16
    left = max(0.0, min(W - cw, cx - cw / 2))
    top = max(0.0, min(H - ch, cy - ch / 2))
    crop = img.crop((int(left), int(top), int(left + cw), int(top + ch)))
    crop = crop.resize((LONG_EDGE, round(LONG_EDGE * ch / cw)), Image.LANCZOS)
    crop = ImageEnhance.Contrast(crop).enhance(1.12)
    dest.parent.mkdir(parents=True, exist_ok=True)
    crop.save(dest, quality=92)


def main() -> None:
    cases = [build_case(spec) for spec in BOOTH_CASES]
    for spec in BOOTH_CASES:
        _export_photo(spec.rel, BOOTH_ASSETS / "photos" / f"{spec.id}.jpg", spec.brightness, spec.contrast)
    _export_closeup(VARROA_CLOSEUP, BOOTH_ASSETS / "varroa_closeup.jpg")
    _export_closeup(FOUL_CLOSEUP, BOOTH_ASSETS / "foul_closeup.jpg", CLASS_OTHER)
    _export_closeup(DWV_CLOSEUP, BOOTH_ASSETS / "dwv_closeup.jpg", CLASS_OTHER)

    out = BOOTH_ASSETS / "cases.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"cases": cases}, ensure_ascii=False, indent=2), encoding="utf-8")
    for c in cases:
        print(f"{c['id']:<10} risk {c['riskScore']:>3} / {c['tier']:<6} "
              f"벌 {c['beeTotal']:>2} · 박스 {len(c['boxes'])} · 처방 {len(c['recommendations'])}")
    print(f"\n→ {out}")


if __name__ == "__main__":
    main()
