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
from dataclasses import dataclass

from PIL import Image, ImageEnhance

from app.services.risk import CLASS_VARROA, compute_risk
from training.data.aihub_to_yolo import CLASS_MAPPING

SAMPLE_ROOT = pathlib.Path(__file__).resolve().parents[2] / "training/datasets/Sample"
BOOTH_ASSETS = pathlib.Path(__file__).resolve().parents[3] / "booth/assets"

LONG_EDGE = 1600


@dataclass(frozen=True)
class BoothCaseSpec:
    id: str
    rel: str          # 01.원천데이터 / 02.라벨링데이터 공통 상대경로 (확장자 없음)
    brightness: float  # 표시용 보정 — 원본이 어두워 아이패드에서 안 보인다
    contrast: float


# 2026-08-30 fix round 1: 이전 선정(danger-90/83, safe-0/076)은 bbox 를 [x,y,w,h] 로 잘못
# 해석해 계산한 면적 기준으로 골랐던 것이라 무효화됐다 — 아래 build_case() 주석 참고.
# 새 선정: danger-100(082, 응애 박스 2개 겹침 없이 잘 분리됨) · danger-90(089) · watch-50(033) ·
# safe-0(005, 신규). 교체 시 §4 선정 기준을 xyxy 해석으로 재적용할 것.
BOOTH_CASES: list[BoothCaseSpec] = [
    BoothCaseSpec("danger-100", "성충/성충_응애/082/A_001_001_20230822060110_011_001_001_001", 1.25, 1.15),
    BoothCaseSpec("danger-90", "성충/성충_응애/089/A_001_001_20230822060113_007_001_001_001", 1.25, 1.15),
    BoothCaseSpec("watch-50", "성충/성충_응애/033/B_001_003_20230824081648_001_003_001_001", 1.55, 1.25),
    BoothCaseSpec("safe-0", "성충/성충_정상/005/B_001_001_20230819135627_001_003_001_000", 1.50, 1.25),
]

# [1] "응애가 뭐죠?" 화면 전용. 유충에 붙은 응애 2마리가 육안으로 보이는 유일한 계열.
# 진단 흐름에는 쓰지 않는다 (벌 1마리 = 저신뢰, 벌통 사진으로 보이지 않음).
VARROA_CLOSEUP = "유충/유충_응애/046/C_001_001_20230829142857_001_001_000_001"


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
            "cls": "varroa" if cls == CLASS_VARROA else "normal",
        })  # 좌표가 정확하면 정상 벌 박스도 겹치거나 잘리지 않는다 — 전부 그린다 (설계 §6 갱신)

    risk = compute_risk(counts)
    return {
        "id": spec.id,
        "photo": f"photos/{spec.id}.jpg",
        "imageWidth": width,
        "imageHeight": height,
        "riskScore": risk.risk_score,
        "tier": risk.tier,
        "beeTotal": risk.bee_total,
        "varroaCount": counts[CLASS_VARROA],
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


def _export_closeup(rel: str, dest: pathlib.Path) -> None:
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
        if CLASS_MAPPING.get(ann["category_id"]) == CLASS_VARROA
    ]
    assert varroa_anns, (
        f"{rel} 라벨에 응애(bee_with_varroa) annotation이 없다 — 인트로 클로즈업은 "
        "응애가 보이는 크롭이어야 한다. VARROA_CLOSEUP 을 다른 사진으로 바꿨다면 "
        "그 라벨에 응애 클래스 annotation이 있는지 확인할 것."
    )
    x1, y1, x2, y2 = (float(v) for v in varroa_anns[0]["bbox"])
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

    out = BOOTH_ASSETS / "cases.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"cases": cases}, ensure_ascii=False, indent=2), encoding="utf-8")
    for c in cases:
        print(f"{c['id']:<10} risk {c['riskScore']:>3} / {c['tier']:<6} "
              f"벌 {c['beeTotal']:>2} · 박스 {len(c['boxes'])} · 처방 {len(c['recommendations'])}")
    print(f"\n→ {out}")


if __name__ == "__main__":
    main()
