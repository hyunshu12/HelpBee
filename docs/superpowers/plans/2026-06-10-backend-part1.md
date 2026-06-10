# 백엔드 1부 (AI 추론 오케스트레이션 + 데이터 저장) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 설계 1부(`docs/01-development/backend-design.md` §1–5)의 이미지→추론→저장→조회 동기 경로를, 이를 떠받치는 최소 Part2 기반(config·envelope·error·auth)과 함께 구현한다.

**Architecture:** Hybrid C — `apps/api`(Hono)가 정책·소유권·쿼터·영속·감사를 맡고, `apps/ai`(FastAPI)가 YOLO→OpenAI 폴백 추론을 실행하며 풍부한 메타를 반환한다. 저장은 `@helpbee/database` queries 헬퍼만 경유. 동기 처리(POST가 완성 리소스 반환, pending 미영속).

**Tech Stack:** Hono, Drizzle(postgres-js), Redis(ioredis), zod+@hono/zod-validator, @aws-sdk/client-s3 + s3-request-presigner, sharp, file-type, axios, pino · FastAPI, Pydantic v2, onnxruntime, boto3, tenacity, Pillow(+pillow-heif), openai.

**테스트 전략 (인프라 제약 대응 — 이 환경엔 Docker/로컬 PG 없음):**
- `packages/database`: **PGlite**(`@electric-sql/pglite` + `drizzle-orm/pglite`)로 인프로세스 Postgres. 테스트 setup이 `migrations/0000_*.sql`을 적용 후 drizzle 인스턴스 제공. 헬퍼는 `Database` 타입을 받으므로 테스트에선 pglite db를 `as unknown as Database` 캐스팅(가장 작은 변경).
- `apps/api`: vitest + Hono `app.request()`. Redis는 `ioredis-mock`, S3/AI 클라이언트는 모듈 모킹. 실제 인프라 불요.
- `apps/ai`: pytest(+pytest-asyncio). OpenAI는 모킹, YOLO 엔진은 protocol/주입으로 fake. 실제 모델·키 불요.
- **E2E(실 인프라 PG/Redis/S3/OpenAI/YOLO)는 이 환경에서 미검증** → 별도 환경(infra)에서 수행. 본 계획은 unit/integration까지 보장.

**의존성 주의:** 1부 API 경로는 Part2 §6/§7/§16(envelope·error·middleware·config) + 최소 `requireAuth`(§8)에 의존. 이 기반을 Group C에 포함한다(전체 auth 도메인은 Part2 별도). DB(완료 상태) 델타 `users.blocked_at`는 Part2 auth 작업이므로 1부 범위 밖.

---

## 파일 구조 (생성/수정)

**packages/database** (Group A)
- Modify: `src/queries/analyses.ts` — `createSingleAnalysis`, `getAnalysisByIdForUser`, `listAnalysesByHiveForUser` 추가, 기존 `listAnalysesByHive` 유지(@deprecated 주석)
- Create: `src/queries/images.ts` — `getAnalysisImageByIdForUser`
- Modify: `src/queries/index.ts` — `images` 네임스페이스 추가
- Create: `src/test/pglite.ts` — 테스트 db 팩토리(마이그레이션 적용)
- Create: `src/queries/analyses.test.ts`, `src/queries/images.test.ts`
- Modify: `package.json` — vitest, @electric-sql/pglite devDep + `test` 스크립트
- Create: `vitest.config.ts`

**apps/api 기반+오케스트레이션** (Group C·D)
- Create: `src/config/env.ts`, `src/lib/envelope.ts`, `src/lib/problem.ts`, `src/lib/error-codes.ts`
- Create: `src/middleware/request-id.ts`, `src/middleware/auth.ts`(requireAuth 최소), `src/middleware/error-handler.ts`
- Create: `src/services/s3-client.ts`, `src/services/ai-client.ts`, `src/services/quota-service.ts`
- Create: `src/schemas/common.ts`, `src/schemas/images.ts`, `src/schemas/analyses.ts`
- Create: `src/routes/images.ts`, `src/routes/analyses.ts`
- Modify: `src/app.ts`(신규 분리) + `src/index.ts`(@hono/node-server serve)
- Create: `src/tests/helpers/app.ts`, `src/tests/*.test.ts`
- Modify: `package.json`(deps + vitest), `vitest.config.ts`, `.env.example`

**apps/ai 추론** (Group B)
- Create: `app/core/config.py`, `app/schemas/analysis.py`, `app/services/preprocess.py`, `app/services/risk.py`, `app/services/openai_client.py`, `app/services/yolo_engine.py`, `app/routers/analyze.py`
- Modify: `app/main.py`(router include), `requirements.txt`
- Create: `app/tests/unit/test_*.py`, `app/tests/conftest.py`, `pytest.ini`

