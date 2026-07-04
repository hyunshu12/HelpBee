# HelpBee AI Service - 단축 명령어
# Usage: make <target>

PY ?= python
APP := app.main:app

.PHONY: help dev test test-regression regression-fixtures lint format \
        convert-data split-data golden \
        train train-resume train-extend eval export-onnx

help:
	@echo "=== Server ==="
	@echo "  dev                 FastAPI 개발 서버 (--reload)"
	@echo "  test                pytest -q (회귀 게이트 제외)"
	@echo "  test-regression     서빙 경로 스냅샷 회귀 게이트 (모델+Sample 필요, 없으면 skip)"
	@echo "  regression-fixtures 회귀 매니페스트 재생성 (프롬프트/모델/risk 의도 변경 후)"
	@echo "  lint                ruff + mypy"
	@echo "  format              ruff format + fix"
	@echo ""
	@echo "=== Data pipeline ==="
	@echo "  convert-data    AI Hub 71667 → YOLO (limit=5000)"
	@echo "  split-data      train/val 분할 (data leakage 방지 자동 전략)"
	@echo "  golden          Golden holdout 셋 추출 (응애 100 + 정상 200)"
	@echo ""
	@echo "=== YOLO training ==="
	@echo "  train           v0.1.0-baseline 학습 (5,000장, 200 epochs, patience 30)"
	@echo "  train-resume    중단된 run 이어 학습 (last.pt + optimizer state)"
	@echo "  train-extend    데이터 추가 후 weight 가져와 새 run (5k → 50k)"
	@echo "  eval            Golden 셋으로 mAP / Recall@varroa / VMIR MAE 평가"
	@echo "  export-onnx     best.pt → best.onnx (CPU 추론용)"

# ===== Server =====
dev:
	uvicorn $(APP) --reload --port 8000

test:
	pytest -q

# 서빙 경로(preprocess→YOLO→risk) 스냅샷. 로컬에 ONNX 모델 + 71667 Sample 있을 때만
# 실제 실행, 없으면 전 케이스 skip (이미지는 라이선스상 미커밋).
test-regression:
	pytest -q -m regression

# 매니페스트 재생성 — 프롬프트/모델핀/risk.yaml 을 "의도적으로" 바꾼 뒤에만.
# created_at 은 date CLI 로 스탬프(선택/기대값은 결정적이라 재실행 byte-identical).
regression-fixtures:
	$(PY) -m training.data.make_regression_fixtures \
		--created-at "$$(date -u +%Y-%m-%dT%H:%M:%SZ)"

lint:
	ruff check . && mypy app training

format:
	ruff format . && ruff check . --fix

# ===== Data pipeline =====
# 변환 파라미터 (override 가능)
#   SOURCE: 71667 다운로드 루트
#   LIMIT : 변환할 최대 이미지 수 (None = 전체)
# 예: make convert-data SOURCE=training/datasets/Sample LIMIT=330
SOURCE ?= training/datasets/aihub-71667
LIMIT ?= 5000

convert-data:
	$(PY) -m training.data.aihub_to_yolo \
		--source $(SOURCE) \
		--output training/datasets/varroa-v1-allraw \
		--split all \
		--limit $(LIMIT)

# 자동 전략 분할 (farm/device/sequence 자동 감지)
# ⚠️ golden 을 먼저 실행할 것 — manifest 기반으로 golden 이미지를 풀에서 제외(leakage 방지).
split-data:
	$(PY) -m training.data.split_strategy \
		--input training/datasets/varroa-v1-allraw \
		--output training/datasets/varroa-v1 \
		--exclude training/datasets/golden/manifest.json \
		--val-ratio 0.2 \
		--seed 42

# Golden 셋 추출 (split-data 전에 실행 — 격리)
golden:
	$(PY) -m training.data.golden_holdout \
		--input training/datasets/varroa-v1-allraw \
		--output training/datasets/golden \
		--n-varroa 100 --n-normal 200 \
		--min-farms 3 --min-devices 2

# ===== YOLO training =====
train:
	$(PY) -m training.train --config training/configs/yolo.yaml

# 중단된 학습 이어가기 (optimizer state 보존)
train-resume:
	$(PY) -m training.train --config training/configs/yolo.yaml \
		--resume training/runs/yolo/v0.1.0-baseline/weights/last.pt

# 데이터 추가 후 재학습 (weight만 가져옴, optimizer는 새로)
# 사용 예: convert-data로 50,000장 새로 만든 후 → make train-extend NAME=v0.1.1-50k
NAME ?= v0.1.1-extended
train-extend:
	$(PY) -m training.train --config training/configs/yolo.yaml \
		--pretrained training/runs/yolo/v0.1.0-baseline/weights/best.pt \
		--name $(NAME)

# Golden 셋 평가 — imgsz 는 학습(yolo.yaml=640)과 일치해야 함
eval:
	$(PY) -m training.eval \
		--weights training/runs/yolo/v0.1.0-baseline/weights/best.pt \
		--golden training/datasets/golden/data.yaml \
		--imgsz 640

# ONNX export — CPU 추론 서버에서 ultralytics 없이 onnxruntime으로 빠른 추론
# imgsz 는 학습(640)과 일치 — 1280 export 는 CPU latency ~4배라 운영 SLA 위반
export-onnx:
	$(PY) -c "from ultralytics import YOLO; \
		YOLO('training/runs/yolo/v0.1.0-baseline/weights/best.pt') \
		.export(format='onnx', dynamic=True, simplify=True, imgsz=640)"
