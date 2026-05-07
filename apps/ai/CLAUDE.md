# apps/ai — HelpBee AI Service (OpenAI Vision + 자체 YOLO)

> 이 문서는 HelpBee 모노레포의 **AI 추론 서비스 도메인** 가이드입니다.
> 두 개의 진단 엔진 — OpenAI Vision(상시) + 자체 YOLO(학습/추론) — 을 한 FastAPI 앱에서 병행 운영합니다.
> Cold-pickup 가능하도록 모든 컨벤션·운영 규칙이 여기 적혀 있습니다.

---

## 1. 목적

HelpBee의 핵심 가치는 **사진 한 장 → 응애(varroa mite) 진단 → 처방·주의사항** 입니다.
이 도메인은 그 진단 엔진을 책임지며, **두 개의 모델을 병행 운영**합니다.

- **OpenAI Vision (5월~상시)** — 베타 출시일부터 사용자에게 즉시 결과 제공
- **자체 YOLO (학습 + 추론)** — 비용 절감, 도메인 정확도 향상, 장기적 모델 주권

두 엔진을 **dual-engine 비교 검증** 으로 운영하며, YOLO 가 OpenAI 대비 동등 이상의 정확도를
달성하면 트래픽을 점진 이관(canary 5% → 100%) 합니다.

---

## 2. 두 서브도메인

### 2-A. OpenAI Vision (상시)
- **모델**: `gpt-4o-mini` 1차, 정확도 부족 시 `gpt-4o` 로 승격
- **응답 SLA**: P95 **5초 내** (preprocess 포함)
- **호출 방식**: Structured Output (`response_format=json_schema`) + Pydantic 파싱
- **장점**: 즉시 운영 가능, 라벨링 불필요
- **단점**: 호출 비용, 외부 의존, latency 분포 넓음

### 2-B. 자체 YOLO (학습 + 추론)
- **베이스라인**: `yolov8s` → 비교군 `yolov8m`
- **데이터**: public 300–500 + 베타 양봉가 기여 + augmentation
  - **베타 시작 전 목표**: 500–1000장 + **2,000+ varroa instances**
- **추론 위치**: MVP 는 같은 FastAPI 컨테이너 안에서 CPU 추론(ONNX) — 별도 GPU 서버 필요 없음
- **학습 위치**: Colab Pro+ A100 (초기) → Lambda Labs / GCP spot (재학습 cron)

---

## 3. 기술 스택

| 영역 | 라이브러리 |
|---|---|
| 웹 프레임워크 | FastAPI + Uvicorn |
| 데이터 검증 | Pydantic v2 |
| 재시도 | tenacity |
| 이미지 전처리 | Pillow (+ pillow-heif HEIC 지원) |
| OpenAI 호출 | `openai` 공식 SDK |
| YOLO 추론·학습 | `ultralytics` + `torch` (CPU/GPU 프로필 분리) |
| Augmentation | `albumentations` |
| 실험 추적 | `wandb` |
| AWS (가중치 S3) | `boto3` |
| 테스트 | `pytest` + `pytest-asyncio` |

requirements 파일은 두 개로 분리합니다:

- `requirements.txt` — OpenAI 개발자용(추론 서버 운영). torch CPU 휠.
- `requirements-gpu.txt` — YOLO 학습자용. torch CUDA + ultralytics + wandb.

---

## 4. 폴더 구조