---

## 실행 순서 (의존성 기반)

1. **Group A — DB 저장 헬퍼** (자립적, 즉시 검증 가능 / PGlite) ← **여기부터 시작**
2. **Group B — apps/ai 추론** (자립적, pytest 목)
3. **Group C — apps/api 기반** (config·envelope·error·auth·미들웨어·서비스 stub)
4. **Group D — apps/api 라우트** (images·analyses 오케스트레이션, C·A·B에 의존)

각 Group은 독립 PR 가능 단위. Group A→B는 병렬 가능, D는 A·B·C 완료 후.

---

## Group A — DB 저장 헬퍼 (PGlite TDD)

**설계 근거:** backend-design §4.5(createSingleAnalysis), §4.6(IDOR 차단 헬퍼), §2-4①②.

### Task A0: PGlite 테스트 하니스
**Files:** Modify `packages/database/package.json` · Create `vitest.config.ts`, `src/test/pglite.ts`

- [ ] **Step 1:** `pnpm --filter @helpbee/database add -D vitest @electric-sql/pglite`
- [ ] **Step 2:** `package.json` scripts에 `"test": "vitest run"`, `"test:watch": "vitest"` 추가
- [ ] **Step 3:** `vitest.config.ts` 작성 (node 환경)
```ts
import { defineConfig } from 'vitest/config';
export default defineConfig({ test: { environment: 'node', include: ['src/**/*.test.ts'] } });
```
- [ ] **Step 4:** `src/test/pglite.ts` — fresh pglite db 팩토리
```ts
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { drizzle } from 'drizzle-orm/pglite';
import * as schema from '../schema';
import type { Database } from '../client';

export async function makeTestDb() {
  const pg = new PGlite();
  const dir = join(__dirname, '../../migrations');
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.sql')).sort()) {
    const sql = readFileSync(join(dir, f), 'utf8').replace(/--> statement-breakpoint/g, '');
    await pg.exec(sql);
  }
  const db = drizzle(pg, { schema }) as unknown as Database;
  return { db, pg };
}
```
- [ ] **Step 5:** 검증 — `pnpm --filter @helpbee/database test` (테스트 0개라도 vitest 부팅 OK)
- [ ] **Step 6:** Commit `chore(db): add vitest + pglite test harness`

### Task A1: createSingleAnalysis
**Files:** Modify `src/queries/analyses.ts` · Create `src/queries/analyses.test.ts`

- [ ] **Step 1: 실패 테스트** — `analyses.test.ts`: user→hive→image→ai_model 시드 후 `createSingleAnalysis`로 analyses 1행 + recommendations N행 생성, 같은 (imageId,modelId) 재호출 시 멱등(중복 행 0, recommendations 재삽입) 검증. success 행은 덮어쓰지 않음(WHERE status<>'success') 검증.
- [ ] **Step 2:** `vitest run src/queries/analyses.test.ts` → FAIL(함수 없음)
- [ ] **Step 3: 구현** — `createSingleAnalysis(db, { hiveId, imageId, modelId, analysis, recommendations })`: 트랜잭션에서 `insert(analyses).onConflictDoUpdate({ target:[imageId,modelId], set:{...}, setWhere: ne(analyses.status,'success') })` + `delete(recommendations).where(eq(analysisId))` 후 재삽입. recommendations 스키마(order/content/severity) 사용.
- [ ] **Step 4:** `vitest run` → PASS
- [ ] **Step 5: Commit** `feat(db): add createSingleAnalysis (single-engine + recommendations, idempotent)`

### Task A2: getAnalysisImageByIdForUser (IDOR)
**Files:** Create `src/queries/images.ts`, `src/queries/images.test.ts` · Modify `src/queries/index.ts`

- [ ] **Step 1: 실패 테스트** — 소유자 userId면 image 반환, 타 user면 undefined, soft-deleted hive면 undefined.
- [ ] **Step 2:** FAIL 확인
- [ ] **Step 3: 구현** — `getAnalysisImageByIdForUser(db, imageId, userId)`: `analysis_images` INNER JOIN `hives` on hive_id, WHERE image.id + image.uploadedBy=userId + hives.userId=userId + hives.deletedAt IS NULL. (uploadedBy·hiveId 교차검증). `index.ts`에 `export * as images`.
- [ ] **Step 4:** PASS
- [ ] **Step 5: Commit** `feat(db): add getAnalysisImageByIdForUser (ownership/IDOR guard)`

### Task A3: getAnalysisByIdForUser + listAnalysesByHiveForUser (IDOR)
**Files:** Modify `src/queries/analyses.ts`, `src/queries/analyses.test.ts`

