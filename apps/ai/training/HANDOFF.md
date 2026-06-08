# v0.1.0 학습 핸드오프 (GPU 서버 → Claude Code 세션 인수인계)

> 이 문서는 **앨리스 클라우드 GPU 서버에서 새로 띄운 Claude Code 세션**이
> 로컬 세션의 작업을 끊김 없이 이어받기 위한 cold-pickup 문서다.
> 작성: 2026-06-08 | 작성 주체: 로컬 Claude Code 세션

---

## 0. 30초 요약

- **목표**: AI Hub 71667 데이터로 **v0.1.0 YOLOv11s 베이스라인** 학습 (응애 진단).
- **결정 끝남**: 단일스테이지 3-class. 근거는 `docs/01-development/adr/ADR-0001-yolo-engine-architecture.md`.
- **지금 단계**: GPU 서버에서 **데이터 다운로드 → 변환 → 분할 → 학습 → 평가 → ONNX export**.
- **환경**: 앨리스 A100 80GB, 디스크 **121.8GB 한도**, driver 535 / CUDA 12.2.
- **핵심 제약**: 디스크가 작아 **Validation 셋(28GB)만** 받아서 베이스라인 검증.

---

## 1. 인수받은 세션이 가장 먼저 할 일

```bash
# develop 브랜치에 학습 코드 전부 머지됨 (PR #11 MERGED)
cd HelpBee && git checkout develop && git pull origin develop
```

그다음 이 3개 문서를 읽어라 (이미 CLAUDE.md는 자동 로드됨):
1. `apps/ai/CLAUDE.md` — AI 도메인 규칙 (3-class, infestation_rate, 640 imgsz, trash 사용)
2. `apps/ai/training/datasets/AIHUB_71667.md` — 데이터셋 단일 진실 소스 ★필독
3. `docs/01-development/adr/ADR-0001-yolo-engine-architecture.md` — 왜 단일스테이지인지

---

## 2. 확정된 기술 결정 (변경 금지, 근거 있음)

| 항목 | 값 | 근거 |
|---|---|---|
| 아키텍처 | **단일스테이지** 3-class detection | ADR-0001 (hybrid_phased, confidence 76) |
| 모델 | **YOLOv11s** (`yolo11s.yaml`) | `configs/yolo.yaml` |
| imgsz | **640** (P2 head 미사용, 1280 아님) | 71667 bbox가 medium~large뿐 (AIHUB §6) |
| 클래스 | `bee_normal`(0) / `bee_with_varroa`(1) / `bee_other_disease`(2) | AIHUB §5 |
| 위험도 | **infestation_rate** (표준 VMIR 아님) | 71667에 응애 자체 bbox 없음 (Q3=B, AIHUB §6) |
| 분할 | **per_colony_time_block** (data leakage 방지) | `split_strategy.py` 자동 선택 |
| golden | 300장 (응애 100 + 정상 200), 학습/aug 영구 제외 | `golden_holdout.py` |

⚠️ **Q3=B 함정**: 71667의 응애 라벨은 "응애 객체"가 아니라 **"응애가 보이는 벌 전체 영역"**.
그래서 클래스명이 `bee_with_varroa`이고, 응애 마릿수 카운팅 불가. infestation_rate = 감염 벌 / 전체 벌.
`yolov11s-p2.yaml`은 v0.2.0 실험용이므로 v0.1.0에서 **쓰지 마라.**

---

## 3. 환경 셋업 (앨리스 A100, CUDA 12.2 함정 주의)

