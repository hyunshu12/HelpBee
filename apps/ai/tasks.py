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

def train_stage1(args: list[str]) -> int:
    """Stage-1 학습 — training/configs/stage1.yaml. 추가 인자(--fold A, --set k=v ...)는 그대로 전달."""
    return _run([sys.executable, "-m", "training.train", "--config", "training/configs/stage1.yaml", *args])

def crops(args: list[str]) -> int:
    """Stage-2 크롭 추출 (out-of-fold) → training/crops. --weights-A/-B/-all 등 인자는 그대로 전달."""
    return _run([sys.executable, "-m", "training.data.make_crops",
                 "--manifest", "training/split_manifest.json", "--out", "training/crops", *args])

def train_stage2(args: list[str]) -> int:
    """Stage-2 학습·보정·ONNX — training/configs/stage2.yaml. 추가 인자(--degrade none|90, --set k=v ...)는 그대로 전달."""
    return _run([sys.executable, "-m", "training.train_stage2", "--config", "training/configs/stage2.yaml", *args])

def gate0(args: list[str]) -> int:
    """Gate 0(b) px/mm 별 recall 곡선 → training/eval_history/v0.2.0-gate0.json. --weights/--crops 등 인자는 그대로 전달."""
    return _run([sys.executable, "-m", "training.gate0_pxmm", *args])

def eval_stage2(args: list[str]) -> int:
    """Stage-2 분리 지표·지름길 프로브 → training/eval_history/v0.2.0-stage2.json. --weights/--crops 등 인자는 그대로 전달."""
    return _run([sys.executable, "-m", "training.eval_stage2", *args])

def eval_e2e(args: list[str]) -> int:
    """합성 e2e tier 일치율 + 단일 스테이지 베이스라인 → training/eval_history/v0.2.0-e2e.json. --onnx/--crops 등 인자는 그대로 전달."""
    return _run([sys.executable, "-m", "training.eval_e2e", *args])

def subset(args: list[str]) -> int:
    """71667 Training 서브셋 (TL.zip 스트리밍 index → select → materialize) — DOWNLOAD.md §4-1.
    --tl-zip/--ts-zip/--out-root 필수. --work(기본 <out-root>/_subset), --n, --seed, --per-colony-cap,
    --limit, --sevenzip, --verify-listing, --reindex(기존 index.jsonl 무시), --dry(명령만 출력)."""
    import argparse
    ap = argparse.ArgumentParser(prog="tasks.py subset")
    ap.add_argument("--tl-zip", required=True); ap.add_argument("--ts-zip", required=True)
    ap.add_argument("--out-root", required=True); ap.add_argument("--work")
    ap.add_argument("--n", default="25000"); ap.add_argument("--seed", default="42")
    ap.add_argument("--per-colony-cap", default="0.15"); ap.add_argument("--limit")
    ap.add_argument("--sevenzip", default=shutil.which("7z") or r"C:\Program Files\7-Zip\7z.exe")
    ap.add_argument("--verify-listing", action="store_true"); ap.add_argument("--reindex", action="store_true")
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args(args)
    work = Path(a.work or Path(a.out_root) / "_subset")
    index, selected = work / "index.jsonl", work / "selected.jsonl"
    mod = [sys.executable, "-m", "training.data.aihub_subset"]
    steps = []
    if a.reindex or not index.exists():
        steps.append([*mod, "index", "--tl-zip", a.tl_zip, "--out", str(index), *(["--limit", a.limit] if a.limit else [])])
    else:
        print(f"= index 재사용: {index} (--reindex 로 다시 생성)")
    steps.append([*mod, "select", "--index", str(index), "--n", a.n, "--seed", a.seed,
                  "--per-colony-cap", a.per_colony_cap, "--out", str(selected)])
    steps.append([*mod, "materialize", "--selected", str(selected), "--ts-zip", a.ts_zip, "--out-root", a.out_root,
                  "--sevenzip", a.sevenzip, *(["--verify-listing"] if a.verify_listing else [])])
    for cmd in steps:
        if a.dry:
            print("+", " ".join(cmd)); continue
        rc = _run(cmd)
        if rc: return rc
    return 0

TARGETS: dict[str, Callable[[list[str]], int]] = {"doctor": doctor, "trash": trash, "split": split, "golden": golden,
                                                  "train-stage1": train_stage1, "crops": crops,
                                                  "train-stage2": train_stage2, "gate0": gate0,
                                                  "eval-stage2": eval_stage2, "eval-e2e": eval_e2e,
                                                  "subset": subset}

def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in TARGETS:
        print("targets:", ", ".join(sorted(TARGETS))); return 2
    return TARGETS[sys.argv[1]](sys.argv[2:])

if __name__ == "__main__":
    sys.exit(main())
