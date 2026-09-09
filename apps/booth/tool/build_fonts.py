#!/usr/bin/env python3
"""부스 앱이 번들하는 한글 폰트 두 개를 서브셋해 assets/fonts/ 에 굽는다.

왜 번들하는가
-------------
Flutter Web(CanvasKit)은 번들 폰트에 없는 글리프를 만나면 **런타임에
fonts.gstatic.com 에서 Noto 조각을 내려받는다.** 즉 폰트를 번들하지 않으면
웹 백업은 인터넷이 있어야만 한글이 보이고, 없으면 전부 두부(□)로 뜬다.
부스 Wi-Fi 를 신뢰할 수 없는데 웹 백업은 바로 그 "네이티브가 안 될 때"를
위한 것이라, 오프라인에서 깨지면 백업으로서 의미가 없다.

왜 서브셋하는가
---------------
원본을 통째로 넣으면 Jua 2.0MB + Noto 2종으로 에셋이 무거워진다. 특히 웹
백업은 부스 Wi-Fi 로 이걸 매번 받아야 한다. 실제로 쓰는 글자만 남기면
Jua 는 2.0MB → 약 0.3MB 로 줄어든다.

두 폰트의 역할이 다르므로 커버리지도 다르게 잡는다
--------------------------------------------------
- **Noto Sans KR (본문, 넓게)**: 앱이 쓰는 글자 ∪ 상용 한글 2,367자
  (`tool/hangul_common.txt`). 문구를 고쳐도 웬만하면 커버된다.
- **Jua (표시용, 좁게)**: 앱이 **지금 쓰는 글자만**. 헤드라인·숫자·워드마크에만
  쓰이므로 넓게 담을 이유가 없다. 나중에 새 글자가 헤드라인에 들어가면
  `fontFamilyFallback` 을 타고 Noto 로 그려진다 — 서체는 달라져도 **두부는
  아니다**(lib/theme/app_fonts.dart 참조).

원본 폰트 (둘 다 OFL, 재배포 가능)
----------------------------------
  Noto Sans KR: https://github.com/google/fonts/raw/main/ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf
  Jua:          https://github.com/google/fonts/raw/main/ofl/jua/Jua-Regular.ttf

실행:
  python3 tool/build_fonts.py --noto <NotoSansKR[wght].ttf> --jua <Jua-Regular.ttf>
"""

from __future__ import annotations

import argparse
import glob
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "fonts"
COMMON_HANGUL = pathlib.Path(__file__).resolve().parent / "hangul_common.txt"

# ASCII 전체 + 앱이 쓰는 기호. 숫자·문장부호가 빠지면 '/100' 같은 표기가 깨진다.
ALWAYS = {chr(c) for c in range(0x20, 0x7F)} | set("·—…‘’“”→←±°%")

NOTO_WEIGHTS = {"Regular": 400, "Bold": 700}

# 소스 전체를 긁으므로 **주석의 이모지**(⚠️ 의 variation selector 등)까지 딸려
# 온다. 한글 서체에 있을 리 없는 글자를 "필수"로 요구하면 검증이 헛돌므로,
# 화면에 실제로 그려질 수 있는 범위만 남긴다. 넉넉히 잡되 이모지는 뺀다.
RENDERABLE_RANGES = [
    (0x20, 0x7E),      # ASCII 인쇄 가능
    (0xA0, 0xFF),      # Latin-1 보충 (도, 플러스마이너스 등)
    (0x2000, 0x206F),  # 일반 문장부호 (긴 줄표, 말줄임표, 따옴표)
    (0x2190, 0x21FF),  # 화살표
    (0x3000, 0x303F),  # CJK 문장부호 (가운뎃점, 낫표)
    (0x3130, 0x318F),  # 한글 자모
    (0xAC00, 0xD7A3),  # 한글 완성형 음절
]


def renderable(c: str) -> bool:
    return any(lo <= ord(c) <= hi for lo, hi in RENDERABLE_RANGES)