```bash
cd apps/ai
python -m venv .venv && source .venv/bin/activate

# ⚠️ 앨리스 preinstalled torch는 driver 535(CUDA 12.2)에 너무 최신이라 깨진다.
#    "NVIDIA driver too old (found version 12020)" 에러가 나면 이걸로 고정:
pip install -q torch==2.4.1 torchvision==0.19.1 --index-url https://download.pytorch.org/whl/cu121
pip install -r requirements-gpu.txt   # ultralytics, wandb 등

# 검증 (아래가 떠야 정상)
python -c "import torch; print(torch.__version__, torch.cuda.is_available(), torch.cuda.get_device_name(0))"
# 기대: 2.4.1+cu121 True NVIDIA A100 80GB PCIe
```
- numpy는 **upper bound 걸지 마라** (torch ABI 깨짐). 로컬 검증값: numpy 2.2.6 OK.

---

## 4. 데이터 다운로드 — 디스크 121GB 한도 (가장 중요)

71667은 zip 단위가 거칠어 **클래스별 선택 불가**. 디스크에 맞춰 **Validation 셋만** 받는다.

| 구분 | filekey | 용량 | 121GB에 맞나 |
|---|---|---|---|
| ❌ Training 이미지 | TS.z01/z02/zip | ~206GB | **안 됨** |
| ✅ **Validation 이미지** | **521779** (VS.zip) | ~26GB | OK |
| ✅ **Validation 라벨** | **521780** (VL.zip) | ~2GB | OK |

```bash
# aihubshell 설치
curl -fsSL -o ~/aihubshell https://api.aihub.or.kr/info/aihubshell.sh
bash ~/aihubshell -mode l -datasetkey 71667   # 파일 목록 확인

# ⚠️ 이미지(521779) + 라벨(521780) 둘 다 받아야 한다. 하나만 받으면 변환 시 "샘플 0건".
bash ~/aihubshell -mode d -datasetkey 71667 -filekey 521779,521780 -aihubapikey '<API_KEY>'
```
- **API 키는 절대 커밋/로그 금지** (UUID 형식, getpass로 입력).
- 다운로드+병합+압축해제에 2~3배 헤드룸 필요 → 28GB 실데이터에 ~80GB 작업공간. 121GB 안에서 OK.
- 받은 위치: `apps/ai/training/datasets/aihub-71667/` (또는 검증용 `Sample/`).

---

## 5. 학습 파이프라인 (Makefile 단축)

```bash
cd apps/ai

# 1) 다운로드 직후 — 레이아웃 확인 (01.원천데이터 / 02.라벨링데이터 폴더 + JSON 개수 > 0)
find training/datasets/aihub-71667 -name "*.json" | head && \
  find training/datasets/aihub-71667 -name "*.json" | wc -l

# 2) JSON → YOLO 변환 (LIMIT으로 양 조절)
make convert-data SOURCE=training/datasets/aihub-71667 LIMIT=5000

# 3) Golden 셋 추출 (split 전, 영구 격리)
make golden

# 4) train/val 분할 (per_colony_time_block 자동 선택)
make split-data

# 5) 학습 (A100이면 batch 64 가능)
make train         # = python -m training.train --config training/configs/yolo.yaml --name v0.1.0-baseline --device 0
#   또는 직접: python -m training.train --config training/configs/yolo.yaml --name v0.1.0-baseline --batch 64 --device 0

# 6) Golden 평가 → eval_golden.json 산출
make eval          # EVAL_RUN=v0.1.0-baseline, --imgsz 640

# 7) CPU 추론용 ONNX export
make export-onnx   # imgsz 640
```

데이터 더 받을 수 있으면 (디스크 늘면): `make convert-data ... LIMIT=50000 && make split-data && make train-extend NAME=v0.1.1-50k`

