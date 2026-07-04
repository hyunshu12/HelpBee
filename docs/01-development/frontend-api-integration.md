# 프론트엔드 ↔ 백엔드 API 연동 가이드

> **목적**: `apps/mobile`(Flutter) · `apps/web` · `apps/admin` 프론트엔드를 만들 때 백엔드(`apps/api`)에
> 바로 붙일 수 있도록 **실제 구현된** 계약을 정리한 단일 진실 소스.
> 이 문서는 설계서(`backend-design.md`)가 아니라 **현재 머지된 코드(`apps/api/src/routes/*`, `schemas/*`)** 기준이다.
>
> **작성/검증**: 2026-06-11, develop 머지분(PR #19~#22) 기준. 백엔드 변경 시 이 문서도 갱신할 것.
>
> ⚠️ **먼저 읽기 — "현재 되는 것 / 안 되는 것"은 맨 아래 §10 Readiness 섹션.** 일부 기능은 코드만 있고 실제로는 아직 동작하지 않는다.

---

## 0. 한눈에

- **Base URL**: 로컬 `http://localhost:3001`, 모든 비즈니스 경로는 `/v1` prefix. (staging/prod URL은 아직 없음 — §10)
- **인증**: `Authorization: Bearer <accessToken>` 헤더. **refresh 토큰은 헤더가 아니라 body로** 전달.
- **성공 응답 봉투**: 모든 2xx는 `{ data, meta }`.
- **에러**: RFC 7807 `application/problem+json` — `{ type, title, status, code, detail, instance, requestId }`. 분기는 항상 **`code`(문자열 enum)** 로.
- **요청 추적**: 응답 헤더 `x-request-id` echo(클라가 보내면 유지, 없으면 서버 생성). 로그 상관관계용.

### 0.1 성공 봉투
```jsonc
{
  "data": { /* 실제 페이로드 */ },
  "meta": {
    "requestId": "uuid",
    "timestamp": "2026-06-11T00:00:00.000Z",
    "pagination": { "limit": 50, "offset": 0, "total": 12 }  // list 응답에만
  }
}
```

### 0.2 에러 봉투 (problem+json)
```jsonc
{
  "type": "https://helpbee.io/errors/quota-exceeded",
  "title": "Quota exceeded",
  "status": 402,
  "code": "QUOTA_EXCEEDED",   // ← 클라는 이걸로 분기
  "detail": "free tier limit (4/month) reached",
  "instance": "/v1/analyses",
  "requestId": "uuid"
}
```

---

## 1. 인증 (`/v1/auth`)

| Method | Path | 인증 | 요청 body | 성공 |
|---|---|---|---|---|
| POST | `/v1/auth/signup` | 🔓 | `{ email, password, name }` | **201** `{ user, accessToken, refreshToken, expiresIn:900 }` |
| POST | `/v1/auth/login` | 🔓 | `{ email, password }` | **200** 동일 |
| POST | `/v1/auth/refresh` | 🔓 | `{ refreshToken }` | **200** `{ accessToken, refreshToken, expiresIn:900 }` |
| POST | `/v1/auth/logout` | 🔐 | `{ refreshToken }` | **200** `{ revoked:true }` |
| GET | `/v1/auth/me` | 🔐 | — | **200** `{ user, subscription:{ plan, status } }` |

- **입력 규칙**: `email`(정규화됨), `password` signup은 **10자 이상**·128 이하, `name` 1~60.
- **`user` (PublicUser)** — 비밀번호 해시 절대 미포함:
  ```ts
  { id, email, name, role: 'user'|'admin', emailVerified: boolean, createdAt: ISO }
  ```

### 1.1 토큰 정책 (클라 필독)
- **access**: HS256, **15분**. **메모리에만 저장**(영속 금지). 만료 시 `AUTH_TOKEN_EXPIRED`(401).
- **refresh**: **7일**. **안전 저장소**(Flutter `flutter_secure_storage` / 웹은 httpOnly 쿠키 권장).
- **회전(rotation)**: `/refresh` 호출마다 **새 refreshToken**을 받는다 → 받은 즉시 기존 것을 교체 저장. (옛 refresh는 폐기됨)
- **401 처리 루프**: 보호 API가 `AUTH_TOKEN_EXPIRED`(401) → `/refresh` 호출 → 새 토큰으로 원요청 1회 재시도.
- **동시 refresh(grace)**: 여러 요청이 동시에 만료돼 `/refresh`를 동시 발사하면, **승자만** 새 토큰을 받고 **패자는 `AUTH_REFRESH_INVALID`(401)**. 패자는 강제 로그아웃하지 말고 **승자가 받은 새 access로 재시도**할 것(전체 세션은 유지됨).
- **재사용 감지**: 폐기된 refresh를 grace 밖에서 다시 쓰면 `REFRESH_REUSE_DETECTED`(401) + 그 사용자의 **모든 세션 폐기**(보안). 이 경우엔 로그인 화면으로.

### 1.2 주요 에러 코드
| code | status | 의미 / 클라 처리 |
|---|---|---|
| `AUTH_INVALID_CREDENTIALS` | 401 | 로그인 실패(존재/불일치 통합 — enumeration 방지) |
| `AUTH_ACCOUNT_LOCKED` | 429 | 로그인 실패 누적 잠금. `Retry-After` 헤더 초만큼 대기 |
| `AUTH_EMAIL_TAKEN` | 409 | signup 이메일 중복 |
| `AUTH_TOKEN_EXPIRED` | 401 | access 만료 → refresh |
| `AUTH_UNAUTHORIZED` | 401 | access 누락/위조 → 로그인 |
| `AUTH_REFRESH_INVALID` | 401 | refresh 무효(만료/회전됨) |
| `REFRESH_REUSE_DETECTED` | 401 | 재사용 감지 → 강제 로그아웃 |
| `AUTH_EMAIL_NOT_VERIFIED` | 403 | 이메일 미인증(분석 진입 차단 — §10 주의) |
| `RATE_LIMITED` | 429 | 레이트리밋(`Retry-After`). signup 5/분·login·refresh 10/분 per IP |

---

## 2. 양봉장 Hives (`/v1/hives`) — 전부 🔐

| Method | Path | 요청 | 성공 |
|---|---|---|---|
| GET | `/v1/hives` | query `{ limit?(1-100,d50), offset?(0-10000,d0) }` | 200 `Hive[]` + pagination |
| POST | `/v1/hives` | `{ name, note?, latitude?, longitude?, address?, installedAt? }` | 201 `Hive` |
| GET | `/v1/hives/:id` | — | 200 `Hive` / 404 |
| PATCH | `/v1/hives/:id` | 위 필드 부분(≥1) | 200 `Hive` / 404 |
| DELETE | `/v1/hives/:id` | — | 200 `{ id, deletedAt }` / 404 (soft delete) |

- **`Hive`**: `{ id, userId, name, note, latitude, longitude, address, installedAt, createdAt, updatedAt, deletedAt }`.
  - ⚠️ `latitude`/`longitude`는 PostgreSQL numeric이라 **문자열**(`"37.566500"`)로 온다. 클라에서 `parseFloat`.
- **좌표는 쌍으로**: latitude/longitude는 둘 다 보내거나 둘 다 생략(반쪽이면 400).
- **IDOR**: 남의 hive id로 접근하면 403이 아니라 **404 `NOT_FOUND`**(존재 누설 방지). `:id`는 uuid 아니면 400.
- **Mass Assignment 차단**: `userId`/`deletedAt` 등 모르는 키를 body에 넣으면 400. 보내지 말 것.

---

## 3. 이미지 업로드 (`/v1/images`) — 전부 🔐

서버는 바이너리를 받지 않는다. **presign → S3 직접 PUT → confirm** 3단계.

```
1) POST /v1/images/presign  { filename, contentType }  → { uploadUrl, objectKey, expiresIn:300 }
2) 클라가 uploadUrl 로 S3에 직접 PUT (헤더 Content-Type 일치, Authorization 헤더 없이!)
3) POST /v1/images/confirm  { objectKey, hiveId, capturedAt? }  → 201 AnalysisImage
```

| Method | Path | 요청 | 성공 / 에러 |
|---|---|---|---|
| POST | `/v1/images/presign` | `{ filename, contentType: 'image/jpeg'\|'image/png'\|'image/webp' }` | 200 `{ uploadUrl, objectKey, expiresIn:300 }` / `UNSUPPORTED_MEDIA`(415) |
| POST | `/v1/images/confirm` | `{ objectKey, hiveId(uuid), capturedAt? }` | 201 `AnalysisImage` / `IMAGE_TOO_LARGE`(413)·`IMAGE_INVALID`(422)·`IMAGE_NOT_FOUND_IN_STORAGE`(404)·`NOT_FOUND`(404 hive) |

- **`AnalysisImage`**: `{ id, hiveId, uploadedBy, storageUrl, mimeType, width, height, byteSize, checksum, capturedAt, createdAt }`.
- presign URL 만료 **5분**. presign rate-limit 30/분/user.
- 서버가 confirm 시 매직넘버 검증 + 10MB 제한 + EXIF/GPS strip 후 재인코딩. **클라도 업로드 전 1920px 리사이즈·EXIF GPS 제거** 권장(모바일 §8).
- confirm으로 받은 `image.id`가 분석 요청(§4)의 입력.

---

## 4. 분석 Analyses (`/v1/analyses`) — 전부 🔐

| Method | Path | 요청 | 성공 |
|---|---|---|---|
| POST | `/v1/analyses` | `{ hiveId, imageId }` | **201**(새 분석 완료, 동기) 또는 **200**(멱등 기존/실패) |
| GET | `/v1/analyses` | query `{ hiveId, limit?, offset? }` | 200 `Analysis[]` + pagination |
| GET | `/v1/analyses/trend` | query `{ hiveId, from?, to? }` (ISO) | 200 `[{ bucket, avgRisk, analysisCount }]` |
| GET | `/v1/analyses/:id` | — | 200 `Analysis` / 404 |

- **동기 처리**: `POST`는 추론 완료된 리소스를 즉시 반환(pending 폴링 없음). `201`=신규, `200`=같은 이미지 재요청(기존 반환, 재과금 0).
- **`Analysis`**:
  ```ts
  { id, hiveId, imageId, modelId,
    status: 'pending'|'success'|'failed',
    varroaInfectionRisk: number|null,        // 0~100 (위험도)
    estimatedVarroaCount: number|null,
    overallHealth: 'healthy'|'warning'|'critical'|null,
    rawResponse, latencyMs, error,
    analyzedAt, createdAt, updatedAt,
    recommendations?: { order, content, severity }[] }  // POST · GET /:id 만 (아래)
  ```
  - tier(safe/watch/danger)는 별도 컬럼이 없고 `overallHealth`(healthy/warning/critical)로 매핑됨.
- **실패 처리**: AI 실패 시 throw가 아니라 **200 + `status:'failed'`** (UX 비차단). 프론트는 `status==='failed'`일 때 "분석 실패, 재시도" UI 필요.
- **재시도(retry)**: `status:'failed'`인 이미지에 **같은 `{hiveId, imageId}`로 `POST` 재요청**하면 백엔드가 그 **failed 행을 제자리에서 재추론·갱신**한다(같은 `id` 유지, `status`/risk/health/recommendations/`error`/`analyzedAt` 새로 채움). 성공하면 **200**(신규 201 아님) + 채워진 결과, 또 실패하면 **200** + `status:'failed'`(새 error). `success` 행은 재요청해도 재실행 없이 그대로 반환(멱등). failed는 quota를 소비하지 않으므로 재시도도 신규와 동일한 reserve/refund 경로를 탄다.
- **무료 사용자 quota**: `POST`는 무료 월 4회 + 10/분/user. 초과 시 `QUOTA_EXCEEDED`(402). 이메일 미인증이면 `AUTH_EMAIL_NOT_VERIFIED`(403).
- **권장조치(recommendations)**: tier에서 파생된 한국어 처방/주의 문구 배열.
  - **포함**: `POST /v1/analyses`(신규·멱등·실패 모두)와 `GET /v1/analyses/:id`. **목록** `GET /v1/analyses`는 페이로드 크기상 **미포함**(빈 배열로 취급).
  - 각 항목: `{ order:number, content:string, severity:'info'|'warn'|'danger' }`. `order` 오름차순 표시. `severity`는 tier 매핑(safe→info / watch→warn / danger→danger).
  - `status:'failed'`이면 빈 배열 `[]`. YOLO 결과에는 "AI 추정치는 참고용…실측 병행" 정직성 안내가 마지막에 붙을 수 있음(≤5개).

---

## 5. 구독 Subscriptions (`/v1/subscriptions`)

| Method | Path | 인증 | 성공 |
|---|---|---|---|
| GET | `/v1/subscriptions/me` | 🔐 | `{ plan, status, trialEndsAt, currentPeriodEnd, features:{ openaiFallback, monthlyAnalysisQuota } }` |
| GET | `/v1/subscriptions/plans` | 🔓 | `{ plans:[{ id, name, monthlyAnalysisQuota, openaiFallback, priceKrwMonthly }] }` |
| POST | `/v1/subscriptions/webhook` | 🔓** | 결제 PG용 — **MVP inert**(기본 `WEBHOOK_DISABLED` 503) |

- `features.monthlyAnalysisQuota`: 무료=4, 유료-active=`null`(무제한).
- 결제는 미구현(모두 무료). `/plans`는 가격 표시용 정적 카탈로그.

---

## 6. 어드민 Admin (`/v1/admin`) — `apps/admin` 전용, 👑

**admin 토큰 필요**: `role==='admin'` + 토큰 audience=admin. 일반 사용자 토큰으론 전부 **403 `FORBIDDEN_ROLE`**, 무인증은 401.
> admin 계정은 일반 signup으론 못 만든다(항상 role=user). 운영자가 DB/다른 admin의 `PATCH /admin/users/:id`로 승격. 승격 후 **재로그인**해야 admin audience 토큰을 받는다.

| Method | Path | 요청 | 성공 |
|---|---|---|---|
| GET | `/v1/admin/users` | query `{ page?, pageSize?(≤100), search?, role?, status? }` | `AdminUserRow[]` + pagination |
| PATCH | `/v1/admin/users/:id` | `{ role?:'user'\|'admin', status?:'active'\|'blocked' }` | `AdminUserDetail` / `ADMIN_SELF_DEMOTE_FORBIDDEN`(409) |
| GET | `/v1/admin/audit-logs` | query `{ cursor?, limit?, entity?, action?, actorId?, from?, to? }` | `{ items:[AuditLogRow], nextCursor }` |
| GET | `/v1/admin/metrics` | query `{ from?, to?, granularity? }` | 집계 `{ users, analysesByStatus, analysesByProvider, subscriptionsByPlan }` |
| GET | `/v1/admin/analyses/:imageId/dual` | — | `{ primary, secondary, agreement }` (두 엔진 비교) |

- `status`는 파생: `deleted_at`→deleted / `blocked_at`→blocked / else active.
- 사용자 차단(`status:'blocked'`) 시 백엔드가 즉시 세션 회수(해당 사용자 강제 로그아웃됨).
- audit-logs는 **cursor 페이지네이션**(`nextCursor`를 다음 요청 `cursor`로). `id`는 문자열.
- dual의 `rawResponse`는 화이트리스트 투영됨(bbox/score/tier만, URL/GPS/PII 제거됨).

---

## 7. 횡단 관심사

### 7.1 레이트리밋
| 대상 | 한도 | 초과 |
|---|---|---|
| signup | 5/분/IP | `RATE_LIMITED`(429)+`Retry-After` |
| login·refresh | 10/분/IP | 〃 |
| presign | 30/분/user | 〃 |
| 인증 사용자(전역) | 300/분/user | 〃 |
- Redis 장애 시 **fail-closed**(429). 프론트는 429+Retry-After를 백오프 처리.

### 7.2 CORS (웹/어드민만 해당, Flutter 앱은 무관)
- 브라우저 앱은 자기 **origin이 백엔드 `CORS_ALLOWLIST` env에 등록**돼야 호출 가능. 와일드카드(`*`) 없음.
- 로컬 개발 시 백엔드 띄울 때 `CORS_ALLOWLIST=http://localhost:3000,http://localhost:3001` 처럼 프론트 origin 포함.
- credentials(쿠키) 사용 시 allowlist 매칭돼야 `Access-Control-Allow-Credentials`가 붙는다.

### 7.3 전체 에러 코드 카탈로그
`apps/api/src/lib/error-codes.ts` 참조. 자주 만나는 것: `VALIDATION_FAILED`(400), `NOT_FOUND`(404, IDOR 포함), `RATE_LIMITED`(429), `QUOTA_EXCEEDED`(402), `AI_UNAVAILABLE`(503), `INTERNAL`(500). **detail은 사용자에게 그대로 노출 금지**(영문·내부 설명) — `code`로 자체 한국어 메시지 매핑할 것.

---

## 8. 타입 공유 (`packages/types`)
- 현재 `packages/types`는 거의 비어 있음(스캐폴드). DTO 타입을 프론트와 공유하려면 이 패키지를 채우거나, 프론트에서 직접 정의(Flutter는 freezed, 웹/어드민은 ts) 후 본 문서와 정합 유지.
- 백엔드 DB 추론 타입(`@helpbee/database`의 `Analysis`/`Hive`/`User` 등)이 사실상 진실의 원천. 응답 형태는 위 각 섹션 기준.

---

## 9. 로컬에서 백엔드 띄우기 (프론트 개발용)
```bash
# 1) 인프라 (모노레포 루트)
docker compose up -d postgres redis

# 2) 마이그레이션 적용 (또는 psql로 migrations/0000_*.sql, 0001_*.sql 순서 적용)
DATABASE_URL=postgresql://helpbee_user:helpbee_password@localhost:5432/helpbee \
  pnpm --filter @helpbee/database migrate

# 3) API 서버 (필수 env — 길이/중복 검증 fail-fast)
DATABASE_URL=postgresql://helpbee_user:helpbee_password@localhost:5432/helpbee \
REDIS_URL=redis://localhost:6379 \
JWT_SECRET=<64자 이상, 플레이스홀더 금지> \
REFRESH_TOKEN_PEPPER=<32자 이상, JWT_SECRET과 다른 값> \
AI_BASE_URL=http://localhost:8000 \
AI_INTERNAL_HMAC_SECRET=<32자 이상, JWT_SECRET과 다른 값> \
S3_IMAGES_BUCKET=helpbee-images-dev \
CORS_ALLOWLIST=http://localhost:3000,http://localhost:3001 \
  pnpm --filter api dev
# health: curl http://localhost:3001/health
```
- 전체 env 목록·기본값은 `apps/api/src/config/env.ts` + `.env.example` 참조.
- 모바일 앱은 `--dart-define=API_BASE=http://10.0.2.2:3001`(Android 에뮬레이터) 등으로 주입.

---

## 10. ⚠️ 현재 가동 상태 (Readiness) — 프론트 붙이기 전 반드시 확인

| 영역 | 상태 | 프론트 영향 |
|---|---|---|
| Auth / Hives / Images(presign·confirm) / Subscriptions / Admin **계약** | ✅ 코드 완성·로컬 검증 | 그대로 붙이면 됨 |
| **AI 추론 실제 동작** | ❌ **아직 안 됨** | AI 서버 미기동 + YOLO 모델(`best.onnx`) 미배포. 현재 `POST /analyses`는 **graceful `status:'failed'`(200)** 로만 응답. 결과 화면은 `failed` 상태 처리 UI를 먼저 만들 것 |
| **이메일 인증 발송** | 🔴 미구현 | 무료 사용자(=현재 전원)는 `email_verified` 전까지 분석 차단(`AUTH_EMAIL_NOT_VERIFIED` 403). 개발 중엔 DB에서 `users.email_verified_at` 수동 set 하거나, 백엔드에 발송 추가 후 테스트 |
| **권장조치(recommendations) 응답** | ✅ 반환 | `POST /analyses`·`GET /analyses/:id`가 `recommendations[{order,content,severity}]` 포함(목록은 미포함). 결과 화면 처방 문구 표시 가능(§4) |
| **인프라 배포(staging/prod)** | 🔴 미배포 | 원격 base URL 없음. 현재 **localhost:3001** 만. 배포 후 환경별 URL 주입 |
| **결제** | 🟡 inert | 전원 무료. 유료 UI는 표시만(`/plans`) |

> **요약**: 로그인/회원가입/벌통 관리/이미지 업로드 흐름은 **지금 바로 붙여 개발 가능**. **AI 분석 결과 화면**은 (a) 실패 상태 UI 먼저 + (b) 추론 환경(모델·AI서버)·이메일 인증이 갖춰지면 실데이터로 완성. 권장조치(recommendations) 반환은 이제 계약에 포함됨. admin 화면은 admin 토큰 발급(DB 승격)만 되면 전부 동작.

---

## 11. 참고
- 라우트 구현: `apps/api/src/routes/{auth,hives,images,analyses,subscriptions,admin}.ts`
- 입력 스키마: `apps/api/src/schemas/*`
- 에러 코드: `apps/api/src/lib/error-codes.ts`
- 응답 봉투: `apps/api/src/lib/envelope.ts`, 에러: `apps/api/src/lib/problem.ts`
- 전체 설계 배경(왜 이렇게): `docs/01-development/backend-design.md`
- Bruno 컬렉션(있으면): `apps/api/bruno/` — 실호출 예시