def used_chars() -> set[str]:
    """앱 소스와 cases.json 에 실제로 등장하는 모든 문자."""
    chars: set[str] = set()
    for p in glob.glob(str(ROOT / "lib" / "**" / "*.dart"), recursive=True):
        chars |= set(pathlib.Path(p).read_text(encoding="utf-8"))
    cases = ROOT / "assets" / "cases.json"
    if cases.exists():
        chars |= set(cases.read_text(encoding="utf-8"))
    else:
        print(f"  ! {cases} 없음 — cases.json 문구는 커버리지에서 빠진다", file=sys.stderr)
    dropped = {c for c in chars if not renderable(c) and not c.isspace()}
    if dropped:
        # 눈에 보이게 알린다 — 진짜 UI 문자가 여기 섞였다면 버그다.
        shown = "".join(sorted(dropped))[:30]
        print(f"  . 서체 대상 아님으로 제외 {len(dropped)}자: {shown!r}")
    return {c for c in chars if renderable(c)}


def subset(src: pathlib.Path, charset: set[str], out: pathlib.Path) -> None:
    subprocess.run(
        [
            "pyftsubset",
            str(src),
            "--text=" + "".join(sorted(charset)),
            "--layout-features=*",
            "--no-hinting",
            "--desubroutinize",
            f"--output-file={out}",
        ],
        check=True,
    )


def verify(out: pathlib.Path, required: set[str], label: str) -> None:
    """서브셋이 실제로 필요한 글자를 담고 있는지 확인한다.

    pyftsubset 이 조용히 글자를 빠뜨리면 그 글자만 두부가 된다 — 빌드 시점에
    잡지 못하면 부스 현장에서야 발견하게 된다.
    """
    from fontTools.ttLib import TTFont

    cmap = set(TTFont(out).getBestCmap())
    missing = {c for c in required if ord(c) not in cmap}
    if missing:
        raise SystemExit(
            f"{label}: 서브셋에 {len(missing)}자가 빠졌다 → {''.join(sorted(missing))[:40]}"
        )
    print(f"  {out.name}: {out.stat().st_size / 1024:.0f} KB  (글리프 {len(cmap)})")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--noto", type=pathlib.Path, required=True)
    ap.add_argument("--jua", type=pathlib.Path, required=True)
    args = ap.parse_args()

    used = used_chars()
    common = set(COMMON_HANGUL.read_text(encoding="utf-8"))

    body_set = used | common | ALWAYS
    display_set = used | ALWAYS

    print(f"앱이 쓰는 문자 {len(used)}자 / 상용 한글 {len(common)}자")

    # ── Noto (본문, 넓게) — 가변 폰트를 정적 두 웨이트로 고정
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    for name, wght in NOTO_WEIGHTS.items():
        font = TTFont(args.noto)
        instancer.instantiateVariableFont(font, {"wght": wght}, inplace=True)
        with tempfile.NamedTemporaryFile(suffix=".ttf", delete=False) as tmp:
            font.save(tmp.name)
            static = pathlib.Path(tmp.name)
        out = OUT_DIR / f"NotoSansKR-{name}.ttf"
        subset(static, body_set, out)
        # 본문 폰트는 앱이 쓰는 글자를 **반드시** 전부 담아야 한다 —
        # 여기가 뚫리면 폴백이 없어 그대로 두부가 된다.
        verify(out, used | ALWAYS, f"NotoSansKR-{name}")
        static.unlink(missing_ok=True)

    # ── Jua (표시용, 좁게)
    out = OUT_DIR / "Jua-Regular.ttf"
    subset(args.jua, display_set, out)
    # Jua 는 원본에 없는 글자가 있을 수 있다(2,519자 한정). 없으면 Noto 로
    # 폴백되므로 실패로 보지 않고, 무엇이 폴백될지만 알린다.
    from fontTools.ttLib import TTFont as _TT

    jua_cmap = set(_TT(out).getBestCmap())
    fallback = {c for c in used if ord(c) not in jua_cmap and not c.isspace()}
    print(f"  {out.name}: {out.stat().st_size / 1024:.0f} KB  (글리프 {len(jua_cmap)})")
    if fallback:
        print(f"  · Jua 원본에 없어 Noto 로 폴백될 글자 {len(fallback)}자: "
              f"{''.join(sorted(fallback))[:40]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
