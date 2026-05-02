# apps/api — HelpBee Backend API

> Hono 기반 단일 백엔드. Flutter 앱(`apps/mobile`), Admin 콘솔(`apps/admin`), Landing(`apps/landing`)이 공유하는 API 게이트웨이.
> 참조 플랜: `/Users/hyeonsyu/.claude/plans/refactored-percolating-church.md`

---

## 1. 목적 (Purpose)

이 서비스는 HelpBee 모노레포의 **단일 백엔드 진입점(single API gateway)** 이다.

- **Flutter 모바일 앱** — 일반 사용자(end user) 트래픽. 인증, 양봉장(hive) 관리, AI 분석(analyses) 요청, 이미지 업로드.
- **Admin 콘솔** — 운영자/관리자. 사용자/구독/AI 모델 관리, 감사 로그 조회.
- **Landing** — 비인증 트래픽. 대시보드 통계 일부, 회원가입.

backend 책임 영역:
1. **JWT 발급/검증** — access(15m) + refresh(7d, DB 해시 + 회전).
2. **비즈니스 룰** — 무료 사용자 분석 4회/월 quota, 구독 게이트, 권한(role) 검사.
3. **AI 위임** — 무거운 추론(질병 분류, 객체 검출)은 별도 AI 서비스(`services/ai`)에 위임. API는 axios 클라이언트로 호출만 한다.
4. **저장소 게이트** — Postgres(Drizzle) + Redis(레이트리밋/캐시) + S3(이미지 presigned URL 발급).

이 서비스는 **AI 추론을 직접 수행하지 않는다.** `services/ai-client.ts`로 위임한다.

---

## 2. 기술 스택 (Tech Stack)

| 영역 | 라이브러리 | 비고 |
|---|---|---|
| 런타임 | Node.js 20+ / pnpm | 모노레포 워크스페이스 |
| 프레임워크 | **Hono** | Edge-friendly, 빠른 라우터 |
| ORM | **Drizzle** + `pg` | `@helpbee/database` 패키지 통해서만 접근 |
| 캐시/레이트리밋 | **Redis** (`ioredis`) | sliding window |
| JWT | `jwt-simple` (HS256) | 추후 `jose`(JOSE/JWS) 검토 — RS256 마이그레이션 시 |
| 검증 | `zod` + `@hono/zod-validator` | 모든 입력 스키마 |
| HTTP 클라이언트 | `axios` | AI 서비스 호출, timeout/retry |
| 로깅 | `pino` | structured JSON, request-id propagation |
| 패스워드 | `argon2` (`argon2id`) | bcrypt 사용 금지 |
| 테스트 | `vitest` + Hono `app.request()` | Testcontainers로 PG 격리 |

> **버전 고정 원칙**: 모든 의존성은 루트 `pnpm-lock.yaml`로 고정. `^` 범위 사용 금지(보안 라이브러리 한정 권장).

---

## 3. 폴더 구조 (Folder Structure)

