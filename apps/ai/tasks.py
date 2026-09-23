# apps/ai/tasks.py
"""Windows/Mac 공용 태스크 러너 — Makefile 대체 (make 없는 네이티브 Windows용).
Usage: python tasks.py <target> [args...]   (apps/ai 에서 실행)
"""
from __future__ import annotations
import os, shutil, subprocess, sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parent
os.environ.setdefault("PYTHONUTF8", "1")
DATA_ROOT = Path(os.environ.get("HELPBEE_DATA_ROOT", r"D:\helpbee-data" if os.name == "nt" else str(ROOT / "training/datasets")))

def _run(cmd: list[str]) -> int:
    print("+", " ".join(cmd), flush=True)
    return subprocess.call(cmd, cwd=ROOT)

def doctor(args: list[str]) -> int:
    dry = "--dry" in args
    rows = []
    for tool in ("python", "git", "7z"):
        rows.append((tool, shutil.which(tool) or "MISSING"))
    for mod in ("torch", "ultralytics", "onnxruntime"):
        try:
            m = __import__(mod); rows.append((mod, getattr(m, "__version__", "ok")))
        except Exception as e:  # noqa: BLE001
            rows.append((mod, f"MISSING ({type(e).__name__})"))
    if not dry:
        try:
            import torch; rows.append(("cuda", f"{torch.cuda.is_available()} {torch.cuda.get_device_name(0) if torch.cuda.is_available() else ''}"))
        except Exception:
            rows.append(("cuda", "n/a"))
    rows.append(("HELPBEE_DATA_ROOT", str(DATA_ROOT)))
    for k, v in rows: print(f"{k:<20} {v}")
    return 0

def trash(args: list[str]) -> int:
    """휴지통 이동 (영구 삭제 금지 정책)."""
    if not args: print("usage: tasks.py trash <path>"); return 2
    p = Path(args[0]).resolve()
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes
        class SHFILEOPSTRUCTW(ctypes.Structure):
            _fields_ = [("hwnd", wintypes.HWND), ("wFunc", wintypes.UINT), ("pFrom", wintypes.LPCWSTR),
                        ("pTo", wintypes.LPCWSTR), ("fFlags", ctypes.c_uint16), ("fAnyOperationsAborted", wintypes.BOOL),
                        ("hNameMappings", ctypes.c_void_p), ("lpszProgressTitle", wintypes.LPCWSTR)]
        op = SHFILEOPSTRUCTW(None, 3, str(p) + "\0\0", None, 0x0040 | 0x0010 | 0x0004, False, None, None)  # FOF_ALLOWUNDO|NOCONFIRMATION|SILENT
        return int(ctypes.windll.shell32.SHFileOperationW(ctypes.byref(op)))
    return _run(["trash", str(p)])

def split(args: list[str]) -> int:
    """split_manifest.json 생성 — <HELPBEE_DATA_ROOT>/aihub-71667-val (예: D:\\helpbee-data). 추가 인자는 그대로 전달."""
    root = Path(os.environ.get("HELPBEE_DATA_ROOT", str(DATA_ROOT)))
    return _run([sys.executable, "-m", "training.data.make_split_manifest",
                 "--roots", str(root / "aihub-71667-val"), "--tags", "71667-val", *args])

def golden(args: list[str]) -> int:
    """split_manifest.json 의 golden split 에서 응애/정상 golden 선택 → training/golden.json. 추가 인자는 그대로 전달."""
    return _run([sys.executable, "-m", "training.data.golden_holdout",
                 "--manifest", "training/split_manifest.json", "--output", "training/golden.json", *args])

TARGETS: dict[str, Callable[[list[str]], int]] = {"doctor": doctor, "trash": trash, "split": split, "golden": golden}

def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in TARGETS:
        print("targets:", ", ".join(sorted(TARGETS))); return 2
    return TARGETS[sys.argv[1]](sys.argv[2:])

if __name__ == "__main__":
    sys.exit(main())
