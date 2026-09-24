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
    assert "targets:" in out.stdout  # tasks.py 자체가 없어서 난 rc 2 와 구분

def test_subset_runs_index_select_materialize_in_order(tmp_path):
    out = subprocess.run([sys.executable, "tasks.py", "subset", "--tl-zip", "TL.zip", "--ts-zip", "vols/TS.zip",
                          "--out-root", str(tmp_path / "sub"), "--n", "100", "--verify-listing", "--dry"],
                         cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    assert out.returncode == 0, out.stderr
    cmds = [l for l in out.stdout.splitlines() if l.startswith("+ ")]
    assert [c.split("training.data.aihub_subset ")[1].split()[0] for c in cmds] == ["index", "select", "materialize"]
    assert "--n 100" in cmds[1] and "--verify-listing" in cmds[2] and "vols/TS.zip" in cmds[2]