```
apps/api/
├── CLAUDE.md                 ← 이 문서
├── package.json
├── tsconfig.json
├── bruno/                    ← Bruno API 테스트 컬렉션 (.bru 파일)
└── src/
    ├── index.ts              ← 부트스트랩(서버 listen). 현재 health 엔드포인트 존재 — 건드리지 말 것
    ├── app.ts                ← (예정) Hono 앱 인스턴스 생성, 미들웨어/라우터 마운트
    ├── config/
    │   └── env.ts            ← (예정) zod로 process.env 검증, typed export
    ├── routes/
    │   ├── auth.ts           ← signup / login / refresh / logout
    │   ├── hives.ts          ← 양봉장 CRUD
    │   ├── analyses.ts       ← AI 분석 요청/조회
    │   ├── images.ts         ← presigned URL 발급
    │   ├── admin.ts          ← 운영자 전용 (requireRole('admin'))
    │   └── subscriptions.ts  ← 구독 상태/결제 webhook
    ├── middleware/
    │   ├── auth.ts           ← requireAuth, requireRole
    │   ├── rate-limit.ts     ← Redis sliding window
    │   ├── error-handler.ts  ← RFC 7807 application/problem+json
    │   ├── request-id.ts     ← x-request-id 생성/전파
    │   └── logger.ts         ← pino 미들웨어
    ├── services/
    │   ├── ai-client.ts      ← axios로 services/ai 호출 (timeout 30s, retry 2회)
    │   ├── s3-client.ts      ← presigned PUT URL 발급
    │   ├── jwt-service.ts    ← sign/verify, refresh 회전 + 재사용 감지
    │   ├── password-service.ts ← argon2 hash/verify
    │   └── quota-service.ts  ← Redis 무료 분석 4회/월 카운터
    ├── lib/
    │   ├── problem.ts        ← RFC 7807 Problem 헬퍼
    │   ├── envelope.ts       ← {data, meta} 응답 빌더
    │   └── error-codes.ts    ← enum: AUTH_INVALID_CREDENTIALS, QUOTA_EXCEEDED, ...
    ├── schemas/
    │   ├── auth.ts           ← signup/login zod 스키마
    │   ├── hives.ts
    │   ├── analyses.ts
    │   └── common.ts         ← pagination, id 등 공통 스키마
    └── tests/
        ├── helpers/          ← test app factory, fixtures
        └── *.test.ts         ← 라우트별 통합 테스트
```

**`.gitkeep`** 파일은 빈 디렉터리를 git이 추적하기 위함이다. 실제 파일을 추가하면 제거해도 된다.

---

## 4. 개발 원칙 (Development Principles)

### 4.1 응답 봉투 (Response Envelope)

모든 성공 응답은 `{ data, meta }` 형태:

```ts
{
  data: T,                       // 실제 페이로드
  meta: {
    requestId: string,           // x-request-id
    timestamp: string,           // ISO 8601
    pagination?: { ... }         // list 응답 시
  }
}
```

`lib/envelope.ts`의 `ok(c, data, meta?)` 헬퍼만 사용. raw `c.json(payload)` 금지.

### 4.2 에러 — RFC 7807 Problem Details

`Content-Type: application/problem+json`. 본문 필수 필드:

```ts
{
  type: "https://helpbee.io/errors/quota-exceeded",  // URI reference
  title: "Quota exceeded",
  status: 402,
  code: "QUOTA_EXCEEDED",        // lib/error-codes.ts enum
  detail: "Free tier limit (4/month) reached.",
  instance: "/v1/analyses",
  requestId: "..."
}
```

에러 코드는 **`lib/error-codes.ts`의 enum에만 존재**. 신규 코드 추가 시 enum도 갱신.

### 4.3 검증 — zod + `@hono/zod-validator`

```ts
import { zValidator } from '@hono/zod-validator';
import { signupSchema } from '../schemas/auth';

app.post('/signup', zValidator('json', signupSchema), (c) => { ... });
```

스키마는 항상 `schemas/`에. 라우트 핸들러 안에 인라인 스키마 정의 금지.

### 4.4 인증 미들웨어

- `requireAuth()` — Bearer access token 검증, `c.set('userId', ...)` 주입.
- `requireRole('admin')` — 위 미들웨어 + role 체크. 401 vs 403 구분.

라우트 정의:
```ts
app.use('/admin/*', requireAuth(), requireRole('admin'));
```

### 4.5 JWT 정책

| 토큰 | 알고리즘 | 만료 | 저장 |
|---|---|---|---|
| access | HS256 | **15분** | 클라이언트 메모리 |
| refresh | HS256 | **7일** | DB에 **해시(argon2)** 저장 |

- **회전(rotation)**: `/auth/refresh` 호출 시 새 refresh 발급 + 이전 refresh `revoked_at` 마킹.
- **재사용 감지(reuse detection)**: 이미 회전된(revoked) refresh로 호출 시 → 해당 사용자의 **모든 refresh 일괄 폐기** + 강제 로그아웃.
- 모든 refresh 액션은 `audit_log` 기록.

### 4.6 패스워드

- `argon2id`만 사용. parameters: `memoryCost=19456, timeCost=2, parallelism=1` (OWASP 2024).
- bcrypt/scrypt/PBKDF2 도입 금지.

---

## 5. API 엔드포인트 (Endpoints)