- [ ] **Step 1: 실패 테스트** — 단일 조회 소유권(타 user → undefined); 목록은 userId 조인으로 타 user hiveId → 빈 배열, 페이지네이션 동작.
- [ ] **Step 2:** FAIL
- [ ] **Step 3: 구현** — `getAnalysisByIdForUser(db, analysisId, userId)`(analyses JOIN hives, 소유권), `listAnalysesByHiveForUser(db, hiveId, userId, opts)`(getHiveTrend의 INNER JOIN 패턴). 기존 `listAnalysesByHive`에 `@deprecated` 주석.
- [ ] **Step 4:** PASS
- [ ] **Step 5: Commit** `feat(db): IDOR-safe analysis read helpers (by-id, by-hive for user)`

---

## Group B — apps/ai 추론 (pytest 목 TDD)

**설계 근거:** backend-design §3(오케스트레이션·폴백), AIHUB_71667.md(infestation_rate), risk.yaml.

### Task B0: 의존성 + pytest
- [ ] `requirements.txt`에 `tenacity`, `pillow-heif`, `onnxruntime`, `boto3`, `python-multipart`, `pytest`, `pytest-asyncio` 추가, `openai`>=1.30 상향. `pytest.ini`(asyncio_mode=auto). Commit.

### Task B1: 스키마 + config
- [ ] **TDD**: `app/schemas/analysis.py` — `AnalysisResponse`(risk_score,tier safe/watch/danger,estimated_count,confidence,recommendations,model_version,prompt_version,latency_ms,cost_estimate_usd,raw_payload,engine_used,fallback_reason). 직렬화 round-trip 테스트. `app/core/config.py`(pydantic-settings, 필수 env fail-fast). Commit.

### Task B2: risk.py (infestation_rate)
- [ ] **TDD**: `services/risk.py` — `compute_risk(class_counts) -> RiskResult`: infestation_rate = varroa/(normal+varroa+other)*100, risk.yaml 임계(3%/10%)로 tier, score_mapping(0%→0,3%→21,10%→70 클램프), bee<5 → low_confidence. 알려진 분포 입력 테스트(경계값). Commit.

### Task B3: preprocess.py
- [ ] **TDD**: `services/preprocess.py` — EXIF strip, RGBA→RGB, HEIC→JPEG, 1024px LANCZOS, q85, 10MB 가드(q80→75). 작은 RGBA/대형 픽셀 fixture 테스트. Commit.

### Task B4: yolo_engine + openai_client (주입 가능)
- [ ] **TDD**: `services/yolo_engine.py` — `YoloEngine` protocol + ONNX 구현(lazy S3/cache load)이되 테스트는 FakeYolo 주입. `services/openai_client.py` — structured output 호출, usage→USD, graceful. OpenAI는 monkeypatch 모킹. Commit.

### Task B5: /analyze engine=auto 폴백
- [ ] **TDD**: `routers/analyze.py` — POST /analyze: preprocess→YOLO→risk→폴백판정(벌<5/경계±밴드/에러)→(유료 허용 시)OpenAI→통합 AnalysisResponse. `engine=yolo`(무료)면 폴백 금지. 양쪽 실패 graceful(200, risk=null). FakeYolo/mock OpenAI로 (정상/폴백/양쪽실패/무료-no-fallback) 4 케이스. `main.py` router include. Commit.

---

## Group C — apps/api 기반 (config·envelope·error·auth·서비스)

**설계 근거:** backend-design §6, §7, §16, §3.2(ai-client), §3.8(SSRF), 1부 §2-③(quota reserve-then-refund).

### Task C0: 의존성 + 부트스트랩
- [ ] `pnpm --filter @helpbee/api add zod @hono/zod-validator @hono/node-server ioredis @aws-sdk/client-s3 @aws-sdk/s3-request-presigner sharp file-type pino` + `-D vitest ioredis-mock @types/node`. `vitest.config.ts`. Commit.

### Task C1: config/env (zod fail-fast)
- [ ] **TDD**: `config/env.ts` — zod로 `DATABASE_URL, REDIS_URL, JWT_SECRET(min64), AI_BASE_URL, AI_INTERNAL_HMAC_SECRET(min32), AWS_REGION, S3_IMAGES_BUCKET, OPENAI_*`… 검증, 누락/플레이스홀더 부팅 거부. 누락 시 throw 테스트. Commit.

### Task C2: envelope + problem + error-codes
- [ ] **TDD**: `lib/error-codes.ts`(enum→status/title/type 테이블), `lib/problem.ts`(`problem(c,code,detail)` RFC7807), `lib/envelope.ts`(`ok`/`created`, requestId/timestamp 자동). 코드↔status 매핑 테스트. Commit.

