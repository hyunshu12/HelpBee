# 2026-07-04 — dev 서버 .env 자동 로드 (P0-2)

> PR: #40 · 브랜치: feature/dev-env-autoload → develop · 머지일: (예정)

## 범위 (Scope)

`pnpm --filter @helpbee/api dev`와 AI 서버(uvicorn)가 `.env`를 자동 로드하지 않아, env를 수동으로 source하지 않으면 API는 즉시 크래시(`[config] invalid environment`)하고 AI는 HMAC 401로 모든 분석이 실패하던 개발 함정 제거. (2026-07-04 점검 B-1 — 점검 중 실제로 두 번 재현된 문제)

## 산출물 (Deliverables)

- `apps/api/package.json` — dev 스크립트: `tsx watch --env-file-if-exists=.env src/index.ts`
  - `--env-file`이 아닌 `--env-file-if-exists`(Node 22.9+) — `.env` 없는 fresh clone에서도 기동 시도 가능(이때는 기존 fail-fast 검증 메시지가 안내)
- `apps/ai/app/core/config.py` — `load_dotenv(<apps/ai>/.env)` 모듈 로드 시 1회
  - 경로는 `config.py` 기준 고정 → uvicorn을 어느 cwd에서 띄워도 동일 동작
  - `override=False`(기본) → 이미 export된 환경변수가 항상 우선 (프로덕션/CI에 영향 없음)
  - `python-dotenv==1.0.0`은 requirements.txt에 기존재

## 검증 (Verification)

- env 미설정 셸에서 `tsx --env-file-if-exists=.env src/index.ts` → health 200 (env 로드 확인)
- env 미설정 셸에서 `python -c "from app.core.config import settings"` → `ai_internal_hmac_secret` 로드 확인
- `pytest -q` 65 PASS (회귀 없음)

## 후속 작업 (Follow-up)

- 각 앱 CLAUDE.md·frontend-api-integration.md의 "set -a; source .env" 수동 로드 안내는 관련 PR들(#34 등) 머지 후 일괄 단순화 (문서 충돌 방지를 위해 이 PR에서는 미수정)

## 참조

- 루트 CLAUDE.md "2026-07-04 점검" §C P0-2 (PR #34)