> 모든 경로는 `/v1` prefix. auth 컬럼: 🔓 익명 / 🔐 인증 / 👑 admin

### Auth (`routes/auth.ts`)
| Method | Path | Auth | 설명 |
|---|---|---|---|
| POST | `/v1/auth/signup` | 🔓 | argon2 hash 후 user 생성, access+refresh 발급 |
| POST | `/v1/auth/login` | 🔓 | credential 검증, 토큰 발급 |
| POST | `/v1/auth/refresh` | 🔓* | refresh token으로 access 재발급(회전) |
| POST | `/v1/auth/logout` | 🔐 | 현재 refresh 폐기 |
| GET  | `/v1/auth/me` | 🔐 | 현재 사용자 프로필 |

*refresh는 헤더가 아닌 body로 전달.

### Hives (`routes/hives.ts`)
| Method | Path | Auth | 설명 |
|---|---|---|---|
| GET    | `/v1/hives` | 🔐 | 내 양봉장 목록 |
| POST   | `/v1/hives` | 🔐 | 양봉장 등록 |
| GET    | `/v1/hives/:id` | 🔐 | 단일 조회(소유 검증) |
| PATCH  | `/v1/hives/:id` | 🔐 | 부분 수정 |
| DELETE | `/v1/hives/:id` | 🔐 | soft delete |

### Analyses (`routes/analyses.ts`)
| Method | Path | Auth | 설명 |
|---|---|---|---|
| POST | `/v1/analyses` | 🔐 | 이미지 분석 요청. quota 검사 후 AI 위임 |
| GET  | `/v1/analyses` | 🔐 | 내 분석 이력(pagination) |
| GET  | `/v1/analyses/:id` | 🔐 | 단일 결과(dual-result 모드 시 두 엔진 응답) |

### Images (`routes/images.ts`)
| Method | Path | Auth | 설명 |
|---|---|---|---|
| POST | `/v1/images/presign` | 🔐 | S3 presigned PUT URL 발급 |
| POST | `/v1/images/confirm` | 🔐 | 업로드 완료 확인 + 메타 등록 |

### Admin (`routes/admin.ts`)
| Method | Path | Auth | 설명 |
|---|---|---|---|
| GET    | `/v1/admin/users` | 👑 | 사용자 목록 |
| PATCH  | `/v1/admin/users/:id` | 👑 | role/상태 변경 |
| GET    | `/v1/admin/audit-logs` | 👑 | 감사 로그 조회 |
| GET    | `/v1/admin/metrics` | 👑 | 운영 지표 |

### Subscriptions (`routes/subscriptions.ts`)
| Method | Path | Auth | 설명 |
|---|---|---|---|
| GET  | `/v1/subscriptions/me` | 🔐 | 현재 구독 상태 |
| POST | `/v1/subscriptions/webhook` | 🔓** | 결제 PG webhook |

**서명(HMAC) 검증 미들웨어로 보호.

---

## 6. AI 서비스 호출 (`services/ai-client.ts`)

AI 추론은 별도 서비스(`services/ai`, FastAPI/Triton 등)에 위임. backend는 axios 클라이언트로만 호출.

```
[apps/api]  ──axios──▶  [services/ai]  ──▶  모델 추론
            ◀──json──
```

**클라이언트 설정**:
- `timeout: 30_000` (30초)
- **재시도 2회** — 지수 백오프(500ms → 1500ms), 5xx/네트워크 에러만. 4xx는 재시도 안 함.
- **engine=auto fallback** — 기본 엔진 실패 시 fallback 엔진으로 자동 재시도. 양쪽 다 실패해야 503.
- **dual-result 모드** — `?engine=dual` 파라미터 시 두 엔진 응답을 병렬 호출하고 둘 다 반환. 응답 스키마: `{ primary, secondary, agreement }`.
- 모든 호출은 `request-id` 헤더 propagation.

**위치**: `services/ai-client.ts`. AI 응답 정규화는 여기서 수행하고 라우트는 그대로 envelope 처리.

---

## 7. 이미지 업로드 흐름

S3 presigned PUT 패턴 — 서버는 바이너리를 받지 않는다.