### Task C3: 미들웨어 (request-id, requireAuth 최소, error-handler)
- [ ] **TDD**: `middleware/request-id.ts`, `middleware/auth.ts`(jwt-simple HS256 **alg 명시 검증**, `c.set('userId','role')`, 누락 401), `middleware/error-handler.ts`(onError→problem). 위조/만료/정상 토큰 테스트. Commit.

### Task C4: s3-client
- [ ] **TDD**: `services/s3-client.ts` — `presignPut(key,contentType)`(5분), `presignGet(key)`(90~120s), `headObject`, `deleteObject`, `validateAndStrip(bytes)`(file-type 매직넘버 + sharp limitInputPixels + EXIF strip 재인코딩). 키 패턴 `images/{userId}/{yyyy}/{mm}/{uuid}.{ext}`. aws-sdk 모킹 테스트. Commit.

### Task C5: ai-client (Hybrid C)
- [ ] **TDD**: `services/ai-client.ts` — axios timeout 30s, **추론 호출 무재시도**, presignedGetUrl + `engine`('auto'유료/'yolo'무료) 전달, **단기 HMAC 내부 bearer**(aud=ai,exp~5m,request_id 바인딩) 서명, x-request-id 전파, 응답 정규화. axios-mock 테스트(정상/타임아웃/4xx no-retry). Commit.

### Task C6: quota-service (reserve-then-refund)
- [ ] **TDD**: `services/quota-service.ts` — `reserve(userId)`(원자 INCR `quota:{userId}:{YYYYMM-KST}`, >4면 throw QUOTA_EXCEEDED, EXPIRE 월말 KST), `confirm()`(no-op), `refund(userId)`(DECR), 멱등 short-circuit 무차감. ioredis-mock + KST 월경계 테스트. Commit.

---

## Group D — apps/api 라우트 (오케스트레이션)

**설계 근거:** backend-design §2(흐름), §6.5(계약 표), §10(images).

### Task D1: schemas
- [ ] **TDD**: `schemas/common.ts`(pagination,.strict,idParam), `schemas/images.ts`(presign/confirm), `schemas/analyses.ts`(create/list). zod 파싱 테스트. Commit.

### Task D2: images 라우트 (presign/confirm)
- [ ] **TDD**: `routes/images.ts` — `POST /v1/images/presign`(검증→presignPut), `POST /v1/images/confirm`(head→매직넘버→≤10MB→EXIF strip→`analysis_images` insert→image_id). Hono app.request + 모킹 s3-client/db. 미지원 타입/초과/정상. Commit.

### Task D3: analyses 라우트 (동기 오케스트레이션)
- [ ] **TDD**: `routes/analyses.ts` — `POST /v1/analyses`: requireAuth→이미지 소유권(getAnalysisImageByIdForUser)→**멱등 short-circuit**(기존 success 반환)→**quota.reserve**→plan별 engine→ai-client.analyze→engine_used→model_id 조회→`createSingleAnalysis`→성공 confirm/실패 refund→**완성 리소스 created()**. 양쪽실패 status=failed+200. `GET /v1/analyses?hiveId=`(listAnalysesByHiveForUser), `GET /:id`(getAnalysisByIdForUser), `GET /trend`(getHiveTrend). 모킹으로 (정상/폴백/멱등/quota초과/IDOR) 케이스. Commit.

### Task D4: app.ts 와이어링 + serve
- [ ] **TDD**: `app.ts`(미들웨어 체인 §7 순서 + 라우트 마운트, health 보존), `index.ts`(@hono/node-server `serve`). 부팅 + /health + 보호 라우트 401 통합 테스트. Commit.

---

## Self-Review 체크 (작성자)
- 스펙 커버리지: §2 흐름(D2/D3), §3 오케스트레이션·폴백(C5/B5), §4 저장(A1·A3·D3), §5 기본값(C1 env·C6 quota·C4 EXIF). ✅
- 타입 일관: `Database`(A), `AnalysisResponse`(B1↔C5 정규화), `engine_used→model_id`(D3가 ai_models 조회). ✅
- 무플레이스홀더: 각 Task에 파일·테스트·커밋 명시. 상세 계약은 design §6.5/§4.3 표 참조(중복 회피).
- 인프라 한계: E2E는 본 환경 밖 — unit/integration까지만 보장(명시).

## 미해결/위험
- PGlite가 마이그레이션 SQL의 트리거/CHECK를 전부 수용하는지 A0에서 1차 확인 필요(불가 시 sql.js 또는 generated-SQL 단위검증으로 폴백).
- 신규 deps 설치는 네트워크 의존(오프라인 시 차단).
- apps/ai 실모델(best.onnx)·OpenAI 키는 테스트에서 모킹 — 실추론 정확도는 별도 환경 회귀.
- `users.blocked_at` 등 DB 델타·전체 auth 도메인은 Part2.
