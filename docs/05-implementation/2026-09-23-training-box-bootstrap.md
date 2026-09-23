# 2026-09-23 — Windows 학습 박스 부트스트랩 + `tasks.py` 러너

> PR: (미생성) · 브랜치: feature/ai-two-stage-redesign-spec · 2-stage 재설계 계획 1 / Task 1

## 범위 (Scope)

make 없는 네이티브 Windows 학습 박스(`ssh beetrain`, RTX 4060 8GB)에서 학습 파이프라인을 돌리기 위한
1회성 부트스트랩 스크립트와 Makefile 대체 러너 `apps/ai/tasks.py`를 추가했다.

## 산출물 (Deliverables)

- `apps/ai/tasks.py` — `python tasks.py <target>` 러너. `TARGETS: dict[str, Callable[[list[str]], int]]`에
  `doctor`(도구/모듈/CUDA/`HELPBEE_DATA_ROOT` 점검, `--dry`는 CUDA 생략), `trash <path>`(Windows는
  SHFileOperationW 휴지통, Mac은 `trash` CLI) 등록. 알 수 없는 target → 목록 출력 + exit 2.
  후속 태스크가 `convert`/`split`/`golden`/`train-stage1`/`crops`/`train-stage2`/`gate0`/`eval`를 같은 dict에 추가.
- `apps/ai/training/env/bootstrap.ps1` — winget으로 Python 3.11 / Git / 7-Zip 설치, User env
  `PYTHONUTF8=1`, `HELPBEE_DATA_ROOT=D:\helpbee-data`, 데이터 디렉터리 생성. 재실행 안전.
  브리프 대비 추가 2건(박스 실측으로 필요 확인):
  - `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` — 기본 Restricted 가 `.venv\Scripts\Activate.ps1`을 막음.
    `-ExecutionPolicy Bypass`로 실행 중이면 값은 기록되지만 `ExecutionPolicyOverride` 예외가 나서 try/catch로 삼킨다.
  - `C:\Program Files\7-Zip`을 User PATH에 추가 — 7-Zip winget 설치기는 PATH를 건드리지 않음.
- `apps/ai/requirements-gpu.txt` — 상단 주석에 torch 핀(`torch==2.4.1+cu121 / torchvision==0.19.1`, cu121 index) 명시,
  `onnx>=1.16`, `onnxruntime>=1.18`, `scipy>=1.11` 추가.
- `apps/ai/app/tests/unit/test_tasks_runner.py` — doctor 출력 / unknown target exit 2.

## 박스 셋업 절차

```powershell
# 관리자 아님 OK (winget user scope). 1회:
powershell -NoProfile -ExecutionPolicy Bypass -File apps\ai\training\env\bootstrap.ps1
# 새 셸에서:
cd <repo>\apps\ai
py -3.11 -m venv .venv ; .\.venv\Scripts\Activate.ps1
pip install torch==2.4.1 torchvision==0.19.1 --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements-gpu.txt      # torch 재설치 없음 (범위 <2.5 만족), pip check 깨끗
python tasks.py doctor
```

## 검증 (Verification)

박스(`DESKTOP-LRU3MLF`)에서 새 ssh 세션 + venv 활성화 후 `python tasks.py doctor`:

```
python               C:\helpbee\apps\ai\.venv\Scripts\python.EXE
git                  C:\Program Files\Git\cmd\git.EXE
7z                   C:\Program Files\7-Zip\7z.EXE
torch                2.4.1+cu121
ultralytics          8.3.253
onnxruntime          1.23.2
cuda                 True NVIDIA GeForce RTX 4060
HELPBEE_DATA_ROOT    D:\helpbee-data
```

- `python tasks.py trash <file>` → rc 0, 파일 휴지통 이동 확인. `python tasks.py nope` → rc 2.
- Mac: `pytest app/tests/unit/test_tasks_runner.py -q` 2 passed, 전체 `pytest -q` green.

## 알려진 제약 / 후속 (Follow-up)

- 이 브랜치가 아직 origin에 push되지 않아 박스의 `C:\helpbee\apps\ai`에는 `tasks.py`·`requirements*.txt`만
  scp로 복사돼 있다(git clone 아님). 브랜치 push 후 `git clone https://github.com/hyunshu12/HelpBee.git C:\helpbee`
  로 교체하고(기존 `.venv`는 재생성 또는 이동) 이후 태스크를 진행할 것.
- 박스의 venv Python은 3.11.9, Mac 로컬 테스트 venv는 3.12.

## 참조

- 권위 가이드: `apps/ai/CLAUDE.md` · 학습 박스 메모: `yolo-training-box`
- 계획: 2-stage 재설계 구현 계획 1 (데이터·학습 파이프라인) Task 1
