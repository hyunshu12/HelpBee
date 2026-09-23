# apps/ai/app/tests/unit/test_tasks_runner.py
import subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]  # apps/ai

def test_doctor_lists_required_tools():
    out = subprocess.run([sys.executable, "tasks.py", "doctor", "--dry"], cwd=ROOT,
                         capture_output=True, text=True, encoding="utf-8")
    assert out.returncode == 0
    for tool in ("python", "git", "7z", "torch", "ultralytics"):
        assert tool in out.stdout

def test_unknown_target_fails():
    out = subprocess.run([sys.executable, "tasks.py", "nope"], cwd=ROOT,
                         capture_output=True, text=True, encoding="utf-8")
    assert out.returncode == 2