```
apps/ai/
├── CLAUDE.md                  # 이 문서
├── .gitignore                 # datasets, runs, *.pt, wandb/ 무시
├── requirements.txt           # 추론 서버 (CPU)
├── requirements-gpu.txt       # 학습 (GPU)
├── Makefile                   # train / eval / export-onnx / test 단축
├── app/
│   ├── main.py                # FastAPI 엔트리 (health 등록 완료)
│   ├── core/                  # config, logging, cost-meter, S3 loader
│   ├── routers/               # /analyze, /analyze/yolo, /analyze/dual, /analyze/batch
│   ├── services/              # openai_client.py, yolo_engine.py, preprocess.py, risk.py
│   ├── schemas/               # AnalysisResponse, ImageInput, ErrorEnvelope (Pydantic v2)
│   ├── prompts/               # varroa_prompt.py (프롬프트 단일 소스 + version)
│   └── tests/
│       ├── unit/              # 모킹된 OpenAI 파싱, 전처리, 비용 계산
│       └── fixtures/          # 회귀 테스트용 이미지 + 기대 risk_score JSON
├── training/
│   ├── configs/               # yolo.yaml, risk.yaml (위험도 가중치 튜닝)
│   ├── datasets/              # **git-ignored**, README 만 커밋
│   │   └── README.md
│   └── runs/                  # **git-ignored** (W&B 로컬 캐시, 체크포인트)
└── postman/                   # 수동 호출용 컬렉션
```

---

## 5. API 엔드포인트

| Method | Path | 용도 | 엔진 |
|---|---|---|---|
| GET | `/health` | 헬스체크 | – |
| GET | `/metrics` | Prometheus 메트릭 (latency, cost, error rate) | – |
| POST | `/analyze` | 단일 이미지 진단 | OpenAI |
| POST | `/analyze/yolo` | 단일 이미지 진단 | 자체 YOLO |
| POST | `/analyze/dual` | 두 엔진 **병렬 호출** + 비교 페이로드 반환 | OpenAI ‖ YOLO |
| POST | `/analyze/batch` | 다수 이미지 일괄 진단 (background task) | 라우팅 옵션 |

> 클라이언트(apps/api 백엔드)는 기본적으로 `/analyze` 호출. 내부 검증·dual-engine 비교는
> 별도 어드민 채널에서 `/analyze/dual` 사용.

---

## 6. 응답 스키마 (`AnalysisResponse`)

```python
class AnalysisResponse(BaseModel):
    risk_score: int            # 0~100, clamped
    tier: Literal["safe", "watch", "danger"]   # risk_score 구간 매핑
    estimated_count: int | None                # 추정 응애 수 (없으면 null)
    confidence: float          # 0.0~1.0, 모델 자체 confidence
    recommendations: list[str] # 한국어 처방·주의 문구 (≤5개)

    # 운영 메타
    model_version: str         # "gpt-4o-mini-2024-07-18" 또는 "yolov8s-v0.1.0"
    prompt_version: str | None # OpenAI 만 채움. e.g. "varroa@1.3"
    latency_ms: int
    cost_estimate_usd: float | None  # OpenAI 만 채움
    raw_payload: dict          # 디버그용 원본 응답 (DB 미저장 옵션)
```

응답 실패는 **에러를 던지지 않고** `risk_score=null`, `tier="watch"`, `recommendations=["AI 분석 실패"...]`,
`raw_payload.error_reason` 채워서 200 으로 반환 (UX 차단 방지). 진짜 4xx/5xx 는
입력 검증 실패·인증 실패에만 사용.

---

## 7. OpenAI 통합 원칙

### 7-1. 모델 핀
- `gpt-4o-mini` 의 정확한 스냅샷 ID(`gpt-4o-mini-2024-07-18` 등)를 `OPENAI_MODEL` env 로 핀
- 승격 결정: golden 셋(§8) 기준 mAP·F1 차이 > 5pp 이고 비용 차이 허용 가능할 때 `gpt-4o`

### 7-2. Structured Output
- `response_format={"type": "json_schema", "json_schema": {...}}` 강제
- 스키마는 Pydantic 모델에서 자동 생성 (`AnalysisOpenAIRaw.model_json_schema()`)
- 파싱 실패 시 1회 재시도 → 그래도 실패면 §6 의 graceful null