```
1. Client → POST /v1/images/presign  (filename, contentType)
2. Server → presigned PUT URL + objectKey 반환  (5분 유효)
3. Client → S3 직접 PUT (presigned URL)
4. Client → POST /v1/images/confirm  (objectKey)
5. Server → HEAD S3, 매직넘버 검증, EXIF 제거, DB 메타 등록
```

**검증 정책**:
- 허용 mime: `image/jpeg`, `image/png`, `image/webp`만.
- 최대 크기: **10 MB**.
- **매직넘버 sniff** — `Content-Type` 헤더 신뢰 금지. 첫 12바이트로 실제 타입 판별.
- **EXIF 제거** — GPS/카메라 메타데이터 제거 후 재저장(`sharp`로 rotate + strip).
- 검증 실패 시 S3 객체 즉시 delete + 4xx Problem 응답.

S3 키 패턴: `images/{userId}/{yyyy}/{mm}/{uuid}.{ext}`.

---

## 8. 레이트리밋 / 캐싱 (Redis)

**sliding window** 알고리즘 (`middleware/rate-limit.ts`).

| 대상 | 제한 |
|---|---|
| 익명 IP | 60 req/min |
| 인증 사용자 | 300 req/min |
| `POST /v1/analyses` | **10 req/min** + **무료 4회/월** quota |

**무료 quota 카운터**: Redis key `quota:{userId}:{YYYYMM}` (월간, TTL = 월말까지).
- 분석 시작 시 `INCR` 후 5 이상이면 `QUOTA_EXCEEDED` (402).
- 유료 구독자는 quota 검사 스킵.

**캐싱**:
- `GET /v1/hives` 등 read-heavy: `cache:hives:{userId}` TTL 60s.
- write 시 즉시 invalidate.

---

## 9. 로깅 / 감사 (Logging & Audit)

### 9.1 pino structured logging

모든 요청에 다음 필드 포함:
```json
{ "requestId":"...", "userId":"...", "route":"GET /v1/hives", "latencyMs":42, "status":200 }
```

- 민감 필드(password, token, presigned URL 쿼리스트링)는 redact.
- 프로덕션은 JSON, 로컬은 pino-pretty.

### 9.2 감사 로그(audit_log)

다음 액션은 `audit_log` 테이블에 insert (PII 최소화):
- 로그인/로그아웃/refresh 회전/재사용 감지
- 패스워드/이메일 변경
- role 변경(admin)
- 결제/구독 상태 변경
- admin 데이터 수정

스키마: `id, userId, actorId, action, target, metadata(jsonb), ip, userAgent, createdAt`.

---

## 10. 로컬 개발 (Local Dev)

```bash
# 1. 인프라 기동
docker compose up -d postgres redis

# 2. 마이그레이션 (packages/database 워크스페이스)
pnpm --filter @helpbee/database migrate

# 3. API 개발 서버
pnpm --filter api dev      # tsx watch + .env.local 로드
```

기본 포트: `3000`. health check: `GET http://localhost:3000/health`.

### Bruno

`apps/api/bruno/` 디렉터리가 Bruno 컬렉션 루트. 각 도메인별 폴더(`auth/`, `hives/`, ...)에 `.bru` 파일.
환경 파일: `bruno/environments/local.bru`, `staging.bru`.

신규 엔드포인트 추가 시 **반드시 Bruno 요청도 같이 추가** (체크리스트 참조).

---

## 11. 테스트 (Testing)

- 러너: `vitest`
- 라우트 테스트: Hono의 `app.request(...)` 사용 — 실제 listen 없이 in-process.
- DB 격리: **Testcontainers**로 매 test suite마다 깨끗한 Postgres 컨테이너.
- Redis 격리: 별도 db number(`db: 15`) 사용 + 매 테스트 `FLUSHDB`.

```bash
pnpm --filter api test           # 전체
pnpm --filter api test -- auth   # 파일명 필터
pnpm --filter api test:watch
```

테스트 헬퍼는 `src/tests/helpers/`. 공통 fixture, test app factory, JWT 발급 유틸 등.

**커버리지 목표**: routes 80%, services/lib 90%.

---

## 12. packages 의존성

