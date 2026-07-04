# 2026-07-04 — 전체 시스템 라이브 점검 (앱·웹·백엔드·AI)

> PR: 없음 (점검/문서 현행화) · 브랜치: feature/web-frontend-mvp 워킹트리에서 수행 · 점검일: 2026-07-04

## 범위 (Scope)

초기 마스터 플랜 대비 진행 현황을 확정하고, 로컬에서 4개 앱(api·ai·web·mobile)을 실제 구동/테스트하여
"되는 것 / 안 되는 것"을 실측으로 검증. 결과와 개선 계획(P0~P2)을 루트 `CLAUDE.md`
"🧪 2026-07-04 전체 시스템 점검 결과 & 개선 계획" 섹션에 기록.

## 검증 (Verification) — 실측 결과

### 테스트 스위트 (전부 이 날짜에 실행)

| 대상 | 명령 | 결과 |
|---|---|---|
| apps/api | `pnpm --filter @helpbee/api test` | ✅ 16 files / **166 tests PASS** (Docker 불필요, in-process) |
| apps/api | `type-check` | ✅ PASS |
| apps/ai | `.venv/bin/python -m pytest -q` | ✅ **65 PASS** (OpenAI는 mock, 실키 불필요) |
| apps/web | `build` | ✅ **25/25 SSG** (ko/en × 10라우트 + robots/sitemap 등) |
| apps/web | `type-check` | ✅ PASS |
| apps/web | `lint` | ❌ FAIL — ESLint config 부재(`next lint` 인터랙티브 프롬프트에서 사망, build는 조용히 skip) |
| packages/ui | `type-check` + vitest | ✅ 12 tests PASS |
| apps/mobile | `dart analyze` | ✅ 0 issues |
| apps/mobile | `flutter test` | ❌ 실행 불가 — **환경 문제**(Xcode 라이선스 미동의 → objective_c build hook 크래시). 코드 문제 아님 |

### 라이브 E2E (API :3001 + AI :8000 실기동)

1. 로그인(`beekeeper1@helpbee.local`) → hives 목록 → subscriptions/me·plans ✅
2. **진단 파이프라인 전체 성공**: `POST /v1/images/presign` → S3 직접 PUT(200) →
   `POST /v1/images/confirm`(1920×1080 추출) → `POST /v1/analyses` →
   **YOLO v0.1.0 ONNX 추론 성공** — 응애 샘플(유충_응애) → `risk 70 / warning / infestation_rate 100%`, latency **197ms** ✅
   (= PR #24 decode / #25 q95 수정이 머지된 서빙 경로가 프로덕션 흐름에서 정상 동작함을 최초 확인)
3. `GET /v1/analyses?hiveId=` / `GET /v1/analyses/trend`(일별 avgRisk 버킷) ✅
4. web dev 서버: `/ko`, `/ko/pricing`, `/ko/contact` 200 + SEO 메타/hreflang 정상 ✅

### 발견된 문제 (요약 — 근본 원인·개선안은 루트 CLAUDE.md §B·§C)

1. **실패 분석 영구 잔존**: `UNIQUE(image_id, model_id)` + 기존 row 반환 → `ai_unavailable`로 실패한 이미지는 재분석 불가 (P0-1)
2. **dev 서버 `.env` 미로드**: api(tsx watch)·ai(uvicorn) 모두 자동 로드 안 함. env 없이 뜨면 API는 즉사, AI는 HMAC 401로 전 분석 실패 (P0-2, 이번 점검에서 실제 재현)
3. **recommendations 미반환** → 결과 화면 처방 문구 공백 (P0-3)
4. `/v1/inquiries` 404 — 웹 문의폼 백엔드 부재 (P1-1)
5. web ESLint config 부재 (P1-2) / AI 회귀 fixture 부재(`-m regression` 0 selected) (P1-3) / 이메일 인증 발송 미구현 (P1-4)
6. `estimated_varroa_count` 항상 null — 데이터셋 라벨 제약(AIHUB_71667.md §6), 버그 아님

## 진행 현황 확정 (초기 계획 대비)

- ✅ **완료**: DB 9테이블(dual-engine) · Backend API 전 라우트(~PR #22) · YOLO v0.1.0 학습+서빙(#24/#25 머지) · 모바일 MVP 전 플로우(#26~#31: 인증→벌통 CRUD→카메라→분석→레포트→등록/수정)
- 🟡 **대기**: 웹 MVP — **PR #33 OPEN** (build green, 라이브 검증 완료, 머지만 남음)
- ❌ **미착수**: Admin 대시보드(`apps/admin/src`는 `.gitkeep`만) · CI/CD(`.github/workflows/` 없음) · Terraform(envs 빈 폴더)

## 후속 작업 (Follow-up)

- 개선 계획 전체(P0-1~P2-3, 수정 파일·구현 방안·검증 기준 포함): **루트 `CLAUDE.md` §C** ★ 단일 소스
- 문서 현행화 완료: `docs/01-development/frontend-api-integration.md` §10 Readiness (AI 추론 ❌→✅ 로컬 동작),
  `apps/mobile/CLAUDE.md` 연동 주의 블록
- 사용자 액션 필요: `sudo xcodebuild -license accept` (flutter test 차단 해제)

## 참조

- 재현 명령·시드 계정·테스트 이미지 경로: 루트 `CLAUDE.md` §D
- 로컬 스택: Docker 미설치, brew Postgres 16 + Redis 7, `apps/api/.env`·`apps/ai/.env`(gitignored)
- YOLO 모델 캐시: `~/.cache/helpbee/yolo/v0.1.0/best.onnx` (S3 `helpbee-models` 원본)