### 7-3. 프롬프트
- **단일 소스**: `app/prompts/varroa_prompt.py` 의 `VARROA_PROMPT` 상수
- **버전 핀**: 같은 파일에 `PROMPT_VERSION = "varroa@1.3"` 상수, 응답에 그대로 echo
- **Few-shot**: 3–5장의 base64 inline 이미지 (현장 사진 우선, 변종 케이스 포함)
  - 라이센스 OK 한 사진만 인라인. 데이터셋 전체는 OpenAI 호출에 포함 금지

### 7-4. 전처리 (`services/preprocess.py`)
1. EXIF orientation 적용 후 strip
2. RGBA → RGB 평탄화
3. HEIC → JPEG (`pillow-heif`)
4. 긴 변 1024px 다운스케일 (`Image.LANCZOS`)
5. JPEG quality=85 인코딩
6. **10MB 가드** — 초과 시 q=80, 75 순차 다운, 그래도 초과면 400

### 7-5. 재시도·타임아웃
- `tenacity` 지수 백오프 `wait_exponential(min=1, max=8)`, `stop_after_attempt(3)`
- 전체 호출(전처리 포함) **30초 하드 타임아웃**
- 실패 카테고리별 처리:
  - 429 / 5xx → 재시도
  - 4xx (잘못된 이미지) → 재시도 안 함, graceful null
  - 타임아웃 → graceful null

### 7-6. 비용 추적
- `response.usage.{input_tokens, output_tokens, cached_tokens}` → USD 환산
- 토큰 단가는 `app/core/openai_pricing.py` 표 (모델별)
- 호출당 비용을 백엔드(`apps/api`)로 콜백 (`POST /internal/ai-cost`)
- **Monthly budget guard**: 누적 비용 > `OPENAI_MONTHLY_BUDGET_USD` 면 `503 Service Unavailable`

---

## 8. YOLO 파이프라인 원칙

### 8-1. 모델
- 베이스라인 `yolov8s`, 비교 `yolov8m`
- `imgsz=640`, `conf=0.25`, `iou=0.5` (운영 기본값, configs/yolo.yaml 에서 오버라이드)

### 8-2. 데이터
- **v0.1.0 주 데이터셋**: **AI Hub 71667 (꿀벌 질병 진단 이미지 데이터)** — 312,000장 / 1,171,779 인스턴스
  - 상세·스키마·매핑·통계·제약 모두: **[apps/ai/training/datasets/AIHUB_71667.md](training/datasets/AIHUB_71667.md)**
  - 71667 7-class → 우리 3-class (`bee_normal` / `bee_with_varroa` / `bee_other_disease`) 매핑은
    `training/data/aihub_to_yolo.py:CLASS_MAPPING` 단일 소스
  - ⚠️ Q3 라벨 케이스 = B (응애 자체 bbox 없음, "감염된 벌 영역"). VMIR 직접 계산 불가 →
    `infestation_rate` 사용 (`training/configs/risk.yaml`)
- **외부 데이터 (베타)**: 베타 양봉가 사진 + Roboflow / Kaggle 변종 — 일반화 평가 + golden 셋 교체
- **베타 진입 게이트**: 500–1000장 + **2,000+ varroa instances** + golden 300장 holdout 통과
- **Augmentation (albumentations / Ultralytics 내장)**: HFlip, Rotate(±15°), HSV jitter, Cutout,
  MotionBlur, RandomShadow, **Copy-Paste (응애 인스턴스 imbalance 대응 핵심)**
  - 상세 카운트(밀도 정확도) 영향 줄 수 있는 transform 은 train only

### 8-3. 라벨링 SOP
- **도구**: Roboflow (cross-labeling 활성화)
- **합의 기준**: 2명 라벨러 IoU ≥ 0.7 → auto-merge, 미만 시 **수의학자 검수**
- **Golden 셋**: 100장 검증 전용, 학습/aug 에 절대 포함 금지, 모든 모델 버전 동일 셋으로 비교