apps/api는 다음 워크스페이스 패키지에 의존:

| 패키지 | 용도 |
|---|---|
| `@helpbee/database` | Drizzle 스키마 + 쿼리 함수. **DB 접근은 여기를 통해서만.** |
| `@helpbee/types` | DTO/도메인 타입 (Flutter/Admin과 공유) |

> **직접 SQL 금지.** `pg.query(...)` 도 금지. 모든 쿼리는 `@helpbee/database/queries/*`에 함수로 정의하고 import해서 사용.

---

## 13. AI 작업 가이드라인 (Coding Agent Guidelines)

### 13.1 새 라우트 추가 절차

1. `schemas/{domain}.ts` — zod 스키마 정의 (입력/출력)
2. `routes/{domain}.ts` — Hono 라우터 + `zValidator` + `requireAuth` 등 미들웨어 조합
3. 비즈니스 로직이 복잡하면 `services/{domain}-service.ts`로 분리
4. DB 접근은 `@helpbee/database`에 쿼리 함수 추가 후 import
5. `tests/{domain}.test.ts` 작성
6. `bruno/{domain}/*.bru` 요청 추가
7. 감사 로그가 필요한 액션이면 `audit_log` insert 누락 점검

### 13.2 반드시 지킬 것

- ✅ **모든 입력은 zod로 검증** — `zValidator` 또는 명시적 `.parse()`.
- ✅ **DB 쿼리는 `packages/database/queries/*` 만 사용** — 직접 SQL 금지.
- ✅ **응답은 envelope** — `ok(c, data)` / `problem(c, code, ...)` 만.
- ✅ **에러 코드는 enum에 등록**.
- ✅ **민감 액션은 audit_log 기록**.
- ✅ **Bruno 요청 동시 갱신**.
- ❌ **환경변수는 `config/env.ts`를 통해서만** — `process.env.X` 직접 참조 금지.

### 13.3 파일 작업 규칙

- 파일 삭제는 `rm` 금지. **`trash <path>`** 사용 (macOS 휴지통 보냄, 복구 가능).
- 보안 hook(`~/.claude/hooks/block_dangerous.py`)이 다음을 자동 차단:
  - `rm`, `unlink`
  - `git reset --hard`, `git push --force`/`-f`, `git clean -f`, `git checkout .`, `git stash drop`, `git branch -D`
  - `DROP DATABASE/TABLE`, `TRUNCATE TABLE`
- 차단되었다고 우회하지 말 것 — 항상 안전한 대안 사용.

### 13.4 보안 주의사항

- 클라이언트 입력을 SQL/명령어/경로에 **절대 직접 보간하지 않는다** (Drizzle parameterize에 맡김).
- presigned URL의 쿼리스트링은 로그에 redact.
- `Authorization` 헤더, `set-cookie`, refresh token 본문은 로그에 redact.
- CORS는 `config/env.ts`의 allowlist 기반 — 와일드카드 `*` 금지.

---

## 📋 개발 계획 (마스터 플랜 발췌)

### API 엔드포인트 요약 (`/api/v1`)
응답 봉투 `{data, meta}`, 에러는 RFC 7807 (`application/problem+json`).

| 도메인 | 메서드/경로 | 인증 |
|---|---|---|
| Auth | POST /auth/{signup,login,refresh,logout}, GET /auth/me | mixed |
| Hives | GET/POST /hives, GET/PATCH/DELETE /hives/:id | auth + 소유권 |
| Analyses | POST /analyses, GET /analyses?hiveId=&from=&to=, GET /analyses/:id, GET /analyses/trend?hiveId=&granularity=day\|week | auth |
| Images | POST /images/presign, DELETE /images/:key | auth |
| Admin | GET /admin/{users,users/:id,analyses,stats} | role=admin |
| Subscriptions | GET /subscriptions/me, GET /subscriptions/plans (정적 stub) | auth (me) |

