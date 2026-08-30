#!/usr/bin/env python3
"""부스 앱 본문용 한글 폰트(Noto Sans KR)를 서브셋해 assets/fonts/ 에 굽는다.

왜 필요한가
-----------
Flutter Web(CanvasKit)은 번들 폰트에 없는 글리프를 만나면 **런타임에
fonts.gstatic.com 에서 Noto 조각을 내려받는다**. 즉 폰트를 번들하지 않으면
웹 백업은 **인터넷이 있어야만** 한글이 보이고, 없으면 전부 두부(□)로 뜬다.
부스 Wi-Fi 를 신뢰할 수 없는데 웹 백업은 바로 그 "네이티브가 안 될 때"를
위한 것이라, 오프라인에서 깨지면 백업으로서 의미가 없다.
(2026-08-31 실측: notosanskr woff2 5조각을 gstatic 에서 받아감)

무엇을 굽는가
-------------
- 커버리지 = **앱 소스·cases.json 에 실제로 쓰인 문자** ∪ **Jua 가 가진 한글 음절**.
  Jua 의 cmap 이 사실상 KS X 1001 상용 2350자라, 문구를 고쳐도 웬만하면 커버된다.
  별도 목록을 들고 다니지 않아도 되는 자기완결적 기준이라 이걸 쓴다.
- 가변 폰트를 wght 400 / 700 두 정적 인스턴스로 고정해 굽는다.

실행: python3 tool/build_body_font.py <NotoSansKR[wght].ttf 경로>
"""
from __future__ import annotations

import glob
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "fonts"
JUA = OUT_DIR / "Jua-Regular.ttf"
WEIGHTS = {"Regular": 400, "Bold": 700}


def used_chars() -> set[str]:
    chars: set[str] = set()
    for p in glob.glob(str(ROOT / "lib" / "**" / "*.dart"), recursive=True):
        chars |= set(pathlib.Path(p).read_text(encoding="utf-8"))
    chars |= set((ROOT / "assets" / "cases.json").read_text(encoding="utf-8"))
    return chars


def jua_hangul() -> set[str]:
    from fontTools.ttLib import TTFont

    cmap = TTFont(JUA).getBestCmap()
    return {chr(c) for c in cmap if 0xAC00 <= c <= 0xD7A3}


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src = pathlib.Path(sys.argv[1])

    # ASCII 전체를 항상 포함한다 — 숫자·문장부호가 빠지면 '/100' 같은 표기가 깨진다.
    charset = used_chars() | jua_hangul() | {chr(c) for c in range(0x20, 0x7F)}
    charset |= set("·—…‘’“”→←±°%")
    text = "".join(sorted(charset))

    from fontTools import varLib
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer

    for name, wght in WEIGHTS.items():
        font = TTFont(src)
        instancer.instantiateVariableFont(font, {"wght": wght}, inplace=True)
        with tempfile.NamedTemporaryFile(suffix=".ttf", delete=False) as tmp:
            font.save(tmp.name)
            static = tmp.name

        out = OUT_DIR / f"NotoSansKR-{name}.ttf"
        subprocess.run(
            [
                "pyftsubset",
                static,
                f"--text={text}",
                "--layout-features=*",
                "--no-hinting",
                "--desubroutinize",
                f"--output-file={out}",
            ],
            check=True,
        )
        print(f"  {out.name}: {out.stat().st_size / 1024:.0f} KB")

    _ = varLib  # 임포트 유지(가변 폰트 지원 확인용)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