### 8-4. 학습
- 진입점: `python -m training.train --config training/configs/yolo.yaml`
- 추적: W&B (`wandb.init(project="helpbee-yolo", config=cfg)`)
- 버전 컨벤션: **SemVer** `vMAJOR.MINOR.PATCH`
  - PATCH = 데이터 추가만 (재학습 cron)
  - MINOR = 하이퍼파라미터·아키텍처 변경
  - MAJOR = 클래스·태스크 변경

### 8-5. Compute
- 초기 학습: **Colab Pro+ A100** (인터랙티브, 비용 예측 쉬움)
- 재학습 cron: **Lambda Labs spot** 또는 **GCP A100 spot**
- **자동 terminate**: 학습 스크립트 마지막에 `gcloud compute instances delete $HOSTNAME --quiet` 보장
- 추론: MVP **CPU(ONNX)** 한 컨테이너. 트래픽 증가 시 별도 GPU 추론 서버로 분리

### 8-6. 가중치 (S3)
- 경로: `s3://helpbee-models/yolo/v{X.Y.Z}/best.pt` (+ `metadata.json`)
- 부팅 시: env `YOLO_MODEL_VERSION` 읽고 로컬 캐시 → 없으면 S3 다운로드
- 캐시 위치: `/var/cache/helpbee/yolo/v{X.Y.Z}/best.pt` (Docker volume)

### 8-7. 배포 (Blue-Green Canary)
- 새 버전 배포 시 트래픽 **5% canary** → 메트릭 1주 확인 → 100% promote
- 메트릭: golden mAP, P95 latency, fp/fn 비율 (양봉가 피드백)
- 롤백: env 한 줄 변경(`YOLO_MODEL_VERSION=v0.1.0`) + 재시작

### 8-8. 위험도 산출 (`services/risk.py`)
```
risk_score = clamp(0, 100, mite_density * K_density + mite_count * K_count)
tier       = "safe"   if risk < 30
             "watch"  if risk < 70
             "danger" otherwise
```
- `K_density`, `K_count`, 임계값은 `training/configs/risk.yaml` 에서 튜닝
- 양봉가·수의학자 라벨링한 risk 라벨로 회귀 학습 후 가중치 갱신

### 8-9. 재학습 루프
- 베타 사용자가 "오진" 신고 → `feedback_queue` 에 누적
- **주 1회 cron**: 신규 라벨 100장 누적 시 patch 재학습 트리거
- 재학습 → golden 셋 통과 시 자동 staging 배포 → 사람 승인 후 prod canary

---

## 9. 로컬 개발

### 9-1. 환경 셋업
```bash
cd apps/ai
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt          # OpenAI 개발자
# 또는
pip install -r requirements-gpu.txt       # YOLO 학습자
```

### 9-2. 서버 실행
```bash
uvicorn app.main:app --reload --port 8000
# Health: curl http://localhost:8000/health
```

### 9-3. Makefile 단축
```
make train        # python -m training.train --config training/configs/yolo.yaml
make eval         # golden 셋으로 mAP/P/R 측정
make export-onnx  # best.pt → best.onnx (CPU 추론용)
make test         # pytest -q
make lint         # ruff + mypy (둘 다 strict)
```

### 9-4. 환경 변수 (.env.example)
```
OPENAI_API_KEY=sk-...
OPENAI_MODEL=gpt-4o-mini-2024-07-18
OPENAI_MONTHLY_BUDGET_USD=200
YOLO_MODEL_VERSION=v0.1.0
AWS_REGION=ap-northeast-2
AWS_S3_MODELS_BUCKET=helpbee-models
WANDB_API_KEY=...
HELPBEE_API_INTERNAL_URL=http://api:3000
```

---

## 10. 테스트

### 10-1. 단위 테스트 (`app/tests/unit/`)
- **OpenAI 파싱**: 정상 / 스키마 위반 / 부분 누락 응답 모킹 → 우리 schema 변환 확인
- **전처리**: HEIC 변환, EXIF strip, 1024 다운스케일, 10MB 가드, RGBA → RGB
- **비용 계산**: usage 토큰 → USD 환산 표 매핑

