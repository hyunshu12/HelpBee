# CLAUDE.md

> **Level: Enterprise** | Initialized: 2026-04-09 | bkit v2.1.1

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## 🚨 GitHub 커밋/PR 규칙 (Claude 필독)

### 브랜치 보호 규칙
- `main`, `develop` 브랜치는 **직접 push 금지** (branch protection 적용)
- 모든 변경은 반드시 **feature 브랜치 → PR → 머지** 순서로 진행

### Claude가 커밋/push 요청을 받으면
1. **feature 브랜치 생성** (현재 브랜치가 feature/* 가 아닌 경우)
   ```bash
   git checkout -b feature/{작업내용}
   ```
2. **커밋**
   ```bash
   git add <파일>
   git commit -m "feat/fix/chore: 설명"
   ```
3. **feature 브랜치 push**
   ```bash
   git push origin feature/{작업내용}
   ```
4. **PR 생성** (`feature/*` → `develop`)
   - GitHub MCP(`mcp__github__create_pull_request`) 사용
   - `base: develop`, `head: feature/{작업내용}`

### 브랜치 네이밍
| 유형 | 패턴 | 예시 |
|------|------|------|
| 기능 | `feature/{name}` | `feature/user-auth` |
| 버그 수정 | `bugfix/{name}` | `bugfix/image-upload` |
| 문서 | `docs/{name}` | `docs/api-guide` |
| 긴급 수정 | `hotfix/{name}` | `hotfix/api-crash` |

### 커밋 메시지 규칙
```
feat: 새 기능
fix: 버그 수정
chore: 빌드/설정 변경
docs: 문서
refactor: 리팩토링
```

---

## 🧪 2026-07-04 전체 시스템 점검 결과 & 개선 계획 (다음 Claude 필독 ★)

> 2026-07-04에 로컬에서 앱·웹·백엔드 전체를 실제 구동/테스트한 결과와, 안 되는 부분의 근본 원인 + 상세 개선 계획.
> **새 세션에서 작업을 시작하면 이 섹션과 `docs/05-implementation/README.md` 인덱스를 먼저 읽을 것.**
> 로컬 환경: Docker 미설치. brew Postgres 16 + Redis 7 상시 가동. `apps/api/.env`, `apps/ai/.env` 구성 완료(gitignored).

### A. 초기 계획 대비 진행 현황 (도메인별)

| 도메인 | 계획 (마일스톤) | 현재 상태 | 판정 |
|---|---|---|---|
| DB (`packages/database`) | 5월 W1~W4: 9테이블 + dual-engine | ✅ 완료. 9테이블·마이그레이션·시드 정상 (PR ~#22까지) | **완료** |
| Backend API (`apps/api`) | 5월 W1~W4: auth/hives/images/analyses/subs/admin | ✅ 코드 완성 + 계약 고정. vitest **166/166 PASS**, type-check PASS | **완료** |
| AI (`apps/ai`) | 5~6월: OpenAI + YOLO dual | 🟡 YOLO v0.1.0 학습·ONNX 서빙 완료(decode/전처리 수정 PR #24/#25 **머지됨**). pytest 65/65 PASS. OpenAI 엔진은 `OPENAI_API_KEY` 미설정(유료 폴백용, 현재 불필요). **회귀 fixture 부재** | **핵심 동작** |
| Mobile (`apps/mobile`) | 5월 W1~W4 + 6월 베타 | ✅ 인증→벌통 CRUD→카메라→분석→레포트 전 플로우 구현 (PR #26~#31 머지). dart analyze 0 issues | **MVP 완료** |
| Web (`apps/web`) | 5~6월: 랜딩 + 블로그 | 🟡 MVP 구현 완료, **PR #33 OPEN 미머지** (브랜치 `feature/web-frontend-mvp`). build 25페이지 SSG green, 라이브 서빙 정상 | **머지 대기** |
| Admin (`apps/admin`) | 5월 W3~6월 | ❌ **미착수** — `src/` 전체가 `.gitkeep` 스캐폴드만 존재 | **미착수** |
| Infra (CI/CD, Terraform) | 5월 W2~: ci.yml, staging | ❌ **미착수** — `.github/workflows/` 없음, `infra/terraform/envs/*` 빈 폴더 | **미착수** |

### B. 실제 구동 테스트 결과 (2026-07-04)

**정상 동작 확인 (라이브 E2E):**
1. API 서버 기동(:3001) + AI 서버 기동(:8000) — health OK
2. `POST /v1/auth/login` (시드 `beekeeper1@helpbee.local` / `helpbee-dev-2026`) → 토큰 발급 ✅
3. `GET /v1/hives`, `GET /v1/subscriptions/me`, `GET /v1/subscriptions/plans` ✅
4. **진단 E2E 전체 성공**: presign → S3 직접 PUT(200) → confirm(width/height 추출) → `POST /v1/analyses` → **YOLO 추론 성공** (응애 샘플 이미지 → `risk 70 / warning / infestation_rate 100%`, latency 197ms) ✅
5. `GET /v1/analyses?hiveId=`, `GET /v1/analyses/trend` (일별 avgRisk 버킷) ✅
6. Web: `pnpm --filter @helpbee/web build` 25/25 SSG + dev 서버에서 `/ko`, `/ko/pricing`, `/ko/contact` 200 + SEO 메타 정상 ✅
7. `@helpbee/ui` vitest 12/12, `apps/ai` pytest 65/65, `apps/api` vitest 166/166 ✅

**실패/미동작 발견 (아래 C의 개선 계획과 번호 연동):**
| # | 증상 | 근본 원인 |
|---|---|---|
| 1 | `pnpm --filter @helpbee/api dev`가 즉시 크래시 (`[config] invalid environment`) | dev 스크립트(`tsx watch`)가 `.env`를 자동 로드하지 않음. AI 서버(uvicorn)도 동일 — env 없이 띄우면 HMAC 401로 분석 전부 실패 |
| 2 | 실패한 분석 재시도 불가 | `UNIQUE(image_id, model_id)` + 라우트가 기존 row를 그대로 반환 → `ai_unavailable`로 한 번 실패한 이미지는 **영구 실패** (재분석 경로 없음) |
| 3 | `POST /v1/inquiries` → 404 | 백엔드에 라우트 자체가 없음 → 웹 문의 폼이 붙을 곳이 없음 |
| 4 | `pnpm --filter @helpbee/web lint` FAIL | `apps/web`에 ESLint config 부재 → `next lint`가 인터랙티브 프롬프트에서 죽고, `next build`는 lint를 조용히 skip (품질 게이트 구멍) |
| 5 | 신규 가입자는 분석 불가 | 이메일 인증 발송 미구현 → `emailVerified:false` → 분석 차단. 시드 계정만 동작 |
| 6 | 분석 응답에 `recommendations` 없음 | AI/백엔드 모두 처방 문구 미생성 → 모바일 결과 화면의 "권장 조치" 영역 비어 있음 (핵심 가치 미완) |
| 7 | `flutter test` 실행 불가 (이 Mac) | **환경 문제**: Xcode 라이선스 미동의. `sudo xcodebuild -license accept` 실행 필요 (사용자 액션). 코드 자체는 analyze 0 issues |
| 8 | AI 회귀 게이트 없음 | `pytest -m regression` → 0 selected. `app/tests/fixtures/` 비어 있음 (CLAUDE.md에 명시된 20~30장 fixture + 기대 risk JSON 미구축) |
| 9 | `estimated_varroa_count`가 항상 null | 데이터셋 라벨 특성(응애 자체 bbox 없음, AIHUB_71667.md §6) — **알려진 제약**, 버그 아님 |

### C. 개선 계획 (우선순위·상세 절차 포함)

> 각 항목은 독립 PR로 진행. 브랜치/PR 규칙은 위 "GitHub 커밋/PR 규칙" 준수. PR 머지 시 `docs/05-implementation/`에 기록 추가 의무.

#### P0-1. 실패 분석 재시도 경로 (B-2) — 사용자 가치 직결
- **문제**: AI 서버 순단 시 그 이미지는 영원히 `failed`. 모바일에서 "다시 시도" 불가.
- **수정 위치**: `apps/api/src/routes/analyses.ts` (+ `packages/database/src/queries/analyses.ts`)
- **방안**: `POST /v1/analyses`에서 기존 row가 `status='failed'`면 반환하지 말고 **재추론 후 해당 row를 UPDATE** (upsert-on-failed). `status='success'`/`pending`일 때만 기존 row 반환. 동시성은 `pending` 마킹 후 추론으로 방어.
- **검증**: vitest에 "failed row 재요청 → 재추론 → success 전환" 테스트 추가. Bruno 요청 갱신.

#### P0-2. dev 서버 .env 자동 로드 (B-1) — 모든 후속 작업의 발목
- **수정 위치**: `apps/api/package.json` dev 스크립트 → `tsx watch --env-file=.env src/index.ts` (Node 20.6+ 지원). AI는 `apps/ai/app/core/config.py`에 `python-dotenv` 도입(`load_dotenv()` — 이미 설정된 env 우선) 또는 `Makefile`에 `make serve` 타깃 추가(`set -a; source .env`).
- **검증**: 루트에서 `pnpm --filter @helpbee/api dev` 단독 실행이 성공해야 함. 각 앱 CLAUDE.md의 로컬 기동 명령 갱신.

#### P0-3. recommendations(권장 조치) 파이프라인 (B-6) — 핵심 가치 완성
- **방안(순서대로)**:
  1. `apps/ai/app/services/risk.py`에 tier별 한국어 권장 조치 **정적 매핑** 추가 (LLM 자유 생성 아님 — apps/ai CLAUDE.md "recommendations enum화" 방침 준수). 예: danger → ["즉시 개미산/옥살산 처리 검토", "격리 및 수의사 상담", ...]
  2. AI 응답 `recommendations` 채우기 → `apps/api/src/services/ai-client.ts`는 이미 필드 수용함 → 라우트에서 `recommendations` 테이블에 insert (`packages/database/src/schema/recommendations.ts` 이미 존재).
  3. `GET /v1/analyses/:id` 응답에 recommendations join 포함 → `apps/mobile/lib/features/analyses/` DTO에 반영.
- **검증**: E2E — 응애 이미지 분석 → 응답에 한국어 권장 조치 1~3개 포함. pytest에 tier→문구 매핑 단위 테스트.

#### P1-1. `/v1/inquiries` 라우트 신설 (B-3) — 웹 PR #33 후속
- **수정 위치**: `apps/api/src/routes/inquiries.ts`(신규) + `apps/api/src/schemas/inquiries.ts` + `packages/database/src/schema/inquiries.ts`(신규 테이블: id, name, email, message, createdAt) + 마이그레이션 generate
- **정책**: 🔓 익명 허용 + 레이트리밋 강화(IP당 5/hour) + zod 검증(이메일 형식, message ≤2000자). 응답 `{data:{id}}`.
- **후속**: `apps/web/src/app/[locale]/contact/` 폼을 이 엔드포인트에 연결 (react-hook-form + zod, 이미 폼 UI 존재).
- **검증**: vitest + Bruno + 웹에서 실제 제출 1회.

#### P1-2. 웹 PR #33 머지 + ESLint config (B-4)
- PR #33 리뷰/머지 먼저 (25 SSG green, type-check PASS 확인됨).
- `apps/web/.eslintrc.json` 추가: `{"extends": "next/core-web-vitals"}` → `pnpm --filter @helpbee/web lint` 통과 확인. admin도 같은 시점에 동일 config 준비.

#### P1-3. AI 회귀 테스트 fixture 구축 (B-8)
- **수정 위치**: `apps/ai/app/tests/fixtures/` + `pytest.ini`(marker 등록)
- **방안**: AIHUB Sample 330장에서 20~30장 선별(응애/정상/질병 골고루, golden 셋과 중복 금지) → 각각 현재 v0.1.0 모델의 risk_score를 기록한 `expected.json` 생성 → `@pytest.mark.regression` 테스트가 `abs(expected-actual) <= 10`, tier 변동 0 검증.
- **주의**: fixture 이미지 git 커밋 여부는 라이선스 확인 후 결정(AI Hub 내국인 제약). 커밋 불가 시 로컬 경로 참조 + CI에서는 skip 마킹.

#### P1-4. 이메일 인증 발송 (B-5) — 베타 온보딩 전 필수
- **방안**: AWS SES(ap-northeast-2) sandbox로 시작. `apps/api/src/services/email-service.ts` 신규 → signup 시 서명 토큰(만료 24h) 포함 인증 링크 발송 → `GET /v1/auth/verify-email?token=` 라우트 → `email_verified_at` UPDATE + audit_log.
- **임시 우회(개발)**: `docs/01-development/frontend-api-integration.md` §10의 DB 직접 UPDATE 방법 유지.

#### P2-1. Admin 대시보드 착수 (A표 참조) — 백엔드 `/v1/admin/*`은 이미 완성
- 시작 순서(apps/admin/CLAUDE.md 마일스톤 준수): ① 로그인+middleware(role=admin) ② `/users` 목록(TanStack Table) ③ KPI 대시보드 ④ `analyses/:imageId/dual` 비교 뷰(BboxOverlay).
- admin 토큰은 일반 signup으로 못 만듦 — 시드 `admin@helpbee.local` / `helpbee-dev-2026` 사용.

#### P2-2. CI 파이프라인 (A표 참조)
- `.github/workflows/ci.yml`: pnpm install → `turbo run lint type-check test` + `apps/ai` pytest. **주의**: API vitest는 Docker 불필요(in-process 확인됨)이므로 GitHub Actions에서 바로 동작. Flutter는 별도 job(`flutter analyze` + `flutter test`).
- 이후 gitworkflow.md의 deploy-staging/production은 인프라(Terraform) 진행과 함께.

#### P2-3. 환경 문제 (이 Mac, 사용자 액션 필요)
- `sudo xcodebuild -license accept` 실행해야 `flutter test` 가능 (objective_c 패키지 build hook이 빈 sdk-path에 크래시).
- pydantic 경고(`model_version` protected namespace)는 `app/schemas/`의 해당 모델에 `model_config = ConfigDict(protected_namespaces=())` 한 줄로 제거 가능 (사소).

### D. 테스트 재현 방법 (다음 세션용 요약)

```bash
# 서버 기동 (env 수동 로드 필요 — P0-2 해결 전까지)
cd apps/api && set -a && source .env && set +a && pnpm dev          # :3001
cd apps/ai  && set -a && source .env && set +a && ./.venv/bin/python -m uvicorn app.main:app --port 8000

# 시드 계정: beekeeper1@helpbee.local / admin@helpbee.local, 비밀번호 helpbee-dev-2026
# E2E: login → /v1/images/presign → S3 PUT → /v1/images/confirm → POST /v1/analyses
# 테스트 이미지: apps/ai/training/datasets/Sample/01.원천데이터/유충/유충_응애/**/*.jpg
# YOLO 모델 캐시: ~/.cache/helpbee/yolo/v0.1.0/best.onnx (없으면 S3 helpbee-models에서 다운로드)
```

---

## 🎯 프로젝트 개요

**HelpBee**: AI 기반 스마트 양봉 진단 SaaS 플랫폼

- **목표**: 2025년 6월 MVP 출시
- **고객**: 한국의 중형 양봉가 (200~500통)
- **핵심 가치**: 벌통 이미지 → AI 분석 → 바로아 응애 감염 진단 리포트
- **기술**: 모노레포 (Turborepo), 풀스택 (Next.js, Hono, FastAPI)

---

## 📁 모노레포 구조 이해

### 전체 아키텍처

이것은 **Turborepo 모노레포**입니다. 단일 Git 저장소에서 4개의 독립적 앱 + 4개의 공유 패키지를 관리합니다.

```
┌─────────────────────────────────────────────────┐
│  User Browser                                   │
├─────────────────────────────────────────────────┤
│  apps/web              apps/admin              │
│  (Next.js 사용자웹)    (Next.js 관리자)        │
└────────────────┬─────────────────────────────┘
                 │
    ┌────────────▼────────────┐
    │  apps/api (Hono.js)    │
    │  핵심 비즈니스 로직     │
    ├────────────┬───────────┤
    │            │           │
    ▼            ▼           ▼
  PostgreSQL  Redis   apps/ai (FastAPI)
              ↓              ↓
         @helpbee/      OpenAI API
         database

공유 패키지:
├─ @helpbee/types (타입)
├─ @helpbee/ui (컴포넌트)
├─ @helpbee/database (DB 스키마)
└─ @helpbee/config (설정)
```

### 각 앱의 역할

| 앱 | 기술 | 역할 | 포트 |
|---|---|---|---|
| **web** | Next.js 14+ | 양봉가 웹앱 (벌통 등록, 이미지 업로드, 결과 조회) | 3000 |
| **admin** | Next.js 14+ | 관리자 대시보드 (사용자/구독 관리, 분석 모니터링) | 3002 |
| **api** | Hono.js | API 서버 (인증, CRUD, 이미지 업로드 조율) | 3001 |
| **ai** | FastAPI | AI 분석 서버 (OpenAI Vision API 호출) | 8000 |

---

## 📍 작업 라우팅 가이드 (상황 → 폴더)

> **Claude 필독**: 작업 요청을 받으면 아래 표에서 상황을 찾고, 해당 폴더의 `@CLAUDE.md`를 먼저 읽고 시작합니다. 분야별 컨벤션·금기·체크리스트가 그 안에 있습니다.

### 🗂 분야별 진입점 (8개)

| 분야 | 진입 문서 | 폴더 |
|---|---|---|
| DB & 스키마 | @packages/database/CLAUDE.md | @packages/database/ |
| Backend API | @apps/api/CLAUDE.md | @apps/api/ |
| AI 서비스 (OpenAI + YOLO) | @apps/ai/CLAUDE.md | @apps/ai/ |
| Flutter 모바일 | @apps/mobile/CLAUDE.md | @apps/mobile/ |
| 어드민 대시보드 | @apps/admin/CLAUDE.md | @apps/admin/ |
| 랜딩/마케팅 | @apps/web/CLAUDE.md | @apps/web/ |
| 디자인 시스템 (UI) | @packages/ui/CLAUDE.md | @packages/ui/ |
| DevOps / 인프라 | @infra/CLAUDE.md | @infra/ |

### 🔍 상황별 라우팅

#### 인증 / 사용자
| 상황 | 건드릴 폴더 |
|---|---|
| 로그인/회원가입/JWT 라우트 추가 | @apps/api/src/routes/ + @apps/api/src/middleware/ + @apps/api/src/lib/ — 가이드: @apps/api/CLAUDE.md |
| 사용자 테이블 / refresh_token 스키마 변경 | @packages/database/src/schema/ + @packages/database/migrations/ — 가이드: @packages/database/CLAUDE.md |
| 모바일 로그인 UI / 토큰 저장 | @apps/mobile/lib/features/auth/ + @apps/mobile/lib/core/storage/ — 가이드: @apps/mobile/CLAUDE.md |
| 어드민 로그인 / role 검증 | @apps/admin/src/app/(auth)/login/ + @apps/admin/middleware.ts — 가이드: @apps/admin/CLAUDE.md |

#### 벌통 (Hive) CRUD
| 상황 | 건드릴 폴더 |
|---|---|
| 벌통 API 엔드포인트 | @apps/api/src/routes/ + @apps/api/src/schemas/ — 가이드: @apps/api/CLAUDE.md |
| 벌통 DB 모델 / 쿼리 헬퍼 | @packages/database/src/schema/ + @packages/database/src/queries/ — 가이드: @packages/database/CLAUDE.md |
| 모바일 벌통 리스트/상세 | @apps/mobile/lib/features/hives/ — 가이드: @apps/mobile/CLAUDE.md |
| 어드민 벌통 모니터링 | @apps/admin/src/app/(dashboard)/users/ + @apps/admin/src/components/tables/ — 가이드: @apps/admin/CLAUDE.md |

#### 이미지 업로드 / 진단
| 상황 | 건드릴 폴더 |
|---|---|
| Presigned URL 발급 / 업로드 라우트 | @apps/api/src/routes/ + @apps/api/src/services/ (storage.ts, ai-client.ts) — 가이드: @apps/api/CLAUDE.md |
| AI 분석 (OpenAI Vision) | @apps/ai/app/routers/ + @apps/ai/app/services/ + @apps/ai/app/prompts/ — 가이드: @apps/ai/CLAUDE.md |
| AI 분석 (자체 YOLO 추론) | @apps/ai/app/services/yolo_inference.py + @apps/ai/app/routers/yolo.py — 가이드: @apps/ai/CLAUDE.md |
| YOLO 모델 학습 / 데이터셋 | @apps/ai/training/ + **@apps/ai/training/datasets/AIHUB_71667.md (v0.1.0 주 데이터셋, cold-pickup 필독)** + @apps/ai/training/datasets/README.md — 가이드: @apps/ai/CLAUDE.md |
| 분석 결과 DB 저장 (dual-engine) | @packages/database/src/schema/analyses.ts + @packages/database/src/schema/aiModels.ts — 가이드: @packages/database/CLAUDE.md |
| 모바일 카메라 / 결과 화면 | @apps/mobile/lib/features/analyses/ + @apps/mobile/lib/shared/widgets/ — 가이드: @apps/mobile/CLAUDE.md |
| 어드민 진단 비교 뷰 (bbox) | @apps/admin/src/app/(dashboard)/analyses/ + @apps/admin/src/components/viewer/ — 가이드: @apps/admin/CLAUDE.md |

#### UI / 디자인
| 상황 | 건드릴 폴더 |
|---|---|
| 공유 컴포넌트 추가 (Button, Card 등) | @packages/ui/src/components/ — 가이드: @packages/ui/CLAUDE.md |
| 디자인 토큰 (꿀색 팔레트, 타이포) | @packages/ui/src/tokens/ + @packages/ui/tailwind.preset.ts — 가이드: @packages/ui/CLAUDE.md |
| 어드민 차트 / 테이블 | @apps/admin/src/components/charts/ + @apps/admin/src/components/tables/ — 가이드: @apps/admin/CLAUDE.md |
| 랜딩 페이지 / SEO | @apps/web/src/app/[locale]/ + @apps/web/src/lib/ — 가이드: @apps/web/CLAUDE.md |
| 블로그 / MDX 콘텐츠 | @apps/web/content/blog/ + @apps/web/messages/ — 가이드: @apps/web/CLAUDE.md |
| 모바일 테마 / 다국어 | @apps/mobile/lib/core/theme/ + @apps/mobile/lib/l10n/ — 가이드: @apps/mobile/CLAUDE.md |

#### 인프라 / 배포 / CI
| 상황 | 건드릴 폴더 |
|---|---|
| Dockerfile (앱별) | @apps/api/Dockerfile, @apps/ai/Dockerfile, @apps/admin/Dockerfile, @apps/web/Dockerfile — 가이드: @infra/CLAUDE.md |
| 로컬 docker-compose 확장 | @docker-compose.yml + @infra/docker/nginx/ — 가이드: @infra/CLAUDE.md |
| GitHub Actions (CI/CD) | @.github/workflows/ — 가이드: @infra/CLAUDE.md |
| Terraform (AWS Seoul, 환경별) | @infra/terraform/modules/ + @infra/terraform/envs/staging/ + @infra/terraform/envs/production/ — 가이드: @infra/CLAUDE.md |
| Kubernetes (기존 develop 자산) | @infra/k8s/ |
| 시크릿 / 환경변수 | @.env.example + AWS Secrets Manager (가이드: @infra/CLAUDE.md) |
| 부하 테스트 (k6) | @infra/k6/ — 가이드: @infra/CLAUDE.md |
| 운영 스크립트 | @scripts/ — 가이드: @infra/CLAUDE.md |

#### 테스트
| 상황 | 건드릴 폴더 |
|---|---|
| API 통합 테스트 (vitest) | @apps/api/src/tests/ — 가이드: @apps/api/CLAUDE.md |
| API 시나리오 (Bruno) | @apps/api/bruno/ |
| AI 단위/회귀 테스트 (pytest) | @apps/ai/app/tests/ + @apps/ai/app/tests/fixtures/ — 가이드: @apps/ai/CLAUDE.md |
| Flutter unit/widget/integration | @apps/mobile/test/ + @apps/mobile/integration_test/ — 가이드: @apps/mobile/CLAUDE.md |
| 어드민 e2e (Playwright) | @apps/admin/tests/ — 가이드: @apps/admin/CLAUDE.md |
| 디자인 시스템 시각 회귀 | @packages/ui/.storybook/ — 가이드: @packages/ui/CLAUDE.md |

#### 문서 / 기획
| 상황 | 건드릴 폴더 |
|---|---|
| 요구사항(PRD) | @docs/00-requirement/ |
| 아키텍처 문서 | @docs/01-development/ |
| 테스트 시나리오 | @docs/02-scenario/ |
| 기술 부채 / 리팩토링 | @docs/03-refactoring/ |
| 운영 런북 | @docs/04-operation/ |
| **구현 완료 기록 (PR 머지 산출물 인덱스)** ★ | **@docs/05-implementation/** |
| Git 워크플로우 (필독) | @gitworkflow.md, @GIT_FLOW_GUIDE.md |
| 모노레포 빠른 시작 | @README_MONOREPO.md |
| 모노레포 상세 구조 | @PROJECT_STRUCTURE.md |

### ⚠️ 다중 폴더 변경 시 (필수 동기화)

- **API 응답 타입 변경** → @packages/types/src/ → 사용처 (@apps/api, @apps/admin, @apps/web, @apps/mobile) 모두 갱신
- **DB 스키마 변경** → @packages/database/src/schema/ + @packages/database/migrations/ + @packages/database/CLAUDE.md 체크리스트 통과 + 의존하는 @apps/api/src/routes/ 검토
- **AI 응답 스키마 변경** → @apps/ai/app/schemas/ + @apps/api/src/services/ai-client.ts + @apps/mobile/lib/features/analyses/ + @apps/admin/src/app/(dashboard)/analyses/
- **디자인 토큰 변경** → @packages/ui/src/tokens/ + @apps/admin + @apps/web 모두 영향, PR 본문에 영향도 명시
- **새 환경변수 추가** → @.env.example + @apps/{각 앱}/CLAUDE.md 환경 섹션 + @infra/CLAUDE.md (Secrets Manager) 동시 갱신

### 🚦 Claude 작업 흐름

1. 사용자 요청을 받으면 위 표에서 가장 가까운 상황을 찾는다
2. 해당 행의 모든 `@폴더/CLAUDE.md`를 먼저 읽는다 (분야별 규칙·금기·체크리스트)
3. 변경할 파일을 식별하고 `git checkout -b feature/{설명}` (현재가 develop이면)
4. 분야별 CLAUDE.md의 PR 체크리스트를 통과한 뒤 push → develop으로 PR

---

## 📖 참고 문서 가이드

### 반드시 읽을 문서

1. **@PROJECT_STRUCTURE.md** (구조 파악 시)
   - 각 앱/패키지의 상세 구조
   - 서비스 간 데이터 흐름
   - 의존성 관계도
   - 향후 구현 단계

2. **@gitworkflow.md** (개발/배포 시)
   - Git 브랜칭 전략 (feature, bugfix, release 등)
   - GitHub Actions 워크플로우 정의
   - 배포 환경 (staging, production)
   - PR 체크리스트

3. **@README_MONOREPO.md** (빠른 시작)
   - 설치 및 실행 방법
   - 개별 앱 실행 명령어
   - 데이터베이스 마이그레이션

### 진행 상황 추적 — 새 작업 시 ★ 먼저 확인 ★

4. **@docs/05-implementation/** — PR 단위 구현 기록 인덱스
   - 무엇이 이미 구현됐는지 한눈에 파악 (git log 뒤지지 말고 여기부터)
   - 각 PR 머지 시 `YYYY-MM-DD-{topic}.md` 한 파일 추가 의무
   - 디렉터리 README에 작성 규칙 / 템플릿 / 인덱스 표 정리됨
   - cold-pickup AI / 신규 합류자의 첫 시작점

---

## 🚀 자주 사용하는 명령어

### 환경 설정

```bash
# 의존성 설치 (첫 실행 시)
pnpm install

# 환경변수 설정
cp .env.example .env.local
# 필수: DATABASE_URL, REDIS_URL, OPENAI_API_KEY, JWT_SECRET 입력

# DB & Redis 시작 (Docker 필요)
docker-compose up -d
```

### 개발 서버

```bash
# 전체 앱 동시 실행 (권장)
pnpm dev

# 개별 앱 실행
pnpm --filter @helpbee/web dev      # 웹앱
pnpm --filter @helpbee/admin dev    # 관리자
pnpm --filter @helpbee/api dev      # API 서버
cd apps/ai && python -m uvicorn app.main:app --reload  # AI 서버
```

### 빌드 & 린트

```bash
# 전체 빌드
pnpm build

# 린트 확인
pnpm lint

# 타입 체크
pnpm type-check

# 테스트
pnpm test

# 특정 앱만 빌드
pnpm --filter @helpbee/api build
```

### 데이터베이스

```bash
# DB 스키마 변경 후 마이그레이션 생성
pnpm --filter @helpbee/database push

# 마이그레이션 적용
pnpm --filter @helpbee/database migrate

# Drizzle Studio (웹 UI로 DB 관리)
pnpm --filter @helpbee/database studio
```

### 정리

```bash
# 빌드 결과, .next, dist 등 정리
pnpm clean

# node_modules 완전 제거 후 재설치 (문제 해결 시)
pnpm clean && pnpm install
```

---

## 🔄 개발 워크플로우

### 새 기능 개발 시

1. **@gitworkflow.md 확인**: 브랜칭 전략 참고
   ```bash
   git checkout -b feature/my-feature
   ```

2. **로컬 개발**
   ```bash
   pnpm dev  # 필요한 서비스 실행
   ```

3. **커밋 & PR**
   - develop 브랜치로 PR 생성
   - CI 자동 실행 (린트, 테스트)
   - 최소 1명 승인 필수

4. **머지 & 배포**
   - develop에 머지되면 자동 테스트
   - 정기 릴리스 시 main으로 release PR 생성
   - 배포 자동화

---

## 💡 핵심 기술 결정사항

### 왜 이 기술을 선택했는가?

| 기술 | 선택 이유 |
|---|---|
| **Turborepo** | 빠른 캐싱, 변경된 패키지만 빌드 |
| **Next.js 14** | SSR/SSG, 이미지 최적화, API 라우트 |
| **Hono.js** | Express 대비 5~10배 빠름, TypeScript 네이티브 |
| **FastAPI** | OpenAI SDK 생태계, 이미지 처리 (Pillow) |
| **Drizzle ORM** | Prisma보다 런타임 오버헤드 없음, 타입 안전 |
| **pnpm** | Yarn/npm보다 저장 공간 효율적, 속도 빠름 |

---

## 🤖 AI/ML 도구 활용

### Claude 플러그인과 스킬 자유로운 사용

이 프로젝트에서 다음 도구들을 적극 활용하세요:

#### 플러그인 (Plugin)
- **@figma** - UI 디자인이 필요하면 Figma 연동
- **@game-changing-features** - 10x 기능 발상

#### 스킬 (Skill)
- **@update-config** - 설정 파일 수정
- **@keybindings-help** - 개발 생산성 향상
- **@simplify** - 코드 정리 및 최적화
- **@humanizer** - 문서 작성 시 자연스럽게

#### 명령어
- `/help` - Claude Code 사용법
- `/model` - 모델 변경
- `/fast` - 빠른 응답 (속도 vs 정확도)

---

## 🔧 주요 파일 경로

```
프로젝트 루트/
├── CLAUDE.md              👈 현재 파일 (가이드)
├── PROJECT_STRUCTURE.md   👈 상세 구조 (필독)
├── gitworkflow.md         👈 워크플로우 (필독)
├── README_MONOREPO.md     👈 빠른 시작 (필독)
│
├── apps/
│   ├── web/               → 사용자 웹앱
│   ├── admin/             → 관리자 대시보드
│   ├── api/src/           → API 서버 로직
│   └── ai/app/            → AI 분석 로직
│
├── packages/
│   ├── types/src/         → 공유 타입
│   ├── database/src/schema/ → DB 스키마
│   ├── ui/src/            → UI 컴포넌트
│   └── config/            → 설정
│
├── .github/workflows/     → CI/CD (구현 예정)
├── infra/docker/          → Docker 설정
│
└── 루트 설정
    ├── package.json       → 모노레포 설정
    ├── turbo.json         → 빌드 파이프라인
    ├── pnpm-workspace.yaml → 워크스페이스
    └── docker-compose.yml → 로컬 개발 환경
```

---

## 🎓 개발 시 주의사항

### 타입 안전성
- 모든 코드는 TypeScript로 작성 (Python 제외)
- `@helpbee/types` 패키지의 타입을 우선 사용
- 새 타입 추가 시 `packages/types/src/`에 추가

### 모노레포 의존성
- 앱 간 의존성은 패키지 경유로만 가능
- 직접 `import`하지 않음 (예: `import from '@helpbee/types'`)
- 순환 의존성 금지

### API 문서화
- 새 엔드포인트는 주석으로 설명
- request/response 타입 명시

### 환경변수
- `.env.example`에 필수 변수 추가
- `.env.local`에 실제 값 입력 (git 커밋 X)

---

## 🆘 문제 해결

### 의존성 문제
```bash
# node_modules 캐시 문제 시
pnpm clean && pnpm install
```

### 포트 충돌
```bash
# 이미 사용 중인 포트 확인 및 종료
lsof -i :3000   # web
lsof -i :3001   # api
lsof -i :8000   # ai
```

### DB 연결 문제
```bash
# Docker 서비스 상태 확인
docker-compose ps

# 재시작
docker-compose restart
```

---

## 📞 연락 & 문서 링크

- **GitHub**: https://github.com/hyunshu12/HelpBee
- **이슈**: GitHub Issues로 보고
- **문서**: 각 파일의 주석과 README 참고

---

## ✅ 다음 단계

- [ ] @PROJECT_STRUCTURE.md 읽기
- [ ] @gitworkflow.md 확인
- [ ] `pnpm dev`로 로컬 환경 실행
- [ ] 개발 시작!

