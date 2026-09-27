"""training/ 스크립트의 텍스트 I/O 는 encoding 을 명시해야 한다.

학습 박스는 Windows(cp949 로케일)라 encoding 없는 read_text()/write_text()/open() 은
YAML/JSON 의 한국어에서 UnicodeDecodeError/EncodeError 로 죽는다.

AST 기반 — 여러 줄에 걸친 호출의 encoding= 도 인식하고, 바이너리 모드('rb'/'wb' 등)와
PIL Image.open 은 제외한다.
"""
import ast
from pathlib import Path

TRAINING = Path(__file__).resolve().parents[3] / "training"


def _has_encoding(call: ast.Call) -> bool:
    return any(kw.arg == "encoding" for kw in call.keywords)


def _is_binary_mode(call: ast.Call, mode_pos: int) -> bool:
    mode = next((kw.value for kw in call.keywords if kw.arg == "mode"), None)
    if mode is None and len(call.args) > mode_pos:
        mode = call.args[mode_pos]
    return isinstance(mode, ast.Constant) and isinstance(mode.value, str) and "b" in mode.value


def _offense(call: ast.Call) -> bool:
    func = call.func
    if isinstance(func, ast.Attribute) and func.attr in ("read_text", "write_text"):
        return not _has_encoding(call)
    if isinstance(func, ast.Name) and func.id == "open":  # builtin open(path, mode)
        return not _has_encoding(call) and not _is_binary_mode(call, 1)
    if isinstance(func, ast.Attribute) and func.attr == "open":
        if isinstance(func.value, ast.Name) and func.value.id == "Image":  # PIL, 바이너리
            return False
        return not _has_encoding(call) and not _is_binary_mode(call, 0)  # Path.open(mode)
    return False


def test_no_bare_text_io_in_training():
    offenders = []
    for py in sorted(TRAINING.rglob("*.py")):
        source = py.read_text(encoding="utf-8")
        lines = source.splitlines()
        for node in ast.walk(ast.parse(source, filename=str(py))):
            if isinstance(node, ast.Call) and _offense(node):
                offenders.append(
                    f"{py.relative_to(TRAINING)}:{node.lineno}: {lines[node.lineno - 1].strip()}"
                )
    assert not offenders, "\n".join(offenders)