### 10-2. 회귀 테스트 (`app/tests/fixtures/`)
- 20–30장 fixture 이미지 + 기대 `risk_score` JSON
- **회귀 게이트**: 다음 변경 시 반드시 통과해야 함
  - 프롬프트 변경 (`prompt_version` bump)
  - OpenAI 모델 핀 변경
  - YOLO 가중치 버전 변경
  - 위험도 가중치(`risk.yaml`) 변경
- 허용 오차: `abs(expected - actual) <= 10` (tier 변경은 0 허용)

### 10-3. 실행
```bash
pytest -q                      # 전체
pytest -q app/tests/unit       # 단위만
pytest -q -m regression        # 회귀만
```

---

## 11. packages 의존성

- 이 도메인은 **apps/api 와 HTTP 통신만** 합니다.
- **DB(postgres)에 직접 접근하지 않습니다** — 모든 영속화는 백엔드를 거칩니다.
- 공유 타입은 `packages/types` (Zod) → 필요시 우리 쪽에서 Pydantic 으로 미러
  (Pydantic ↔ Zod 자동 동기화는 하지 않음, 수동 미러 + 회귀 테스트로 보호)
- 비용/메트릭 콜백: `POST {HELPBEE_API_INTERNAL_URL}/internal/ai-cost` (mTLS 또는 internal token)

---

## 12. AI 작업 가이드라인 (Claude/사람 공통)

### 변경 시 반드시 챙길 것
- **프롬프트 변경 시** → `PROMPT_VERSION` 상수 bump + 회귀 테스트 재실행 + golden 셋 비교
- **OpenAI 모델 변경 시** → `OPENAI_MODEL` 핀 ID 변경, 비용 표 갱신, golden 회귀
- **YOLO 가중치 변경 시** → SemVer 따라 S3 업로드, `metadata.json` 같이 올림, canary 5% 부터
- **위험도 가중치 변경 시** → `risk.yaml` PR 에 회귀 diff 첨부

### 데이터 / 산출물 관리
- **`training/datasets/` 의 raw 파일은 절대 git commit 금지** (`.gitignore` 확인)
- **학습 산출물 금지 커밋**: `*.pt`, `*.onnx`, `training/runs/`, `wandb/`
- **GPU spot 학습 후 자동 terminate** 스크립트 항상 사용 (비용 사고 방지)

### 셸 컨벤션
- `rm` 금지 → **`trash`** 사용 (복구 가능)
- `git reset --hard`, `git push --force` 사용 시 사용자 확인 필수

### 코드 컨벤션
- Python 3.11+, Pydantic v2 only (v1 `.dict()` / `.parse_obj` 금지)
- 모든 외부 호출은 `tenacity` + 명시적 timeout
- 비밀값은 env 만, 코드/로그에 평문 금지
- 라우터에서 직접 `openai.*`/`ultralytics.*` 호출 금지 → 반드시 `services/` 경유

---

## 📋 개발 계획 (마스터 플랜 발췌)

### API 엔드포인트
| 메서드/경로 | 설명 |
|---|---|
| GET /health | OpenAI 연결 체크 포함 |
| GET /metrics | Prometheus 호환 텍스트 (누적 토큰/비용) |
| POST /analyze | OpenAI 단독 진단 (multipart 또는 {image_url}) |
| POST /analyze/yolo | 자체 YOLO 추론 ({boxes, count, risk_score, model_version, latency_ms}) |
| POST /analyze/dual or /analyze/compare | OpenAI + YOLO 병렬 (asyncio.gather, 베타 검증) |
| POST /analyze/batch | 최대 10장 동시 (rate limit 고려) |

### AnalysisResponse 스키마
```
risk_score: int (0-100)
tier: Literal["safe","caution","warning","critical"]
estimated_count: int
confidence: float (0-1)
recommendations: list[str]   # 한글
model_version: str           # "gpt-4o-mini-2024-07-18"
prompt_version: str          # "v1.2"
latency_ms: int
cost_estimate_usd: float
raw_payload: dict | None
```