> **2026-06-08 파이프라인 사전 감사 수정 (PR `feature/ai-v010-pipeline-fixes`)**
> GPU 학습 전 다중 에이전트 감사로 확정 버그 다수를 수정하고 합성 데이터로 전 구간 드라이런 검증 완료:
> - **golden leakage 차단**: `make split-data` 가 `golden/manifest.json` 으로 golden 을 풀에서 자동 제외 + train/val ∩ golden = ∅ 격리 assert. (golden → split 순서만 지키면 됨)
> - **golden `data.yaml` 3-class 정합** (이전 nc:2/varroa_mite → bee_normal/bee_with_varroa/bee_other_disease) + `train:` 키 추가
> - **eval/export imgsz 640** 으로 통일 (이전 Makefile 1280 — 학습과 불일치)
> - **eval 지표 infestation_rate** (이전 VMIR=varroa/normal) — risk.yaml 정의와 일치, 결과 키 `infestation_rate_mae`
> - **`varroa_recall`** 클래스명 `bee_with_varroa` 로 정정 (이전 `varroa_mite` → 항상 None)
> - **`--limit` seed 셔플** (경로정렬 첫 N개 편중 → 대표 샘플), bbox 픽셀공간 clip, 메타 부족 시 random fallback fail-fast, 작은 colony 보정
> - **ultralytics 경로 자동화**: train.py 가 data path 를 절대화(datasets_dir 의존 제거) + project 절대화. 산출물은 `training/runs/yolo/<name>` (gitignored)
>
> → **실데이터(521779+521780) 도착 시 §5 `make` 순서 그대로 실행하면 끝.** (단 `make golden` 은 실데이터에서 기본 `--n-varroa 100 --n-normal 200` 사용)

---

## 6. 산출물 처리 (학습 끝나고)

- **가중치**: `s3://helpbee-models/yolo/v0.1.0/best.pt` (+ `metadata.json`) 업로드. SemVer 규약.
- `*.pt`, `*.onnx`, `runs/`, `wandb/`, datasets raw는 **git 커밋 금지** (`.gitignore` 확인).
- ⏳ **남은 일 (ADR §7)**: `eval_golden.json` 결과를 `apps/ai/training/eval_history/v0.1.0.json`으로
  커밋 → ADR §8 Q4(베이스라인 평가 수치 공란) 해소. 이건 코드/문서 PR이라 GPU 서버 말고 로컬에서 해도 됨.

---

## 7. 미해결 / 게이트 (건드리기 전에 인지)

- **라이선스**: AI Hub 71667 **상용·내국인 사용 제약** 미해결 (ADR §8 Q1). 학습/검증은 진행하되,
  프로덕션 배포 전 법무 확인 필요. v0.2.0의 71488도 동일 게이트.
- **colony 001 dominance (75%)**: 일반화 평가 약함. 베타 양봉가 외부 데이터로 보강 예정.
- **응애 인스턴스 2.4%**: 심각한 imbalance → `yolo.yaml`의 `copy_paste: 0.3` 필수 유지.
- **infestation_rate 임계값(3%/10%)**: VMIR 차용값이라 베타 실측 라벨로 회귀 보정 필요.

---

## 8. 셸/git 안전 규칙 (전역 hook이 강제)

- `rm` 금지 → **`trash`** 사용.
- `git reset --hard`, `git push --force/-f`, `git clean -f`, `git checkout .`, `git branch -D`, `DROP/TRUNCATE` 차단됨.
- `main`/`develop` 직접 push 금지 → `feature/*` 브랜치 → PR (base: `develop`).
- 커밋 메시지 끝: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- PR 본문 끝: `🤖 Generated with Claude Code`

---

## 9. 진행 상태 체크리스트

- [x] ADR-0001 결정 + 코드/문서 정렬 (PR #11 → develop 머지됨)
- [x] 학습 노트북 작성 (`notebooks/train_v0.1.0_aihub71667.ipynb`)
- [x] 앨리스 torch/CUDA 호환 해결 (torch 2.4.1+cu121)
- [ ] **Validation 셋(521779+521780, 28GB) 다운로드** ← 지금 여기
- [ ] 레이아웃 확인 → 변환(LIMIT=5000) → golden → split
- [ ] 학습 → 평가 → ONNX
- [ ] eval_history/v0.1.0.json 커밋 (로컬에서)
- [ ] S3 가중치 업로드