### 주요 정책
- **JWT**: HS256, access 15분 / refresh 7일. Refresh DB 해시 저장 + 회전 + 재사용 감지 시 전체 폐기
- **패스워드**: argon2 (bcrypt보다 GPU 저항성 우수)
- **레이트리밋 (Redis)**: 익명 60req/min, 인증 300req/min, /analyses POST 10/min + 무료 4회/월 (`quota:{userId}:{YYYYMM}`)
- **AI 호출**: axios baseURL=AI_BASE_URL, timeout 30s, 5xx/timeout 지수 백오프 2회. engine='auto' 시 OpenAI 1차 → 실패/저신뢰 시 YOLO 폴백. dual-result(관리자 전용) 동시 호출 → raw_response jsonb
- **이미지 업로드**: S3 presigned PUT 흐름. jpeg/png/webp 10MB 매직넘버 sniff. EXIF 제거. multipart 프록시 백업
- **로그**: pino 구조화 (requestId/userId/route/latencyMs), 민감 동작은 audit_log insert

### 마일스톤
- **5월 W1**: env/config, DB/Redis 부트, auth + JWT + argon2, hives CRUD, 에러/검증 미들웨어
- **5월 W2**: images presign, analyses CRUD, AI client, trend 집계, 쿼터
- **5월 W3**: admin 라우터, subscriptions stub, audit, pino, 레이트리밋
- **5월 W4**: 통합 테스트, Bruno 컬렉션, 보안 점검 (헬멧, CORS)

### 검증
- Bruno 컬렉션 (@apps/api/bruno/) 도메인별 폴더 + 환경
- vitest + Hono `app.request` 통합 테스트, Testcontainers DB 격리
- CI 게이트: type-check, lint, test

### 리스크 / 미해결
- AI 동기 호출 SLA 적합성 — 10s 초과 시 BullMQ 큐 전환 검토
- S3 vs Cloudflare R2 — 한국 latency/비용 비교 필요
- jwt-simple → jose 교체 검토 (알고리즘 강제·키 회전)
- 무료 쿼터 월 경계 (UTC vs KST) 합의 필요
- EXIF/위치정보 보존 vs 삭제 정책 (개인정보)

### 다른 분야와의 인터페이스 (정합 포인트)
- **← DB** (@packages/database): queries/* helper만 사용, 직접 SQL 금지
- **→ AI** (@apps/ai): HTTP /analyze, /analyze/dual, /analyze/yolo 호출. AI 응답 스키마 변경 시 services/ai-client.ts 동기화
- **→ Flutter** (@apps/mobile), **Admin** (@apps/admin): Bruno 컬렉션을 OpenAPI 대용으로 공유. packages/types 동기화 필수

---

## 14. PR 체크리스트

라우트/스키마/서비스를 추가/수정한 PR은 다음을 확인:

- [ ] `pnpm --filter api lint` 통과
- [ ] `pnpm --filter api type-check` 통과
- [ ] `pnpm --filter api test` 통과 (신규 코드 커버리지 포함)
- [ ] zod 스키마가 `schemas/` 에 있고 라우트에서 `zValidator` 사용
- [ ] DB 접근은 `@helpbee/database` 쿼리 함수만 사용 (직접 SQL 0건)
- [ ] 응답이 `{data, meta}` envelope, 에러는 RFC 7807 (`application/problem+json`)
- [ ] 신규 에러는 `lib/error-codes.ts` enum에 등록
- [ ] 인증/권한 미들웨어 누락 없음 (`requireAuth`, `requireRole`)
- [ ] 민감 액션에 `audit_log` insert 포함
- [ ] Bruno 컬렉션(`bruno/`)에 요청 추가/갱신
- [ ] 환경변수 신규 추가 시 `config/env.ts` zod 스키마 갱신 + `.env.example` 갱신
- [ ] 로그에 PII/secret redact 확인
- [ ] 레이트리밋 / quota 영향 검토 (특히 `/analyses`)

---

## 부록: 자주 쓰는 명령어

```bash
# 개발
pnpm --filter api dev
pnpm --filter api test
pnpm --filter api type-check

# 인프라
docker compose up -d postgres redis
docker compose logs -f api

# DB
pnpm --filter @helpbee/database migrate
pnpm --filter @helpbee/database studio   # Drizzle Studio
```

> 이 문서가 cold-pickup 가능하지 않다고 느끼면 즉시 갱신할 것. 추측 금지.