### OpenAI 통합 정책
- **모델**: gpt-4o-mini 1차 (~$0.001/이미지) → 정확도 부족 시 gpt-4o 승격
- **Structured Output**: response_format=json_schema + Pydantic
- **프롬프트**: prompts/varroa_prompt.py 단일 소스. system은 양봉 전문가 페르소나(영문), user는 한글 권장 조치 요청. Few-shot 3-5장(safe/caution/critical) base64 inline. prompt_version 응답 포함
- **전처리**: Pillow longest 1024px 다운스케일, JPEG q=85, EXIF strip, RGBA→RGB, HEIC→JPEG, 10MB 가드
- **재시도**: tenacity 지수 백오프 max 3, 30s 하드 타임아웃, 실패 시 null result + reason (에러 아님)
- **비용**: response.usage 토큰 → USD 환산 → 백엔드 콜백 + 월 예산 초과 시 503 BUDGET_EXCEEDED

### YOLO 파이프라인 정책
- **모델**: YOLOv8s 베이스라인 → yolov8m 비교 (Ultralytics 안정성). v11 실험적
- **데이터셋**: public(Roboflow varroa, BeeAlert) 300-500 + 베타 양봉가 3명 + augmentation. 베타 시작 전 500-1000장 + varroa instances 2000+
- **라벨링**: Roboflow + 2명 cross-labeling IoU≥0.7, 미만 수의학자 검수, golden 100장 holdout
- **학습**: train.py CLI + configs/yolo.yaml + W&B tracking + SemVer 버전 (0.1.0 베이스라인)
- **Compute**: Colab Pro+ A100, retrain은 Lambda Labs (~$1.10/h) or GCP A100 spot
- **추론**: lazy-load, env YOLO_DEVICE=cuda|cpu, GPU 미가용 시 CPU 자동. 목표 latency: GPU <500ms, CPU <2s (yolov8s)
- **위험도 산출**: `risk = clamp(0,100, mite_density * K + count_weight * mite_count)`. K, count_weight, 임계 구간은 configs/risk.yaml에서 튜닝
- **모델 저장**: S3 helpbee-models/yolo/v0.1.0/best.pt versioning. env YOLO_MODEL_VERSION 부팅 시 다운로드. Blue-green canary 5% → 100%
- **재학습 루프**: feedback_queue → 주 1회 cron → 100장 누적 시 patch retrain (v0.1.x)

### 마일스톤
- **5월 W1**: /analyze stub + 프롬프트 프로토타입 + 수동 curl. 동시에 public dataset + Roboflow workspace + 라벨링 가이드 PDF
- **5월 W2**: structured output Pydantic, 전처리 완성. yolov8s 베이스라인 학습 (public only), mAP 측정
- **5월 W3**: dual-engine endpoint, YOLO bridge 인터페이스 합의. /analyze/yolo 통합 + S3 weight 파이프라인
- **5월 W4**: cost tracker, 회귀 테스트, 백엔드 E2E. /analyze/compare + 베타 양봉가 데이터 수집 시작
- **6월**: 라벨링 + iterate (v0.2.0)
- **7-8월**: 베타 retraining loop, 50+ 실 이미지, 90% 정확도 게이트

### 검증
- pytest unit (mocked OpenAI 파싱, 전처리, 비용 계산)
- 회귀 테스트셋 fixture (20-30장 + 기대 risk_score JSON) — CI 게이트
- mAP@0.5 ≥ 0.85, mAP@0.5:0.95 ≥ 0.6 (100장 holdout)
- Latency p50/p95 (GPU/CPU)
- Beta report: OpenAI vs YOLO confusion matrix, 비용 비교, FN 분석

### 리스크 / 미해결
- 한국 양봉 환경 이미지 부족 → few-shot에 현장 사진 우선 / 베타 후 fine-tuning 검토
- OpenAI silent 모델 업데이트 → model_version 핀 + 회귀 게이트 필수
- 비용 스파이크 → 백엔드 rate limit + AI budget guard 이중화
- 한글 권장 조치 일관성 → recommendations enum화 + 매핑 (LLM 자유 생성 최소화)
- 양봉가 협조 실패 시 public data 의존 → 일반화 약화
- 수의학자 검수비 미산정 (월 50-100만원 예상)
- GPU 비용: 학습당 $20-50, 월 5회 sweep 시 $200-300
- CPU에서 yolov8m 이상 2s 초과 → ONNX export + quantization 필요
- Class imbalance → weighted loss / oversampling

### 다른 분야와의 인터페이스 (정합 포인트)
- **← Backend API** (@apps/api): HTTP만 (DB 직접 접근 X). 응답 스키마 변경 시 apps/api/src/services/ai-client.ts + 클라이언트(@apps/mobile, @apps/admin) 동기화
- **→ DB** (@packages/database): 직접 접근 없음. ai_models 테이블 메타는 백엔드를 통해 조회
- **모델 가중치 ↔ S3** (@infra): helpbee-models 버킷 versioning, env로 버전 핀

---

## 13. 회귀 게이트 체크리스트

PR 머지 전 다음 중 해당하는 항목 **모두** 체크:

- [ ] 프롬프트 변경했는가 → `PROMPT_VERSION` bump 했는가?
- [ ] OpenAI 모델 변경했는가 → 비용 표(`openai_pricing.py`) 갱신했는가?
- [ ] YOLO 가중치 변경했는가 → S3 업로드 + `metadata.json` 작성했는가?
- [ ] 위험도 공식·가중치 변경했는가 → golden 셋 회귀 diff 첨부했는가?
- [ ] 회귀 테스트 통과(`pytest -q -m regression`)했는가?
- [ ] golden 셋 mAP / risk 정확도가 이전 버전 대비 ≥ 동등한가?
- [ ] 비용·latency 메트릭 회귀 없는가? (P95 latency, $/req)
- [ ] `.gitignore` 가 새 산출물 패턴 커버하는가? (raw 데이터, 가중치 누수 방지)

---

## 참고

### 데이터셋
- **AI Hub 71667 (v0.1.0 주 데이터셋)**: [training/datasets/AIHUB_71667.md](training/datasets/AIHUB_71667.md) ★ cold-pickup 필독
- **공개 데이터 보강**: BeeImage, Kaggle varroa, Roboflow varroa workspace
- **외부 베타 데이터**: 베타 양봉가 3명 사진 (Phase 2)

### 학습 인프라
- 학습 config: [training/configs/yolo.yaml](training/configs/yolo.yaml)
- 모델 정의 (P2 head): [training/configs/yolov11s-p2.yaml](training/configs/yolov11s-p2.yaml)
- 데이터셋 config: [training/configs/dataset.yaml](training/configs/dataset.yaml)
- 위험도 정의: [training/configs/risk.yaml](training/configs/risk.yaml)
- 변환 / 분할 / golden: [training/data/](training/data/)
- 학습 / 평가 진입점: [training/train.py](training/train.py), [training/eval.py](training/eval.py)
- 단축 명령: [Makefile](Makefile)

### 외부
- 상위 계획: `~/.claude/plans/refactored-percolating-church.md`
- AI YOLO 설계 결정 로그: `~/.claude/plans/ai-linked-prism.md`
- S3 가중치 버킷: `helpbee-models`
- W&B 프로젝트: `helpbee-yolo`
- Roboflow 프로젝트: (URL은 시크릿/팀위키)
- KCI 논문 (참고): "A YOLOv8-Based Two-Stage Framework for Non-Destructive Detection of
  Varroa destructor Infestations in Apis mellifera Colonies" (Lee et al., JKSCI 2024.10)
