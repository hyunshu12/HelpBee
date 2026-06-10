# HelpBee 백엔드 설계 — AI 추론 + 데이터 저장 (전체 도메인·보안)

> **상태**: 설계 확정 (코드 미구현, 설계 문서 단계) · **작성일**: 2026-06-10 · **범위**: 전체 백엔드 (`apps/api` 오케스트레이션 + `apps/ai` 추론 + `@helpbee/database` 저장)
> **선행 문서**: [ADR-0001 YOLO 엔진](adr/ADR-0001-yolo-engine-architecture.md) · DB 스키마 [`packages/database`](../../packages/database/CLAUDE.md) · UX 제약 [`docs/06-design-handoff`](../06-design-handoff/README.md)
> **대체**: 본 문서가 [`architecture.md`](architecture.md)(구버전, EKS 마이크로서비스 가정)를 대체하는 현재 백엔드 권위 설계다.

이 문서는 2026-06-10 브레인스토밍 세션의 산출물로, 사용자 확정 결정 11건 위에 울트라코드 워크플로우(다각도 비판 → YAGNI/보안 게이트 → 합성)로 강화한 설계다. **1부**는 추론·저장 핵심, **2부**는 전체 도메인 계약 + 엄격 보안(OWASP API Top10 + PIPA)을 다룬다.

## 확정 결정 요약 (11건 + 보안)

| # | 결정 | 값 |
|---|---|---|
| 1 | 결과물 | 설계 문서 (코드 미구현) |
| 2 | 기본 추론 엔진 | 자체 **YOLO v0.1.0**(CPU ONNX, P95 263ms) + **OpenAI 폴백(유료 전용)**. 무료=YOLO 단독 |
| 3 | 처리 방식 | **동기(sync)** — `POST /v1/analyses`가 완성 리소스 반환(pending 미영속) |
| 4 | 범위 | 전체 백엔드 (auth·hives·images·analyses·subscriptions·admin) |
| 5 | 저장 전략 | 사용된 엔진 **1행만**(정상=YOLO/폴백=OpenAI), 비교는 어드민 `/analyze/dual` 전용 |
| 6 | 오케스트레이션 | **Hybrid C** — api=정책/영속/감사, ai=추론/폴백 실행+풍부한 메타 |
| 7 | 무료 쿼터 | **reserve-then-refund** + **이메일 검증 후 활성** + KST 월경계 |
| 8 | refresh 토큰 해시 | **HMAC-SHA256(pepper)** (argon2 X — 재사용 감지 가능) / 비밀번호는 argon2id |
| 9 | api↔ai 내부 인증 | 사설 서브넷+SG + **단기 HMAC 서명 bearer** (mTLS는 Phase 2) |
| 10 | admin JWT | **별도 audience/시크릿 분리** (blast radius 축소) |
| 11 | 재분석 | **재촬영(새 image_id)** 필요, 같은 image_id 재요청은 멱등 안전망 |
| + | 유료 OpenAI 폴백 | **사용자별 일 5회 cap** + 글로벌 월예산 가드 이중화 |

## 🚨 P0 운영 액션 (설계와 무관, 즉시)

보안 검토 중 발견: **2026-06-08 baseline에서 S3 업로드에 AWS ROOT 액세스 키(account `491919374695`)가 쓰인 정황**. 사실이면 즉시 — ROOT 키 비활성화·삭제, root MFA, S3 접근을 IAM task role/OIDC 전환, CloudTrail로 과거 유출 점검, `.env.example` 장기키 슬롯 제거. (자세히는 §13.1)

---

# 1부 — AI 추론 오케스트레이션 & 데이터 저장

> **확정 7개 결정 (불변 전제)**
> ① 결과물 = 백엔드 설계 문서 (코드 구현 X) · ② 기본 엔진 = 자체 YOLO v0.1.0(CPU ONNX, P95 263ms, mAP 0.916) + OpenAI Vision 폴백 · ③ 동기(sync) 처리 · ④ 전체 백엔드 범위(1부는 추론+저장 핵심) · ⑤ 사용된 엔진 1행만 저장(비교는 어드민 dual 전용) · ⑥ Hybrid C 오케스트레이션 · ⑦ MVP·1인 운영·저비용

---

## 1. 시스템 구성

```
┌──────────────┐
│  Client      │  (앱·웹: 본 설계 범위 밖. 계약만 정의)
│ (미구현)     │
└──────┬───────┘
       │ HTTPS  (JWT access, envelope {data,meta} / RFC7807 problem+json)
       ▼
┌─────────────────────────────────────────────────────────────┐
│  apps/api  (Hono :3001)   ── 정책·영속·감사 ──                │
│  auth/소유권/quota·plan 게이트 · ai-client(axios) · s3-client │
│  · createSingleAnalysis 트랜잭션 · audit_log                  │
└───┬───────────────┬───────────────────────┬──────────────────┘
    │ queries/*      │ Redis                 │ HTTP (presigned GET URL)
    ▼ (직접 SQL 0)   ▼                       ▼
┌──────────┐   ┌──────────┐        ┌──────────────────────────┐
│PostgreSQL│   │ Redis 7  │        │ apps/ai (FastAPI :8000)  │
│ 16 · 9테 │   │ quota /  │        │ 추론 전용 · DB 접근 X    │
│이블      │   │ rate /   │        │ /analyze (engine=auto)   │
│          │   │ cache    │        │ preprocess · risk.py     │
└──────────┘   └──────────┘        │ YOLO(ONNX) → OpenAI 폴백 │
                                   └───┬──────────────┬───────┘
                                       │ lazy-load     │ Vision API
                                       ▼               ▼
                              S3 helpbee-models   OpenAI Vision
                              (best.onnx)         (gpt-4o-mini)

이미지 원본: S3 helpbee-images (presigned PUT 업로드 / presigned GET 추론 전달)
```

- **apps/api** = 단일 정책·영속·감사 게이트웨이. AI 추론을 직접 수행하지 않고 `services/ai-client.ts`로 위임.
- **apps/ai** = 추론 전용. DB·Redis 직접 접근 금지. 영속화는 전부 백엔드를 거친다.
- **저장 원칙**: 모든 쓰기는 `@helpbee/database` queries 헬퍼 경유 (직접 SQL 0건).

---

## 2. 핵심 데이터 흐름 (이미지 → 추론 → 저장 → 조회, 동기)

```
[1] presign        [2] S3 PUT        [3] confirm           [4] analyses (동기)        [5] 조회
 client ─POST──▶ api    client ──▶ S3   client ─POST──▶ api    client ─POST──▶ api ──▶ ai    GET /analyses…
 {filename,           (직접 업로드)     {objectKey,hiveId,     {hiveId,imageId}    추론→저장→완성   완성 리소스
  contentType}                          capturedAt}                                리소스 반환     재조회
        ◀─ PUT URL+key (5분)                 ◀─ image_id            ◀────── analysisId+status+risk+tier+recs
```

### 단계별

1. **POST /v1/images/presign** `{filename, contentType}` → api 검증 → presigned **PUT** URL + objectKey (TTL 5분).
2. **client → S3 직접 PUT** (백엔드는 바이너리 프록시하지 않음).
3. **POST /v1/images/confirm** `{objectKey, hiveId, capturedAt}` → api:
   - HEAD S3 → **매직넘버 sniff** (jpeg/png/webp만, Content-Type 헤더 불신뢰)
   - ≤ 10MB 검증
   - **EXIF strip** — orientation 적용 후 GPS/메타 제거 (`captured_at`은 strip 전 추출)
   - `analysis_images` insert → **image_id** 반환
4. **POST /v1/analyses** `{hiveId, imageId}` → api (동기):
   - ① **소유권·일치 검증** (should): `image.uploadedBy == userId` **AND** `image.hiveId == 요청 hiveId` — 불일치 시 404/403 problem
   - ② **멱등(중복 제출) 게이트** (must): 같은 `(image_id, model_id)`에 `status='success'` 행이 있으면 **추론 스킵·기존 결과 반환**. 더블탭/네트워크 재시도 방어용 안전망이며, **재분석은 재촬영(새 image_id) 필요**(D11) — 한 이미지는 모델당 분석 1회
   - ③ **quota·rate 게이트**: **이메일 검증(email_verified) 후에만 무료 quota 활성**(미검증=0). **reserve-then-refund**: 추론 직전 원자 `INCR quota:{userId}:{YYYYMM-KST}` 예약 → 반환값 > 4면 402(원자 차단), success면 확정, **실패면 DECR 환불**, 멱등 short-circuit은 무차감. Redis 장애 시 fail-closed. 유료 skip / `/analyses` POST 10·min
   - ④ 활성 `ai_models` 조회 → **플랜별 엔진 결정: 유료 = `engine=auto`(YOLO→OpenAI 폴백) / 무료 = `engine=yolo`(폴백 X)** → `ai-client.analyze(presignedGetUrl, engine)` (**자동 재시도 없음** — §3·§5 참조)
   - **4d. ai `/analyze`**: preprocess → YOLO(ONNX) → risk.py(infestation_rate) → 폴백 판정 → (필요시) OpenAI 폴백 → 통합 응답
   - **4e. api 저장**: `engine_used → model_id` 매핑 → **`createSingleAnalysis`** 트랜잭션(analyses 1행 + recommendations N행, status=success) → 폴백 시 OpenAI 비용 기록 → audit_log insert
5. **조회**:
   - `GET /v1/analyses?hiveId=&from=&to=` (페이지네이션, **userId 필터 강제**)
   - `GET /v1/analyses/:id`
   - `GET /v1/analyses/trend?hiveId=&granularity=` (getHiveTrend, INNER JOIN으로 소유권 강제)

### 동기 ↔ 폴링 계약 봉합 (must)

확정 결정 ③(동기)과 이미 머지된 design-handoff(POST→pending→GET 폴링)의 모순을 **응답 형태**로 봉합한다.

| 구분 | 본 설계 (동기) | design-handoff 폴링 호환 |
|---|---|---|
| `POST /v1/analyses` 응답 | **완성된 분석 리소스** (`analysisId` + `status: success\|failed` + `risk_score` + `tier` + `recommendations`) | "POST가 곧 첫 폴링 응답" |
| `GET /v1/analyses/:id` | 같은 리소스 그대로 재조회 | 동기에서 폴링은 0~1회만 돌아도 동일 결과 |
| `pending` 행 | **영속하지 않음** (트랜잭션 내에서 `success\|failed`로 commit) | — |

→ 모바일 코드 변경 없이 수렴. (cross-link: `docs/06-design-handoff/2026-06-09-mobile-app-mvp.md`)

---

## 3. 추론 오케스트레이션 (Hybrid C)

### 3.1 폴백 방향 — 단일 진실 (must)

> **primary = 자체 YOLO v0.1.0 → 실패/저신뢰 시 OpenAI Vision 폴백.**
> `apps/api/CLAUDE.md` line 428·238의 "OpenAI 1차 → YOLO 폴백" 표기는 **본 설계로 정정**한다. 매 분석을 OpenAI로 먼저 호출하면 비용 폭증 + YOLO P95 263ms 이점 상실이므로 절대 역전 금지.

### 3.2 api `ai-client.ts`

| 항목 | 값 |
|---|---|
| timeout | 30s (ai 내부 폴백 SLA보다 길게 — §3.5) |
| **재시도** | **추론 호출(`/analyze`)은 자동 재시도 없음** (must). 지수 백오프 2회는 presign/confirm 같은 **멱등 GET/HEAD에만** |
| 헤더 | `x-request-id` 전파 |
| 이미지 전달 | presigned **GET URL** (바이너리 프록시 X) |

> 외곽 axios 재시도가 ai를 두 번 호출하면 추론 2회 실행 + 폴백 OpenAI 과금 중복. ai 내부 `tenacity`(OpenAI 호출 한정)는 유지하되, api → ai 추론 호출은 1회만.

### 3.3 ai `/analyze` (engine=auto) 파이프라인

```
preprocess ─▶ YOLO(ONNX, CPU) ─▶ risk.py(infestation_rate) ─▶ 폴백 판정 ─┬─(정상)─▶ 통합 응답
  EXIF strip      검출: bbox            risk_score / tier        (§3.4)    │
  RGBA→RGB        bee 인스턴스          recommendations(enum)              └─(폴백)─▶ OpenAI Vision
  HEIC→JPEG                             + low_confidence flag                       (structured output)
  1024px·q85                                                                        ─▶ 통합 응답
  10MB 가드
```

### 3.4 폴백 트리거 — risk.yaml 단일 소스 (should)

폴백 판정은 `risk.yaml`을 단일 소스로 삼는다. 검출별 conf를 이미지 1개 스칼라로 평균낸 "confidence < 0.5"는 **폐기**(검출 태스크에서 정의 불명확, risk.yaml에 해당 스칼라 없음).

| # | 폴백 트리거 | 근거 |
|---|---|---|
| 1 | 전체 벌 인스턴스 < `min_bee_count`(=5) | risk.yaml `infestation_rate.min_bee_count` |
| 2 | infestation_rate가 tier 경계(3% / 10%) ±밴드 | risk.yaml `thresholds` |
| 3 | YOLO 에러 / 타임아웃 | 추론 실패 |

> `low_confidence`(벌 < 5)는 폴백 게이트와 **별도 bool 플래그**. **무료 티어는 폴백 자체가 없으므로**(D6 확정) low_confidence·경계 케이스도 YOLO 결과 + `recommendations.low_confidence` enum을 그대로 반환. **폴백(OpenAI)은 유료 티어 전용** → 비용·DoS 노출을 원천 차단.

### 3.5 OpenAI 폴백 risk_score 의미축 정합 (should)

YOLO risk(infestation_rate 기반)와 OpenAI risk가 같은 컬럼·게이지·추세선에 섞이면 엔진 전환 시 위험도가 점프해 양봉가를 오도한다(AIHUB_71667.md: "측정 정의 다름").

- OpenAI 폴백 프롬프트를 "VMIR 추정"이 아니라 **"infestation_rate(감염 의심 벌 비율) 추정"**으로 재정렬.
- LLM은 risk_score를 자유 생성하지 않고 **infestation_rate만 추정** → YOLO와 **동일한 `risk.yaml` score_mapping 함수**로 risk_score 산출.
- tier 경계·score_mapping은 risk.py(YOLO)와 OpenAI 정규화 양쪽이 risk.yaml을 **단일 소스로 참조**.

### 3.6 폴백 SLA / 타임아웃 예산 (should)

5초 룰은 **정상(YOLO) 경로에서만 보장**, 폴백은 best-effort임을 UX 계약으로 명시.

| 계층 | 타임아웃 |
|---|---|
| YOLO 정상 경로 | P95 263ms (5초 룰 여유) |
| OpenAI 폴백 (동기 전용) | 짧게 **8~10s**, tenacity 1~2회 |
| api ai-client | 30s (폴백보다 길게 — "누가 먼저 끊기나" 명확화) |

→ OpenAI 예산 초과(503) / 타임아웃은 모두 **graceful null(status=failed)** 단일 경로로 흡수.

### 3.7 양쪽 실패 처리 (must)

```
YOLO 실패 ─▶ OpenAI 폴백 실패 ─▶ ai graceful (risk=null, tier=watch,
                                  recommendations=["AI 분석 실패…"])
            ─▶ api: status='failed' 저장 + HTTP 200 envelope (UX 비차단)
```

### 3.8 SSRF / presigned GET 보안 (should)

ai는 S3 자격증명 + OpenAI 키를 보유한 고가치 타깃 → 임의 URL fetch는 SSRF(메타데이터/RDS/Redis 접근) 위험.

- 분석용 presigned GET: objectKey 단일 스코프 + TTL = **최악 추론시간 + 여유(90~120s)**.
- ai `/analyze`는 임의 `image_url` fetch 금지 → objectKey만 받아 고정 버킷(helpbee-images) GetObject. presigned URL 사용 시 **host allowlist(우리 S3 도메인)**로 SSRF 차단.
- `raw_response` 저장 전 storage URL **쿼리스트링(서명) strip**, pino **redact 목록에 ai 호출 URL 추가**.

---

## 4. 저장 모델

### 4.1 ai_models 시드 (should — v11s 통일)

| provider | name | version | model_version 조립 |
|---|---|---|---|
| `yolo` | `helpbee-yolov11s` | `0.1.0` | `helpbee-yolov11s-0.1.0` |
| `openai` | `gpt-4o-mini` | `2024-07-18` | `gpt-4o-mini-2024-07-18` |

- ADR-0001 기준 **`yolov11s`로 단일 정정** (packages/database/CLAUDE.md §3.7, apps/ai 주석의 `yolov8s` 잔재 폐기).
- `engine_used → model_id` 매핑은 정확 문자열 일치 대신 **`provider` + `version` 활성행 1개 조회**로 느슨하게 (매핑 실패 시 restrict FK로 저장 자체가 깨지는 것 방지). `is_active`로 canary 운영.

### 4.2 analyses

- `UNIQUE(image_id, model_id)` **유지**. 동기·단일 엔진이라 image당 보통 **1행**, dual(어드민)만 2행.
- 저장 규칙: **정상 = YOLO 1행 / 폴백 = OpenAI 1행** (확정 결정 ⑤).

### 4.3 AnalysisResponse → analyses 컬럼 매핑 (must)

AnalysisResponse는 tier/confidence/cost를 반환하지만 analyses에 대응 컬럼이 없거나(tier/confidence/cost) 어휘가 충돌(overall_health ≠ tier)한다. 매핑을 명시 확정한다.

| AnalysisResponse 필드 | analyses 컬럼 | 처리 |
|---|---|---|
| `risk_score` (0~100) | `varroa_infection_risk` smallint | 그대로 저장 |
| `tier` | **(컬럼 없음)** | **신규 컬럼 X**. `risk_score`에서 risk.yaml 임계(3%/10%)로 백엔드가 **결정론적 재계산** → envelope에서만 노출 (무마이그레이션) |
| `tier` → `overall_health` | `overall_health` | 1:1 매핑 저장 (`safe→healthy`, `watch→warning`, `danger→critical`) **또는** MVP 미사용 nullable |
| `estimated_count` | `estimated_varroa_count` integer | 그대로 (없으면 null) |
| `confidence` / `cost_estimate_usd` | **(컬럼 없음)** | `raw_response.meta`에 저장. 조회 API는 raw_response를 클라에 노출 X → 필요 시 envelope 가공 필드로 승격 |
| `latency_ms` | `latency_ms` | 그대로 |
| `model_version` | `model_id` (FK) | §4.1 매핑 |
| status | `status` | `success` \| `failed` (pending 미영속) |

> **tier 어휘 단일 확정** (must): risk.yaml 기준 **3분법 `safe / watch / danger`**. 마스터플랜의 4분법(`caution/warning/critical`) 표기는 **폐기**.

### 4.4 recommendations

- tier별 한국어 **enum 매핑** (`risk.yaml` recommendations) → `analysis_id` 종속 **N행**.
- severity: `info | warn | danger` (CHECK 제약), `order`로 표시 순서 제어.

### 4.5 신규 쓰기 헬퍼 — createSingleAnalysis (must)

현 유일 헬퍼 `createDualAnalysis`는 **두 엔진 입력을 강제**하고 **recommendations를 insert하지 않는다**(코드 확인). store-one-engine 동기 경로에 부적합 → 신규 헬퍼 추가.

```ts
// packages/database/src/queries/analyses.ts (신규)
createSingleAnalysis(db, {
  hiveId, imageId, modelId,
  analysis: Omit<NewAnalysis, 'hiveId'|'imageId'|'modelId'>,
  recommendations: { order, content, severity }[],
})
// 한 트랜잭션에서:
//   1) analyses upsert  — onConflictDoUpdate target [imageId, modelId]
//   2) 해당 analysisId의 기존 recommendations delete 후 재삽입 (멱등)
// queries/index.ts 에 export
```

- `createDualAnalysis`는 **어드민 `/analyze/dual` 전용으로 보존**.
- 모든 영속은 `@helpbee/database` queries 경유 (직접 SQL 0).

### 4.6 신규 조회 헬퍼 (IDOR 차단 — should)

- 현 `listAnalysesByHive(db, hiveId)`는 **userId 필터가 없다** → 핸들러가 검증 한 줄만 누락해도 IDOR(타 양봉가 진단/GPS 노출).
- `listAnalysesByHive`에 **userId + hives soft-delete 조인** 추가 (getHiveTrend가 이미 쓰는 INNER JOIN 패턴 재사용).
- image용 소유권 쿼리 헬퍼(`getImageByIdForUser` 패턴) 추가 → §2-④① 검증을 쿼리 레벨에서 강제.

---

## 5. 열어둔 결정 · 권장 기본값

| ID | 결정 | 권장 기본값 |
|---|---|---|
| **D1** | 이미지 스토리지 | **AWS S3** (helpbee-images) |
| **D2** | 이미지 → ai 전달 | **presigned GET URL** (objectKey 스코프, TTL 90~120s, host allowlist — §3.8) |
| **D3** | EXIF / GPS | **제거** (orientation 적용 후 strip), `captured_at`은 strip 전 추출 |
| **D4** | 무료 쿼터 | **KST 월경계** key·TTL(다음 KST 월초까지) · **reserve-then-refund**(추론 전 원자 INCR 예약 → >4 차단, 성공 확정, 실패 DECR 환불, 멱등 short-circuit 무차감) · **이메일 검증 후에만 활성**(미검증=0) · Redis 장애 fail-closed · 월경계 테스트 |
| **D5** | JWT | jwt-simple **HS256** (access 15m / refresh 7d 회전 + 재사용 감지). **refresh `token_hash`는 argon2 X → 결정적 키드 해시(HMAC-SHA256 with server pepper, 또는 SHA-256)** — 토큰은 128bit+ 고엔트로피 난수라 솔트 불필요. argon2는 토큰별 무작위 salt로 raw→row 조회 불가 → `token_hash` UNIQUE·재사용 감지가 깨짐 (must) |
| **D6** | 폴백 정책 | **무료 = YOLO 단독(폴백 X) / 유료 = YOLO→OpenAI 폴백** *(확정)*. 임계는 risk.yaml 단일 소스(벌 < 5 / 경계 ±밴드 / 에러 — §3.4). 유료 폴백 **사용자별 일 5회 cap**(초과 시 YOLO 결과 graceful) + OpenAI 월예산 가드(유료 풀, `AI_BUDGET_EXCEEDED`→YOLO 강등) 이중화. 분석 전 `email_verified_at` 강제 → 비용·DoS 원천 차단 |
| **D7** | 구독 / 결제 | **stub만** (PG 없음) |
| **D8** | 양쪽 실패 | **graceful 200 + status=failed** (§3.7) |
| **D9** | infestation_rate 임계 | safe < 3% / watch 3~10% / danger ≥ 10% (**placeholder** — VMIR 차용, 베타 실측 회귀 보정 필요) |
| **D10** | api↔ai 내부 인증 | **방어심층** *(확정)*: ① 사설 서브넷 격리 + SG(api SG에서만 ai 인그레스 허용, ai 공개 X) ② 앱계층 **짧은 수명 HMAC 서명 내부 bearer**(exp ~5m · `aud=ai` · `request_id` 바인딩 · 시크릿 Secrets Manager·회전). 현업 실무 표준. **규모·컴플라이언스 확대 시 mTLS(워크로드 아이덴티티, App Mesh/ALB mTLS)로 승급** |
| **D11** | 재분석 정책 | **재촬영(새 image_id) 필요** *(확정)* — 한 이미지는 모델당 분석 1회. 같은 image_id 재요청은 멱등 안전망으로 기존 결과 반환(재과금 0), 별도 '같은 사진 재분석' 엔드포인트 없음 |

### ⚠️ 출시 차단 리스크 (should — 격상)

- **baseline S3 ROOT 키 회전**: 2026-06-08 baseline에서 S3 업로드에 실제 사용된 **AWS ROOT 키를 즉시 회전**하고, 이후 모든 S3 접근을 IAM task role(infra §8/§19)로 전환. baseline 문서가 스스로 "보안 최우선"으로 분류 → **후속작업이 아니라 출시 차단 항목**으로 명시.

### 추후 (nice — MVP 범위 밖, 메모)

- **infestation_rate 원시 지표 보존**: `raw_response.meta`에 `infestation_rate`, `bee_total_count`, `bee_with_varroa_count`를 구조화 저장(스키마 변경 불필요). risk_score는 score_mapping이 비선형 saturating이라 역산 불가 → 베타 실측 VMIR **회귀 보정에 원시 지표 필수**. 신규 컬럼 추가는 보류(YAGNI).
- **fallback_from 스키마 고정·범위 한정**: `raw_response.fallback_from`은 비교 데이터가 아니라 **폴백 트리거 운영 메타**로 한정 — `{reason, yolo_confidence, yolo_bee_count, yolo_model_version}` 고정 키만. YOLO bbox 전체/좌표 dump 금지 (결정 ⑤ 정합, jsonb 비대·PII 방지).

---

# 2부 — 전체 도메인 & 보안

## 6. 공통 계약 (envelope · RFC7807 · error-codes)

> 1부 §4(응답 봉투·에러·검증)에서 확정한 원칙을 2부 모든 도메인이 공유한다. 본 절은 **계약의 단일 진실 소스**이며, §8~§12는 이 계약을 *참조만* 한다(재설계 금지). 사실 근거: `apps/api/CLAUDE.md` §4.1~§4.3, `lib/envelope.ts`/`lib/problem.ts`/`lib/error-codes.ts` 설계.

### 6.1 성공 봉투 — `lib/envelope.ts`

모든 2xx 응답은 예외 없이 `{ data, meta }`. 라우트에서 raw `c.json(payload)` 금지, `ok()`/`created()` 헬퍼만 사용.

```ts
type Meta = {
  requestId: string;   // x-request-id (§7.1에서 주입, ok()가 c.get('requestId')로 자동 채움)
  timestamp: string;   // ISO 8601 (UTC)
  pagination?: { limit: number; offset: number; total: number };
};
function ok<T>(c, data: T, extra?: Partial<Meta>): Response;        // 200
function created<T>(c, data: T, extra?: Partial<Meta>): Response;   // 201
```

- `requestId`/`timestamp`는 라우트가 직접 넣지 않는다(헬퍼가 컨텍스트에서 채움).
- 리스트 응답은 `extra.pagination`에 `{limit, offset, total}`을 넣고 공통 페이지네이션 스키마(§6.4)와 1:1.
- **동기 처리(1부 확정)**: `POST /v1/analyses`는 `created()`로 **완성된 분석 리소스 1건**을 즉시 반환한다(pending 미영속, 폴링 엔드포인트 없음).

### 6.2 에러 — RFC 7807 `application/problem+json` · `lib/problem.ts`

`Content-Type: application/problem+json` 고정. 본문 필수 필드:

```ts
type Problem = {
  type: string;     // "https://helpbee.io/errors/{kebab-code}" (URI reference)
  title: string;    // 영문 고정 요약
  status: number;   // HTTP status
  code: ErrorCode;  // lib/error-codes.ts enum (기계 판독 단일 진실)
  detail: string;   // 상황 설명 (PII/secret/입력값 echo 금지)
  instance: string; // 요청 경로 (c.req.path)
  requestId: string;
};
function problem(c, code: ErrorCode, detail?: string): Response;
```

- `problem(c, code)` 한 줄로 status/title/type을 enum 매핑 테이블에서 자동 도출 → 라우트는 코드만 고른다.
- 전역 onError(§7.8)가 throw된 `AppError`/`ZodError`/미처리 예외를 모두 이 형태로 정규화.
- **detail에 사용자 입력을 반사하지 않는다.** 검증 실패는 필드 경로만 노출(§6.4). DB 드라이버 에러는 도메인 코드로 변환 후 응답(constraint명·테이블명 클라 전달 금지 — §13 SHOULD).

### 6.3 에러 코드 enum — `lib/error-codes.ts`

신규 에러는 **반드시 이 enum에 먼저 등록**한 뒤 사용(자유 문자열 금지). 코드 ↔ status ↔ title ↔ type을 한 테이블에서 관리.

| code | status | title | 발생 지점 |
|---|---|---|---|
| `VALIDATION_FAILED` | 400 | Validation failed | zValidator 실패 (§6.4, §7.7) |
| `AUTH_INVALID_CREDENTIALS` | 401 | Invalid credentials | 로그인 실패(존재/불일치 통합), 토큰 무효, webhook 서명 불일치 |
| `AUTH_TOKEN_EXPIRED` | 401 | Token expired | access 만료(15m) |
| `AUTH_UNAUTHORIZED` | 401 | Unauthorized | access 누락/위조 (`requireAuth`) |
| `REFRESH_REUSE_DETECTED` | 401 | Refresh token reuse detected | revoked refresh 재사용 → 전체 폐기 |
| `AUTH_REFRESH_INVALID` | 401 | Refresh invalid | refresh 미존재/만료/위조 |
| `AUTH_EMAIL_TAKEN` | 409 | Email already registered | signup 이메일 중복 |
| `AUTH_ACCOUNT_LOCKED` | 429 | Account locked | 로그인 실패 누적 잠금 (+Retry-After) |
| `AUTH_USER_NOT_FOUND` | 404 | User not found | `/me` 대상 user 삭제됨 |
| `AUTH_EMAIL_NOT_VERIFIED` | 403 | Email not verified | 분석 게이트 미통과(§8.8) |
| `FORBIDDEN` | 403 | Forbidden | 비소유 명시 거부 (일반 컨텍스트) |
| `FORBIDDEN_ROLE` | 403 | Forbidden | role 불충분 (`requireRole`) |
| `ADMIN_SELF_DEMOTE_FORBIDDEN` | 409 | Cannot remove last admin | 마지막 admin 강등 차단 |
| `NOT_FOUND` | 404 | Resource not found | 리소스 없음 / **IDOR 시 동일 코드** |
| `UNSUPPORTED_MEDIA` | 415 | Unsupported media type | jpeg/png/webp 외 |
| `IMAGE_TOO_LARGE` | 413 | Image too large | 10MB 또는 픽셀 상한 초과 |
| `IMAGE_INVALID` | 422 | Invalid image | 매직넘버/디코드 실패, 키 패턴 불일치 |
| `IMAGE_NOT_FOUND_IN_STORAGE` | 404 | Image not found in storage | confirm 시 S3 객체 부재 |
| `RATE_LIMITED` | 429 | Too many requests | sliding window 초과 (+Retry-After) |
| `QUOTA_EXCEEDED` | 402 | Quota exceeded | 무료 월 4회 소진 |
| `AI_UNAVAILABLE` | 503 | AI engine unavailable | YOLO 실패 + 폴백 불가/실패 |
| `AI_BUDGET_EXCEEDED` | 503 | AI budget exceeded | OpenAI 폴백 예산 초과 → YOLO-only 강등 신호 |
| `WEBHOOK_SIGNATURE_INVALID` | 401 | Webhook signature invalid | HMAC 불일치/타임스탬프 윈도 위반 |
| `WEBHOOK_DISABLED` | 503 | Webhook disabled | MVP inert 또는 시크릿 미구성 |
| `INTERNAL` | 500 | Internal server error | 미분류 예외 (detail 마스킹) |

> 보안 규약(§13 정합): **인가 실패(비소유 리소스)는 `NOT_FOUND`(404)** 로 반환해 존재 여부 누설을 막는다. 단 명시적 role 부족(일반 user의 `/admin/*`)은 `FORBIDDEN_ROLE`(403). 401(미인증) vs 403(인증됐으나 권한 없음)은 `apps/api/CLAUDE.md §4.4`와 정합.

### 6.4 공통 입력 스키마 — `schemas/common.ts`

- `paginationSchema`: `{ limit: number(1~100, default 50), offset: number(≥0, default 0) }`. 모든 list에 적용.
- `idParamSchema`: `{ id: string().uuid() }` — 모든 `:id` path param(비-uuid는 400).
- 모든 mutation 스키마는 **`.strict()`** (모르는 키는 silent strip이 아니라 400 거부 — Mass Assignment 차단, §13 MUST).
- 검증 실패 응답: `VALIDATION_FAILED` + `detail`에 zod issue를 `{path}` 배열로 평탄화(값·정규식 미포함, message는 고정 카탈로그 매핑).

### 6.5 엔드포인트 공통 계약 표 (횡단 요약)

| 메서드/경로 | 인증 | 요청 zod (schemas/) | 성공 응답 | 주요 에러 코드 |
|---|---|---|---|---|
| POST `/v1/auth/signup` | 🔓 | `auth.signupSchema` | 201 `{user, tokens}` | VALIDATION_FAILED, AUTH_EMAIL_TAKEN |
| POST `/v1/auth/login` | 🔓 | `auth.loginSchema` | 200 `{user, tokens}` | AUTH_INVALID_CREDENTIALS, AUTH_ACCOUNT_LOCKED, RATE_LIMITED |
| POST `/v1/auth/refresh` | 🔓* | `auth.refreshSchema`(body) | 200 `{tokens}` | AUTH_REFRESH_INVALID, REFRESH_REUSE_DETECTED |
| POST `/v1/auth/logout` | 🔐 | `auth.logoutSchema`(body) | 200 `{revoked:true}` | AUTH_UNAUTHORIZED |
| GET `/v1/auth/me` | 🔐 | — | 200 `{user, subscription}` | AUTH_UNAUTHORIZED, AUTH_USER_NOT_FOUND |
| GET `/v1/hives` | 🔐 | `paginationSchema`(query) | 200 `[hive]`+pagination | RATE_LIMITED |
| POST `/v1/hives` | 🔐 | `hives.createHiveSchema` | 201 `{hive}` | VALIDATION_FAILED |
| GET/PATCH/DELETE `/v1/hives/:id` | 🔐 | `idParamSchema`(+patch) | 200 `{hive}` | NOT_FOUND(IDOR), VALIDATION_FAILED |
| POST `/v1/analyses` | 🔐 | `analyses.createSchema` | **201 완성 리소스(동기)** | QUOTA_EXCEEDED, AI_UNAVAILABLE, NOT_FOUND |
| GET `/v1/analyses` | 🔐 | `analyses.listSchema`(query) | 200 `[analysis]`+pagination | NOT_FOUND(hive 비소유) |
| GET `/v1/analyses/:id` | 🔐 | `idParamSchema` | 200 `{analysis}` | NOT_FOUND |
| POST `/v1/images/presign` | 🔐 | `images.presignSchema` | 200 `{uploadUrl, objectKey, expiresIn}` | UNSUPPORTED_MEDIA |
| POST `/v1/images/confirm` | 🔐 | `images.confirmSchema` | 201 `{image}` | UNSUPPORTED_MEDIA, IMAGE_TOO_LARGE, NOT_FOUND |
| GET `/v1/admin/*` | 👑 | 각 도메인 | 200 | FORBIDDEN_ROLE |
| POST `/v1/subscriptions/webhook` | 🔓** | `subscriptions.webhookSchema` | 200 `{received:true}` | WEBHOOK_SIGNATURE_INVALID, WEBHOOK_DISABLED |

\* refresh는 헤더가 아닌 body. \*\* HMAC 서명 검증 미들웨어로 보호(§7.6).

---

## 7. 미들웨어 체인

`src/app.ts`에서 아래 **고정 순서**로 마운트한다. 순서가 보안·관측성의 전제이므로 임의 변경 금지. 현 `src/index.ts`는 health만 있는 부트스트랩이므로 앱 구성을 `app.ts`로 분리하고 `index.ts`는 listen만 담당한다(기존 health 엔드포인트 보존).

```
요청 →
 1. request-id        (x-request-id 생성/전파, c.set('requestId'))
 2. logger            (pino, 요청/응답 1줄 + redact)
 3. CORS              (allowlist 정확 매칭, * 금지)
 4. security-headers  (HSTS / nosniff / X-Frame-Options / Referrer-Policy / CSP)
 5. rate-limit        (Redis sliding window, 전역 → 라우트별 강화)
 6. error boundary    (app.onError로 RFC7807 정규화 — 아래 모든 단계 throw 포착)
 7. zValidator        (라우트별, schemas/* — 400 VALIDATION_FAILED)
 8. requireAuth       (보호 라우트, Bearer access 검증 → c.set('userId','role'))
 9. requireRole       ('admin' 등, requireAuth 이후)
→ 라우트 핸들러
```

### 7.1 request-id (`middleware/request-id.ts`)
- 인입 `x-request-id` 형식 검증(uuid/짧은 토큰) 후 채택, 없으면 생성. `c.set('requestId', id)` + 응답 헤더 echo.
- AI 호출 시 동일 id 전파(1부 Hybrid C: api→ai HMAC 내부 bearer의 `request_id` 바인딩과 같은 id) → 분산 추적 일관성.

### 7.2 logger (`middleware/logger.ts`)
- pino 인스턴스 1개. 요청 시작/완료 각 1줄(JSON): `requestId, userId(있으면), method, route, status, latencyMs`.
- **redact 단일 목록**(§14.1과 동일 소스): `authorization`/`cookie`/`set-cookie` 헤더, `*.password`/`*.passwordHash`/`*.token`/`*.refreshToken`/`*.tokenHash`, presigned URL 서명 쿼리스트링(`*.uploadUrl`), `*.latitude`/`*.longitude`/`*.address`/`*.capturedAt`, `*.rawResponse`/`*.raw_payload`, 내부 bearer. `req.body` 통째 로깅 금지(필드 allowlist).
- prod JSON, 로컬 pino-pretty(`NODE_ENV` 분기).

### 7.3 CORS
- `config/env.ts`의 `CORS_ALLOWLIST`(콤마 구분) 기반 **정확 매칭**. 와일드카드 `*` 금지(`apps/api/CLAUDE.md §13.4`, `infra/CLAUDE.md §14`).
- 요청 origin이 allowlist에 매칭될 때만 그 origin을 `Access-Control-Allow-Origin`에 반환. **origin 무조건 echo 금지**. admin은 httpOnly 쿠키 기반이라 `Access-Control-Allow-Credentials: true`는 매칭 시에만(§13 SHOULD).

### 7.4 security-headers
- `Strict-Transport-Security`(prod, max-age ≥ 6개월, includeSubDomains), `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `X-Powered-By` 제거.
- **Content-Security-Policy** 추가(`default-src 'self'`, `img-src 'self' cdn.helpbee.kr`, `frame-ancestors 'none'`), admin은 더 엄격. `Permissions-Policy`로 geolocation 차단(§13 SHOULD). WAF(CloudFront 앞단)와 이중 방어 — 앱 계층 헤더도 끄지 않는다.

### 7.5 rate-limit (`middleware/rate-limit.ts`)
Redis sliding window. 전역 적용 후 특정 라우트에서 더 엄격한 한도로 덮어쓴다.

| 적용 대상 | 한도 | 키 |
|---|---|---|
| 익명 IP(전역) | 60 req/min | `rl:ip:{ip}:{minute}` |
| 인증 사용자(전역) | 300 req/min | `rl:user:{userId}:{minute}` |
| `POST /v1/auth/login` / `refresh` | 10 req/min/IP | `rl:auth:{ip}:{minute}` |
| `POST /v1/auth/signup` | **5 req/min/IP + 일일 상한** | `rl:signup:{ip}:{minute}` |
| `POST /v1/images/presign` | 30 req/min/user | `rl:presign:{userId}:{minute}` |
| `POST /v1/analyses` | 10 req/min/user | `rl:analyses:{userId}:{minute}` |

- 초과 시 `RATE_LIMITED`(429) + `Retry-After`.
- **클라 IP는 신뢰 프록시 홉 인지 파서로 추출**(CloudFront+ALB 홉 수 기준 XFF의 N번째 또는 CloudFront 주입 헤더). 위조 XFF가 limiter를 리셋하지 못하게 한다(§13 SHOULD).
- **quota/rate-limit는 캐시와 달리 Redis 장애 시 fail-closed**(가용성보다 남용 차단 우선).
- 무료 월 quota(1부 확정)는 rate-limit과 **별개 계층** — 차감 로직은 §8.x/§11.3과 1부 참조. rate-limit 미들웨어가 quota를 차감하지 않는다(역할 분리).

### 7.6 webhook 서명 검증
- `POST /v1/subscriptions/webhook`은 인증 미들웨어 대신 **HMAC 서명 검증 미들웨어**(라우트 최상단, zValidator보다 먼저)로 보호. **raw body**(파싱 전 bytes)로 서명 계산, `timingSafeEqual` 상수 시간 비교. 상세 §11.4.

### 7.7 zValidator (라우트별)
- `@hono/zod-validator`로 `json`/`query`/`param` 검증. 스키마는 항상 `schemas/`에(인라인 금지). 실패 시 전역 onError가 `VALIDATION_FAILED`로 정규화(§6.4).

### 7.8 error boundary (`app.onError`)
- 모든 throw를 RFC7807로 변환. `AppError`(코드 보유)는 그대로, `ZodError`→`VALIDATION_FAILED`, 그 외→`INTERNAL`(detail 마스킹, 원본은 로그·Sentry로만). 404 미매칭은 `app.notFound`로 `NOT_FOUND`. **pg 드라이버 에러는 도메인 코드로 변환**(예: unique 위반 → `AUTH_EMAIL_TAKEN`), constraint/컬럼명 미노출(§13 SHOULD).

### 7.9 auth / role (`middleware/auth.ts`)
- `requireAuth()`: `Authorization: Bearer` access(HS256, 15m) 검증 → `c.set('userId', sub)`, `c.set('role', role)`. 만료 `AUTH_TOKEN_EXPIRED`, 위조/누락 `AUTH_UNAUTHORIZED`.
  - **JWT 검증은 algorithm 핀 강제**(HS256만, alg=none/RS256/헤더 alg 불일치 거부 — §13 MUST). `jwt-simple` 사용 시 `decode`에 4번째 algorithm 인자 필수, 가능하면 `jose`로 교체.
  - **즉시 회수 마커**: `requireAuth`는 Redis `sessions_valid_after:{userId}` 마커를 읽어 access `iat < marker`면 거부(차단/탈퇴/비번변경/refresh-reuse 시 마커 bump). full blacklist 아님, O(1)(§13 MUST).
- `requireRole('admin')`: requireAuth 이후 `c.get('role')` 확인, 불충분 시 `FORBIDDEN_ROLE`(403). `app.use('/v1/admin/*', requireAuth(), requireRole('admin'))` 단일 마운트, 이 prefix 밖 admin 핸들러 금지(§12.1).
- 도메인 소유권은 미들웨어가 아니라 **쿼리 계층 IDOR 방어**(§9.3, §13)에 위임 — 라우트는 빈 결과를 `NOT_FOUND`로 변환.

---

## 8. Auth 도메인 (`apps/api/src/routes/auth.ts`)

> 범위: signup/login/refresh/logout/me. 1부에서 확정된 토큰/저장/멱등/IDOR 핵심은 재설계하지 않고 참조만 한다. 근거: `apps/api/CLAUDE.md` §4.4~§4.6·§5, `packages/database/src/schema/{users,refreshTokens,auditLog,subscriptions}.ts` 실제 컬럼, 1부 확정.

### 8.0 전제 (1부 참조 — 재설계 금지)
- 응답 봉투/에러/검증: §6 그대로. 모든 auth 액션은 `audit_log` insert(§8.6).
- 토큰: JWT **HS256**, access **15분(클라 메모리)** / refresh **7일**, 회전 + 재사용 감지(§8.4).
- refresh `token_hash` = **HMAC-SHA256(server pepper)** (결정적 → raw→row 조회·재사용 감지 가능). 비밀번호 = **argon2id**. 두 해싱은 별도 서비스로 분리해 스왑 불가하게(§13 MUST).
  - ⚠️ `refreshTokens.ts:8` 주석 "argon2 해시"는 확정과 **불일치** → 구현 PR에서 "HMAC-SHA256(server pepper), 결정적"으로 정정(§13 MUST, §17).

### 8.1 엔드포인트 계약 표

| Method | Path | 인증 | 요청 (zod) | 성공 응답 (`data`) / 상태 | 에러 코드 (status) |
|---|---|---|---|---|---|
| POST | `/v1/auth/signup` | 🔓 | `signupSchema`: `{ email, password, name }` | `{ user: PublicUser, accessToken, refreshToken, expiresIn:900 }` / **201** | `AUTH_EMAIL_TAKEN`(409), `VALIDATION_FAILED`(400), `RATE_LIMITED`(429) |
| POST | `/v1/auth/login` | 🔓 | `loginSchema`: `{ email, password }` | `{ user: PublicUser, accessToken, refreshToken, expiresIn:900 }` / **200** | `AUTH_INVALID_CREDENTIALS`(401), `AUTH_ACCOUNT_LOCKED`(429), `VALIDATION_FAILED`(400) |
| POST | `/v1/auth/refresh` | 🔓* | `refreshSchema`: `{ refreshToken }` | `{ accessToken, refreshToken, expiresIn:900 }` / **200** | `AUTH_REFRESH_INVALID`(401), `REFRESH_REUSE_DETECTED`(401), `VALIDATION_FAILED`(400) |
| POST | `/v1/auth/logout` | 🔐 | `logoutSchema`: `{ refreshToken }` | `{ revoked: true }` / **200** | `AUTH_UNAUTHORIZED`(401) |
| GET | `/v1/auth/me` | 🔐 | — | `PublicUser` + `{ subscription:{plan,status} }` / **200** | `AUTH_UNAUTHORIZED`(401), `AUTH_USER_NOT_FOUND`(404) |

\* `/refresh`는 access 만료 상태에서 호출되므로 `requireAuth` 미적용. refresh 토큰 자체가 인증 수단이며 **헤더가 아닌 body**로 전달.

### 8.2 zod 스키마 (`schemas/auth.ts`)

모두 `schemas/auth.ts`에 정의(인라인 금지), `.strict()`.

```ts
const emailField = z.string().trim().toLowerCase().email().max(254);
//  정규화(trim→NFKC→toLowerCase)는 단일 유틸 normalizeEmail()로 추출해 signup/login/실패카운터/조회가 동일 함수 경유(§13 SHOULD).
//  DB의 lower(email) UNIQUE 인덱스(0000_*.sql)와 정합.
const passwordField = z.string().min(10).max(128); // OWASP 최소 10, 상한 128(argon2 입력 폭주 방지)
const nameField = z.string().trim().min(1).max(60);

export const signupSchema  = z.object({ email: emailField, password: passwordField, name: nameField }).strict();
export const loginSchema   = z.object({ email: emailField, password: z.string().min(1).max(128) }).strict();
//  login의 password는 길이만(min(1)) — signup 정책 변경 시 기존 계정 잠김 방지.
export const refreshSchema = z.object({ refreshToken: z.string().min(1).max(512) }).strict();
export const logoutSchema  = z.object({ refreshToken: z.string().min(1).max(512) }).strict();
```

**`PublicUser` 출력 투영(필수)**: `password_hash` 절대 미포함. `users`에서 다음만 노출.

```ts
type PublicUser = {
  id: string; email: string; name: string;
  role: 'user' | 'admin';        // users.role (users_role_check)
  emailVerified: boolean;        // email_verified_at IS NOT NULL로 파생(타임스탬프 원본 미노출)
  createdAt: string;             // ISO
};
```

### 8.3 엔드포인트별 처리 흐름

#### POST /signup (201)
1. `signupSchema` 검증 → `normalizeEmail()`.
2. **rate-limit/계정보호 게이트 이후에만** argon2id 도달(메모리 DoS 방지, §13 MUST). 비밀번호 해시 → `users.password_hash`.
3. `users` insert(`role='user'`, `email_verified_at=NULL`). **이메일 충돌은 `lower(email)` UNIQUE 위반 catch를 단일 진실 소스**로 → `AUTH_EMAIL_TAKEN`(409). 사전 SELECT+INSERT는 TOCTOU.
4. `subscriptions` 기본 row(`plan='free'`, `status='active'`)를 같은 트랜잭션 insert(`user_id` UNIQUE).
5. access(15m)+refresh(7d) 발급 → refresh `token_hash`(HMAC) row insert(`user_id`, `token_hash`, `expires_at`, `user_agent`, `ip`).
6. `audit_log`: `action='auth.signup'`, `entity='user'`, `entity_id=user.id`.
7. 201 반환. **무료 quota는 이메일 검증 완료 전 0**으로 시작(계정 양산 인센티브 제거, §13 MUST·§8.8).

#### POST /login (200)
1. `loginSchema` 검증.
2. **계정 보호 게이트(§8.5.3)를 argon2 verify 이전에 선검사** — 잠금이면 `AUTH_ACCOUNT_LOCKED`(429) + `Retry-After`.
3. `normalizeEmail()`로 user 조회(`deleted_at IS NULL` + `blocked_at IS NULL` 필터).
4. argon2 verify. **user 미존재와 비밀번호 불일치는 동일 `AUTH_INVALID_CREDENTIALS`(401)** (enumeration 방지). user 미존재 시에도 더미 verify 1회로 타이밍 차이 최소화.
5. 실패: Redis 실패 카운터 INCR(복합 키 `auth:fail:{email}+{ip}`) + `audit_log action='auth.login_failed'`(사유 코드만, 입력값 미기록 — §14 집계/샘플링 고려).
6. 성공: 카운터 삭제 + 토큰 발급 + refresh row insert + `audit_log action='auth.login'`.

#### POST /refresh (200) — §8.4.
#### POST /logout (200) — §8.3.logout.
1. `requireAuth`로 `userId` 주입.
2. `refreshToken` → HMAC → `refresh_tokens` row 조회.
3. **row의 `user_id` ≠ caller면 no-op**(suspicious audit, 200 `{revoked:true}`). **절대 §8.4 재사용 감지(전체 revoke) 분기로 진입 금지** — token_hash가 글로벌 UNIQUE라 타인 토큰도 매칭될 수 있고, victim 세션 대량 revoke(cross-tenant denial)를 막는다(§13 SHOULD).
4. 본인 소유면 `revoked_at = now()` 마킹.
5. `audit_log action='auth.logout'`.

#### GET /me (200)
1. `requireAuth`로 `userId`.
2. `users` 조회(`deleted_at IS NULL`). 미존재 → `AUTH_USER_NOT_FOUND`(404).
3. `subscriptions` 요약(`plan`, `status`) 조인.
4. `PublicUser` + `{ subscription }`. **audit_log 미기록**(읽기 전용).

### 8.4 Refresh 회전 + 재사용 감지

`refresh_tokens`(`id, user_id, token_hash UNIQUE, expires_at, revoked_at, user_agent, ip, created_at`) 기준.

**정상 회전**:
1. body `refreshToken` → HMAC-SHA256(pepper) → `token_hash`.
2. `token_hash`로 row 조회. row 없음/`expires_at <= now()` → `AUTH_REFRESH_INVALID`(401).
3. `revoked_at IS NOT NULL` → 재사용 분기(아래) — 단 **grace window 예외 우선 판정**.
4. 유효: 단일 트랜잭션에서 **조건부 UPDATE**(`WHERE id=? AND revoked_at IS NULL`)로 기존 revoke(승자만 회전) + 새 refresh row insert(`user_agent`/`ip` 갱신) + 새 access 발급.
5. `audit_log action='auth.refresh'`.

**Grace window (동시성 오탐 방지, §13 MUST)**: 모바일 dio AuthInterceptor가 access 만료 시 다중 refresh를 동시 발사한다. 토큰이 **grace(예: 10초) 내 revoke됐고 교체가 같은 user/device**면 재사용 감지(전체 revoke)가 아니라 **현재 유효 토큰쌍을 반환**(benign 중복, 로그만). full reuse-detection은 grace 밖 토큰에만 적용. → 동시 2개 refresh에서 강제 로그아웃 0 검증(§15).

**재사용 감지 (grace 밖 revoked refresh)**:
1. 공격 신호 → 해당 user의 **모든 refresh 일괄 revoke**(`UPDATE ... SET revoked_at=now() WHERE user_id=? AND revoked_at IS NULL`) + `sessions_valid_after:{userId}` 마커 bump(access도 무효화).
2. `audit_log action='auth.refresh_reuse_detected'` (metadata: `{ tokenHashPrefix, revokedCount }` — 토큰 원문 미기록).
3. `REFRESH_REUSE_DETECTED`(401).

### 8.5 비밀번호 / 토큰 / 계정 보호

#### 8.5.1 비밀번호 (`services/password-service.ts`)
- **argon2id**, `memoryCost=19456, timeCost=2, parallelism=1` (OWASP 2024, 1부 확정). bcrypt/scrypt/PBKDF2 금지. `users.password_hash`(text)에 PHC string 저장.

#### 8.5.2 JWT (`services/jwt-service.ts`)
- HS256, `JWT_SECRET`(Secrets Manager, **min 64자**·플레이스홀더 부팅 거부, §13 MUST). access 15m / refresh 7d.
- access payload(최소): `{ sub, role, ev:emailVerified(boolean), iat, exp }`. PII(이메일/이름) 미포함.
- refresh는 **opaque 랜덤(32바이트 base64url)** 권장 — 검증의 단일 진실 소스는 DB row.
- **access 시크릿과 refresh pepper는 서로 다른 값**. admin 토큰은 다른 audience(`aud`)로 스코프해 blast radius 축소(§13 MUST).

#### 8.5.3 계정 보호 (Redis, argon2 이전 게이트)
- 복합 키 `auth:fail:{email}+{ip}` + 별도 per-IP login cap(이메일만 키로 쓰면 victim lockout-DoS, §13 MUST).
- 로그인 실패 INCR(TTL 15분 슬라이딩). 예: **email-IP 10회/15분 초과 → 15분 lockout** + per-IP 30/min. 임계값은 `config/env.ts`.
- **검사는 argon2 verify 이전**에 실행(throttle된 시도는 argon2 미도달 → CPU/메모리 DoS 차단). 성공 시 카운터 삭제. CAPTCHA/이메일 알림은 Phase 2.

### 8.6 감사 로그 — 실제 컬럼 매핑

`audit_log`(bigserial PK, `actor_id`, `action`, `entity`, `entity_id`, `metadata jsonb`, `ip`, `user_agent`, `created_at`) 기준. ⚠️ `apps/api/CLAUDE.md §9.2`의 `userId/actorId/target` 표기는 실제 스키마(`actor_id/entity/entity_id`)와 드리프트 → 구현은 실제 스키마, 문서는 후속 정정(§17).

| 액션 | `action` | `actor_id` | `entity`/`entity_id` | metadata |
|---|---|---|---|---|
| 회원가입 | `auth.signup` | 신규 user.id | `user`/user.id | `{}` |
| 로그인 성공 | `auth.login` | user.id | `user`/user.id | `{ via:'password' }` |
| 로그인 실패 | `auth.login_failed` | NULL | `user`/NULL* | `{ reason }` (입력값·비번 미기록, 집계/샘플링) |
| 계정 잠금 | `auth.account_locked` | NULL | `user`/NULL* | `{ window:'15m' }` |
| refresh 회전 | `auth.refresh` | user.id | `user`/user.id | `{}` |
| 재사용 감지 | `auth.refresh_reuse_detected` | user.id | `user`/user.id | `{ tokenHashPrefix, revokedCount }` |
| 로그아웃 | `auth.logout` | user.id | `user`/user.id | `{}` |

\* 실패/잠금은 user 존재 누출 방지 위해 `entity_id` NULL. `actor_id`는 인증 전이므로 NULL(`onDelete:'set null'`). metadata에 **불변 actor 참조**(actor uuid를 text로 복사)를 두어 FK nulling 후에도 귀속 유지(§13 SHOULD).

### 8.7 신규 에러 코드 — §6.3 enum에 일괄 등록(중복 정의 금지).

### 8.8 email_verified_at 게이트 (분석 권한 전제)
- login/`/me`는 미인증 계정도 허용(온보딩). 단 **`POST /v1/analyses` 진입 전 `email_verified_at IS NOT NULL` 검사** → 미인증이면 `AUTH_EMAIL_NOT_VERIFIED`(403). **무료 quota는 검증 완료 시점에 활성화**(§8.3, §13 MUST).
- 구현: `requireVerifiedEmail()` 미들웨어를 `requireAuth` 뒤 체이닝. **권위 소스는 JWT `ev`가 아니라 Redis(`email_verified:{userId}`, verify 시 set, 짧은 TTL) + DB fallback** — `ev`는 클라 UX 힌트로만(자가주장 boolean을 authorization 소스로 신뢰 금지, §13 SHOULD). 검증 완료 시 `sessions_valid_after` bump 또는 refresh 강제로 클레임 재동기.

### 8.9 DB 정합 / 인터페이스 메모
- `users.email`은 citext가 아니라 **text + `lower(email)` UNIQUE**(0000) → zod `toLowerCase()` 정규화가 충돌 검사의 필수 전제(라우트에서 반드시 정규화 후 사용).
- `users.role` CHECK `IN ('user','admin')` — signup은 항상 `'user'`. admin 승격은 `PATCH /v1/admin/users/:id` 전용.
- refresh 쿼리 헬퍼를 `packages/database/src/queries/`에 추가(직접 SQL 금지): `getRefreshTokenByHash`, `createRefreshToken`, `revokeRefreshToken(id)`, `revokeAllRefreshTokensForUser(userId)`. 기존 `queries/hives.ts`의 `(db, ...)` 첫 인자 스타일 준수.
- soft delete/blocked user: login/refresh/me 모두 `deleted_at IS NULL` + `blocked_at IS NULL` 필터. 이미 발급된 access(15m)는 **`sessions_valid_after` 마커**로 즉시 무효화(§7.9, §13 MUST).

### 8.10 MVP 적정선 / 비범위
- 이메일 인증 메일 발송·콜백, 비밀번호 재설정은 별도 섹션(§8은 게이트 소비/플래그만).
- 소셜 로그인·MFA·RS256 마이그레이션(`jwt-simple`→`jose`)은 Phase 2(단 alg 핀은 MVP 필수 — §13 MUST). refresh 세션 목록 UI·동시 세션 제한은 비범위.

---

## 9. Hives 도메인 (`routes/hives.ts`)

> 양봉가 벌통 CRUD. 모든 라우트 `requireAuth()` + 소유권 검증. DB 접근은 `queries.hives.*`만(직접 SQL 금지). 1부 인증/JWT/envelope/RFC7807은 참조만.

### 9.1 엔드포인트 계약 표

| 메서드/경로 | 인증 | 요청 (zod) | 응답 (data) | 주요 에러코드 |
|---|---|---|---|---|
| `GET /v1/hives` | 🔐 | query: `listHivesQuery` (paginationSchema 적용) | `Hive[]`(소유 + soft delete 제외, `updatedAt` desc) + pagination | `RATE_LIMITED` |
| `POST /v1/hives` | 🔐 | json: `createHiveSchema` | `Hive` | `VALIDATION_FAILED`(400) |
| `GET /v1/hives/:id` | 🔐 | path: `hiveIdParam` | `Hive` | `NOT_FOUND`(404) |
| `PATCH /v1/hives/:id` | 🔐 | path + json: `updateHiveSchema` | `Hive` | `NOT_FOUND`(404), `VALIDATION_FAILED`(400) |
| `DELETE /v1/hives/:id` | 🔐 | path: `hiveIdParam` | `{ id, deletedAt }` | `NOT_FOUND`(404) |

### 9.2 zod 스키마 (`schemas/hives.ts`)

`packages/database/src/schema/hives.ts` 컬럼에 1:1, `.strict()`:

```ts
const latitude  = z.number().min(-90).max(90);
const longitude = z.number().min(-180).max(180);

export const createHiveSchema = z.object({
  name: z.string().trim().min(1).max(100),       // hives.name NOT NULL
  note: z.string().trim().max(1000).optional(),
  latitude: latitude.optional(),
  longitude: longitude.optional(),
  address: z.string().trim().max(255).optional(),
  installedAt: z.coerce.date().optional(),       // timestamptz
}).strict().refine(
  (v) => (v.latitude == null) === (v.longitude == null),  // 반쪽 좌표 금지
  { message: 'latitude/longitude must be provided together', path: ['latitude'] },
);

export const updateHiveSchema = createHiveSchema.partial().strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'at least one field required' });

export const hiveIdParam = z.object({ id: z.string().uuid() }).strict();
export const listHivesQuery = paginationSchema;  // §6.4 (limit 1~100 default 50)
```

- `userId`는 클라가 보내지 않는다 — 항상 `c.get('userId')`. **DB insert/update는 `{...body}` 무차별 스프레드 금지**, 명시 필드 화이트리스트만 set(`userId`/`id`/`deleted_at`/timestamps는 코드 결정 — Mass Assignment 차단, §13 MUST).
- `installedAt`은 UTC 저장, 클라가 KST 표시.

### 9.3 소유권 / IDOR 차단 (핵심, §13 MUST)
- `GET/PATCH/DELETE /v1/hives/:id`는 모두 **`queries.hives.getHiveByIdForUser(db, hiveId, userId)`** 로 먼저 조회(`WHERE id=? AND user_id=? AND deleted_at IS NULL` 강제):
  - 남의 hive id → `undefined` → `NOT_FOUND`(404). **403 아닌 404**(존재 누설 차단).
  - soft delete된 id → `undefined` → 404.
- 목록은 `queries.hives.listHivesByUser(db, userId, {limit, offset})` — `WHERE user_id=? AND deleted_at IS NULL ORDER BY updated_at DESC LIMIT ? OFFSET ?`. **헬퍼 내부에서 `limit=Math.min(opts.limit??50,100)` 방어적 클램프**(zod 우회 직접호출 대비, §13 SHOULD). offset hard cap(≤10000).
- 헬퍼 시그니처가 `userId`를 필수로 받아 구조적으로 IDOR가 어렵다.

### 9.4 Soft delete 정책
- `DELETE`는 `deleted_at = now()` 세팅(hard delete 금지). 종속 `analysis_images`/`analyses`는 **hard 보존**(법적/통계) — hive를 실제 DELETE하지 않으므로 cascade 미발동.
- user soft delete 시(1부) 해당 user의 hives도 같은 트랜잭션에서 `deleted_at` 일괄 세팅 + `sessions_valid_after` bump로 접근 차단.

### 9.5 위치정보(lat/lng) PIPA 처리
- 양봉장 좌표 = **위치정보**(위치정보보호법/PIPA). 
  - **선택 수집**: 좌표 optional, 미입력해도 hive 생성/진단 정상.
  - **목적 제한**: 트렌드/지역 통계 전용. 마케팅/제3자 제공 금지.
  - **정밀도 최소화**: numeric(9,6)이나 MVP 표시/통계엔 소수 4자리(≈11m)면 충분(과도 정밀도 지양).
  - **로그/감사 마스킹**: 좌표를 pino 로그·audit metadata에 평문 금지(§7.2 redact, §14.1). 
  - **삭제권**: soft delete된 hive 좌표 미표시, 탈퇴 시 hive와 함께 마스킹/파기(§13 파기권).

### 9.6 캐싱 (Redis)
- `GET /v1/hives`: 키 `cache:hives:{userId}`, TTL **60초**. hit 반환, miss 시 조회 후 `SETEX`.
- **write invalidate**: `POST`/`PATCH`/`DELETE` 성공 시 `cache:hives:{userId}` 즉시 `DEL`. 단일 hive 캐시는 MVP 미도입.
- 캐시는 **best-effort**: Redis 장애 시 로깅 후 DB fallthrough(가용성 우선 — quota/rate-limit의 fail-closed와 대비). 키가 `userId` 스코프라 사용자 간 누출 구조적 차단.

### 9.7 감사 로그
- hive CRUD는 민감 액션 아님 → 기본 미기록(pino 로그로 충분). 단 `DELETE`(soft delete)만 선택적 `action='hive.deleted', entity='hive', entity_id=:id`(좌표 제외) 1건.

---

## 10. Images 도메인 (계약, `routes/images.ts`)

> S3 presigned PUT — **서버는 바이너리를 직접 받지 않는다.** 1부 §7을 엔드포인트 2개로 계약화. presigned 발급/검증은 `services/s3-client.ts` 위임.

### 10.1 엔드포인트 계약 표

| 메서드/경로 | 인증 | 요청 (zod) | 응답 (data) | 주요 에러코드 |
|---|---|---|---|---|
| `POST /v1/images/presign` | 🔐 | json: `presignSchema` | `{ uploadUrl, objectKey, expiresIn:300 }` (5분) | `UNSUPPORTED_MEDIA`(415), `VALIDATION_FAILED`(400), `RATE_LIMITED`(429) |
| `POST /v1/images/confirm` | 🔐 | json: `confirmSchema` | `AnalysisImage` | `NOT_FOUND`(404), `IMAGE_NOT_FOUND_IN_STORAGE`(404), `IMAGE_INVALID`(422), `IMAGE_TOO_LARGE`(413) |

### 10.2 zod 스키마 (`schemas/images.ts`) — `.strict()`

```ts
const ALLOWED_MIME = ['image/jpeg', 'image/png', 'image/webp'] as const;

export const presignSchema = z.object({
  filename: z.string().trim().min(1).max(255),   // 확장자 추출용(신뢰 X, sniff가 진실)
  contentType: z.enum(ALLOWED_MIME),
}).strict();

export const confirmSchema = z.object({
  objectKey: z.string().min(1).max(512),         // presign 발급 키(서버가 패턴/소유 재검증)
  hiveId: z.string().uuid(),
  capturedAt: z.coerce.date().optional(),        // EXIF 보조(nullable)
}).strict();
```

### 10.3 S3 키 경로 + IDOR
- 키 패턴(1부 §7): **`images/{userId}/{yyyy}/{mm}/{uuid}.{ext}`** — presign 단계에서 서버가 `userId`/`yyyy`/`mm`/`uuid`/`ext` 전부 결정. 클라가 키를 정하지 않는다. `{ext}`는 검증된 `contentType`에서 매핑(filename 확장자 불신).
- **confirm IDOR 이중 방어**:
  1. `objectKey`가 `^images/{현재userId}/\d{4}/\d{2}/[0-9a-f-]{36}\.(jpg|png|webp)$` 매치 검사 → 키의 userId ≠ 토큰 userId면 `IMAGE_INVALID`(422).
  2. `hiveId`는 `queries.hives.getHiveByIdForUser(db, hiveId, userId)` 소유 검증 → 실패 `NOT_FOUND`(404).

### 10.4 presign 단계 (`POST /presign`)
1. `contentType` allowlist(zod enum) — 위반 `UNSUPPORTED_MEDIA`.
2. 서버가 `objectKey` 생성, `s3-client`가 presigned PUT 발급, 만료 **5분**(`expiresIn=300`).
3. presigned PUT 서명에 **`Content-Type` 조건 + `content-length-range 0~10MB`** 포함(클라가 다른 타입/과대 크기로 못 올리게, §13 SHOULD). 단 헤더는 최종 근거 아님 — confirm sniff가 진짜 검증.
4. 응답: `{ uploadUrl, objectKey, expiresIn:300 }`. uploadUrl 서명 쿼리스트링 로그 redact.
- **presign 전용 rate-limit**(30/min/user, §7.5). presign/confirm은 quota 미소모(quota는 `/analyses` success에만 차감 — 1부 확정).

### 10.5 confirm 단계 (`POST /confirm`) — 1부 §7 4·5 단계
1. **소유/키 검증** — §10.3.
2. **HEAD S3** — 없으면 `IMAGE_NOT_FOUND_IN_STORAGE`(404).
3. **크기 가드** — `Content-Length` ≤ **10MB**, 초과 시 객체 삭제 + `IMAGE_TOO_LARGE`(413).
4. **매직넘버 sniff** — `file-type` 등으로 컨테이너 내부까지 판별(`Content-Type` 헤더 불신). allowlist 불일치 시 객체 삭제 + `IMAGE_INVALID`(422).
5. **디컴프레션 폭탄 가드(§13 MUST)** — `sharp`에 `limitInputPixels`(24~50MP) + timeout. `width×height` 픽셀 상한도 검증(byte_size만으론 부족). sharp 디코드는 try/catch 격리(native 크래시 → graceful 실패 + 객체 삭제). 초과/실패 시 `IMAGE_TOO_LARGE`/`IMAGE_INVALID` + 객체 삭제.
6. **EXIF/GPS 제거 + 재인코딩** — `sharp` rotate(orientation) + strip + **재인코딩**(polyglot 무력화). EXIF 촬영 시각은 `capturedAt` 미제공 시 보조 사용(위경도는 즉시 폐기).
7. **메타 등록** — `analysis_images` 1 row insert(명시 필드만, 스프레드 금지):

| 컬럼 | 출처 | 비고 |
|---|---|---|
| `hive_id` | 요청 `hiveId`(소유 검증 후) | FK cascade |
| `uploaded_by` | `c.get('userId')` | FK restrict |
| `storage_url` | objectKey 기반 S3 URL | 바이너리 미저장 |
| `mime_type` | **sniff 결과**(헤더 아님) | NOT NULL |
| `width`/`height` | sharp 메타 | nullable |
| `byte_size` | strip 후 최종 크기 | nullable |
| `checksum` | strip 후 sha256 | 무결성 |
| `captured_at` | 요청 또는 EXIF(위치 제거 후) | nullable |

> `analysis_images`는 `created_at`만 존재(`updated_at` 없음) — insert만, 갱신 없음. filename은 저장/로깅 시 정규화(경로구분자/널바이트/제어문자 제거) 또는 미보관(§13 MUST).

8. 응답: 생성된 `AnalysisImage`. 이 `image.id`가 1부 `POST /v1/analyses` 입력(분석 처리는 1부 참조).

### 10.6 검증 실패 cleanup
- confirm 어느 단계든 실패 시 **S3 객체 즉시 삭제**(고아·비용 누수 차단). DB insert는 전 검증 통과 후에만 → 실패 시 DB 부산물 없음.
- presign만 받고 미PUT/미confirm: **S3 lifecycle(미확정 prefix expiration=1day)** 로 정리. Terraform `s3` 모듈에 추가 + `infra §9` 문서화(§13 SHOULD). 서버 추적 큐 미도입(1인 운영 단순화).

### 10.7 SSRF 차단 (1부 확정 — AI 위임 시, §13 MUST)
- AI 위임 시 `storage_url` **원문 전달 금지**. 서버가 `image_id`로 row 조회 → objectKey만 추출 → **자체 s3-client로 presigned GET 신규 발급(TTL 90~120s)** 해 그 URL만 ai에 전달(출처 단일화).
- `apps/ai`는 수신 URL host를 **S3 버킷/`cdn.helpbee.kr` allowlist 검증**, 해석된 IP가 사설/링크로컬/메타데이터(10/8, 172.16/12, 192.168/16, 169.254.169.254, 127/8)면 거부(DNS rebinding 고려). presigned GET allowlist host는 `config/env.ts`.

### 10.8 캐시/감사/레이트리밋
- confirm은 hive 메타 불변이라 `cache:hives` 무효화 대상 아님. presign/confirm은 빈번 → audit 미기록(pino). confirm 실패가 비정상 잦으면 메트릭/알람(§14, infra §12). rate-limit는 §7.5.

---

## 11. Subscriptions 도메인 (`routes/subscriptions.ts`)

### 11.0 목적과 1부 정합
plan(요금제)을 단일 진실 소스로 노출해 1부 두 게이트를 결정. 결제(PG)는 MVP 범위 밖, webhook은 inert scaffold.
- **무료 = YOLO 단독(폴백 X)** / **유료(basic·pro) = YOLO→OpenAI 폴백** — 폴백 게이트.
- **무료 quota = 추론 전 검사 + success 시점 차감** — quota 게이트(차감 시점/키/환불없음은 1부 확정, §11은 plan만 결정 — 재설계 금지).

DB(`subscriptions.ts`): `user_id UNIQUE NOT NULL`(FK cascade), `plan text DEFAULT 'free'` CHECK `IN ('free','basic','pro')`, `status text DEFAULT 'active'` CHECK `IN ('active','inactive','cancelled')`, `trial_ends_at`/`current_period_end`(nullable), timestamps.

### 11.1 엔드포인트 계약 표

| Method | Path | 인증 | 요청 (zod) | 응답 `data` | 에러 코드 |
|---|---|---|---|---|---|
| GET | `/v1/subscriptions/me` | 🔐 | — | `SubscriptionMe` | `AUTH_UNAUTHORIZED` |
| GET | `/v1/subscriptions/plans` | 🔓 | — | `PlanCatalog` (정적 stub) | — |
| POST | `/v1/subscriptions/webhook` | 🔓** | `webhookBodySchema` (raw 보존) | `{ received:true }` | `WEBHOOK_SIGNATURE_INVALID`, `WEBHOOK_DISABLED` |

### 11.2 응답 스키마 (zod + envelope)

```ts
export const PLAN_VALUES = ['free', 'basic', 'pro'] as const;          // DB CHECK 1:1
export const SUB_STATUS_VALUES = ['active', 'inactive', 'cancelled'] as const;

export const subscriptionMeSchema = z.object({                          // PII 없음
  plan: z.enum(PLAN_VALUES),
  status: z.enum(SUB_STATUS_VALUES),
  trialEndsAt: z.string().datetime().nullable(),
  currentPeriodEnd: z.string().datetime().nullable(),
  features: z.object({                                                   // 파생(클라 UX용)
    openaiFallback: z.boolean(),                                         // free=false, basic/pro(active)=true
    monthlyAnalysisQuota: z.number().int().nullable(),                  // free=4, 유료=null(무제한)
  }),
});

export const planCatalogSchema = z.object({                             // 정적 상수(DB 미접근)
  plans: z.array(z.object({
    id: z.enum(PLAN_VALUES), name: z.string(),
    monthlyAnalysisQuota: z.number().int().nullable(),
    openaiFallback: z.boolean(),
    priceKrwMonthly: z.number().int().nullable(),                       // MVP 표시만
  })),
});
```

`/plans`는 코드 상수(가격 변경 시 배포로 갱신 — 1인 운영 적정선).

### 11.3 plan 판정 단일 함수 (폴백·quota 게이트의 근원)

```ts
// services/subscription-service.ts — 라우트/analyses 양쪽이 동일 사용(게이트 일관성)
export async function resolveUserPlan(db, userId): Promise<{
  plan; status; openaiFallback: boolean; monthlyAnalysisQuota: number | null;
}> {
  // subscriptions row 조회(user_id UNIQUE). 없으면 free/active 기본.
  //   openaiFallback = (plan !== 'free') && status === 'active'
  //   monthlyAnalysisQuota = plan === 'free' ? 4 : null
  //   유료라도 status !== 'active'면 free로 강등(폴백 X, quota 4)
}
```

규칙: ① row 없는 신규 = `free/active`(누락 안전망). ② 유료라도 `status≠active`면 폴백·무제한 미적용(결제 실패/취소 시 권한 즉시 회수). ③ `trial_ends_at` 과거 + 연장 없음 → MVP는 webhook inert이므로 수동 강등(어드민 PATCH); 자동 강등 cron은 Phase 2.

### 11.4 POST /webhook — inert scaffold (MVP)
1. `webhookSignatureGuard`(라우트 최상단, zValidator 이전) — **raw body**(파싱 전 bytes)로 HMAC-SHA256, `X-HelpBee-Signature` vs `HMAC(secret, rawBody)` `timingSafeEqual`. 시크릿 Secrets Manager(`helpbee/{env}/webhook`).
2. **타임스탬프 윈도** — `X-HelpBee-Timestamp` ±5분 밖이면 replay reject. 추가로 **event_id/nonce를 Redis SET NX EX(24h)** 멱등 키로 윈도 내 replay 차단(§13 SHOULD).
3. MVP 플래그 `SUBSCRIPTION_WEBHOOK_ENABLED=false`(기본) → 서명 통과해도 본문 미처리, `{received:true}` 200 후 종료(inert). enable 시에만 plan/status mutation 활성. **plan 변경 대상은 서명된 payload 내 subscription만**(클라 userId 신뢰 금지).
4. 모든 수신은 `audit_log action='subscription.webhook', entity='subscription'`(성공·서명실패 모두). PII/카드정보 metadata 저장 금지(`{eventType, eventId}`만).
- 시크릿 미설정 시 `WEBHOOK_DISABLED`(503) fail-closed. enable 전까지 라우트 404도 옵션.

### 11.5 신규 에러 코드 — §6.3 enum: `WEBHOOK_SIGNATURE_INVALID`(401), `WEBHOOK_DISABLED`(503). `QUOTA_EXCEEDED`(402)는 분석 도메인(1부)에서 사용.

---

## 12. Admin 도메인 (`routes/admin.ts`)

### 12.0 2중 신원 보호 전제
1. **표면(네트워크)** — admin 콘솔/백엔드 호출 경로는 **Cloudflare Access(ZeroTrust) + IP allowlist**(`apps/admin §10`, `infra §14`). API `/v1/admin/*`도 동일 게이팅 뒤. **모든 비-prod 환경(preview/staging)에도 fail-closed**(§13 SHOULD).
2. **애플리케이션** — `requireAuth()` + `requireRole('admin')`. JWT는 admin httpOnly 쿠키 또는 Bearer. `users.role IN ('user','admin')`.
> 표면 보호는 인프라 책임이며 role 검사를 **대체하지 않는다**(defense in depth).

### 12.1 인가 미들웨어 — 401 vs 403 + BFLA 가드
```ts
app.use('/v1/admin/*', requireAuth(), requireRole('admin'));  // 단일 마운트, prefix 밖 admin 핸들러 금지
```
- **401 `AUTH_UNAUTHORIZED`** — 신원 미확인(재로그인). **403 `FORBIDDEN_ROLE`** — `role≠admin`(재로그인 무의미). 403에 필요 role 명 미노출.
- **BFLA 테스트 매트릭스를 CI에**: 모든 admin 경로에 anon→401 / role=user→403 검증, 가드 누락 admin 라우트 추가 시 실패(§13 SHOULD).

### 12.2 엔드포인트 계약 표

| Method | Path | 인증 | 요청 (zod) | 응답 `data` | 에러 코드 |
|---|---|---|---|---|---|
| GET | `/v1/admin/users` | 👑 | `adminUserListQuery` | `Paginated<AdminUserRow>` | `VALIDATION_FAILED`, `FORBIDDEN_ROLE` |
| PATCH | `/v1/admin/users/:id` | 👑 | path `id:uuid` + `adminUserPatchBody` | `AdminUserDetail` | `VALIDATION_FAILED`, `NOT_FOUND`, `ADMIN_SELF_DEMOTE_FORBIDDEN`, `FORBIDDEN_ROLE` |
| GET | `/v1/admin/audit-logs` | 👑 | `auditLogQuery` (cursor) | `CursorPaginated<AuditLogRow>` | `VALIDATION_FAILED`, `FORBIDDEN_ROLE` |
| GET | `/v1/admin/metrics` | 👑 | `metricsQuery` | `AdminMetrics` | `VALIDATION_FAILED`, `FORBIDDEN_ROLE` |
| GET | `/v1/admin/analyses/:imageId/dual` | 👑 | path `imageId:uuid` | `DualComparison` | `NOT_FOUND`, `FORBIDDEN_ROLE` |

> dual은 1부 확정 "비교는 어드민 `/analyze/dual` 전용". API 어드민 표면은 **저장된 두 엔진 row 조회·대조(읽기 전용)**(§12.6). 실시간 dual 추론 트리거는 `apps/ai` 책임.

### 12.3 zod 스키마 — 페이지네이션·필터 (`.strict()`)

```ts
export const pageQuery = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),  // 상한 100
}).strict();

export const adminUserListQuery = pageQuery.extend({
  search: z.string().trim().max(120).optional(),   // 이메일/이름 ILIKE(파라미터 바인딩)
  role: z.enum(['user', 'admin']).optional(),
  status: z.enum(['active', 'blocked', 'deleted']).optional(),  // §12.5 파생
}).strict();

export const adminUserPatchBody = z.object({
  role: z.enum(['user', 'admin']).optional(),
  status: z.enum(['active', 'blocked']).optional(),  // deleted는 별 경로(soft delete), PATCH 금지
}).strict().refine((b) => b.role !== undefined || b.status !== undefined, { message: 'role 또는 status 필수' });

export const auditLogQuery = z.object({
  cursor: z.coerce.bigint().optional(),    // 마지막 audit_log.id keyset
  limit: z.coerce.number().int().min(1).max(100).default(50),
  entity: z.string().max(60).optional(), action: z.string().max(60).optional(),
  actorId: z.string().uuid().optional(),
  from: z.string().datetime().optional(), to: z.string().datetime().optional(),
}).strict();

export const metricsQuery = z.object({
  from: z.string().datetime().optional(), to: z.string().datetime().optional(),
  granularity: z.enum(['day', 'week']).default('day'),
}).strict();
```

### 12.4 응답 스키마 — PII 최소화

```ts
export const adminUserRowSchema = z.object({       // password_hash 절대 X
  id: z.string().uuid(), email: z.string().email(),  // 운영 식별(콘솔은 ZeroTrust 뒤)
  name: z.string(), role: z.enum(['user', 'admin']),
  status: z.enum(['active', 'blocked', 'deleted']),  // 파생(§12.5)
  emailVerifiedAt: z.string().datetime().nullable(),
  createdAt: z.string().datetime(),
  plan: z.enum(['free', 'basic', 'pro']).nullable(),
});
export const adminUserDetailSchema = adminUserRowSchema.extend({
  updatedAt: z.string().datetime(), deletedAt: z.string().datetime().nullable(),
  subscriptionStatus: z.enum(['active', 'inactive', 'cancelled']).nullable(),
  analysisCount: z.number().int(),
});
export const auditLogRowSchema = z.object({
  id: z.string(),                    // bigint → 문자열 직렬화(2^53 초과 안전, §13 SHOULD)
  actorId: z.string().uuid().nullable(), action: z.string(), entity: z.string(),
  entityId: z.string().uuid().nullable(),
  metadata: z.record(z.unknown()).nullable(),  // 기록 단계에서 이미 redact(§12.7)
  ip: z.string().nullable(), userAgent: z.string().nullable(),
  createdAt: z.string().datetime(),
});
```
DB 정합: `audit_log`(`id bigserial`, `actor_id uuid nullable set null`, `action/entity text`, `entity_id uuid`, `metadata jsonb`, `ip/user_agent text`, `created_at`) ↔ `auditLogRowSchema` 1:1. `id`는 **string 직렬화**.

### 12.5 status 파생 모델 (신규 컬럼 — DB 도메인 위임)
`users`에 `status` 컬럼 없음(실제 스키마). status는 **파생**(1부 "tier 재계산" 철학과 동일):
```
status = deleted_at IS NOT NULL → 'deleted'
       : blocked_at IS NOT NULL → 'blocked'
       : 'active'
```
- **차단은 §13 MUST에 따라 `users.blocked_at` 컬럼 추가**(DB 도메인 PR) + `sessions_valid_after` 마커 bump(즉시 회수). 이전 "refresh revoke만으로 효과상 차단(완전 차단 아님)" 방식은 폐기 — blocked_at + Redis 마커로 진짜 회수(§7.9, §8).
- PATCH는 `status='active'`(해제)/`'blocked'`(차단)만. `deleted` 전환은 user 본인 soft delete 흐름이며 admin PATCH 금지(운영자 임의 삭제 차단).

### 12.6 진단 비교(dual) — 읽기 전용 대조
```
GET /v1/admin/analyses/:imageId/dual
```
- `analyses`에서 `image_id = :imageId` row 전체 조회(최대 2: openai·yolo) + `ai_models` 조인(`provider`/`name`/`version`).
- 응답 `DualComparison`: `{ primary, secondary, agreement }`(1부 ai-client dual 명명 정합). `primary`=실제 사용 엔진(정상=YOLO 1행), `secondary`=비교용(있을 때만), `agreement`=tier 일치·risk 차이. 1행만 있으면 `secondary=null, agreement=null`.
- 정상 운영 저장은 사용 엔진 1행뿐(1부). dual 2행은 어드민이 `/analyze/dual` 명시 실행 시에만 존재.
- `raw_response`는 어드민 비교에 노출하되 **EXIF/GPS/PII/원본 URL은 저장 단계에서 이미 화이트리스트 정제된 상태**(bbox/score/tier만, §13 MUST). bbox 좌표는 BboxOverlay용으로 전달. **dual 응답도 동일 화이트리스트 투영**(이중 방어).

### 12.7 모든 admin 변경 → `audit_log` (필수)
**mutation(PATCH)만 기록**(GET 미기록, 노이즈·row 증가 억제):

| 액션 | `action` | `entity`/`entity_id` | `metadata`(redact 후) |
|---|---|---|---|
| role 변경 | `admin.user.role_change` | `user`/대상 id | `{ before, after }`(role 값만) |
| 차단/해제 | `admin.user.status_change` | `user`/대상 id | `{ before, after }`(status 값만) |
| webhook 수신 | `subscription.webhook` | `subscription`/대상 id | `{ eventType, eventId }`(카드/PII 금지) |

- `actor_id`=요청 admin userId, `ip`/`user_agent`=요청 헤더(redact 정책). metadata에 before/after 값만(비번/토큰/이메일 평문 금지).
- **mutation + audit insert는 동일 트랜잭션**(변경됐는데 로그 누락 방지). audit insert는 전용 헬퍼(`queries/auditLog.ts`)로 metadata 허용 키 화이트리스트 타입 강제(임의 jsonb 직접 insert 금지, §13 SHOULD).

### 12.8 self-demote 가드 (경합 안전)
- 마지막 admin 강등 시 admin 0 사고 → `ADMIN_SELF_DEMOTE_FORBIDDEN`(409).
- **같은 트랜잭션에서 `SELECT count(role='admin' AND deleted_at IS NULL) FOR UPDATE`(또는 SERIALIZABLE) 후 강등 적용, 1 미만 되면 거부**(비잠금 COUNT는 동시 2 demote가 모두 통과 → admin 0 락아웃, §13 SHOULD). 동시 2 demote에서 ≥1 admin 잔존 검증(§15).

### 12.9 metrics — 집계 읽기 (1인 운영 적정)
- 사용자: 전체/활성(최근 N일 분석) — `users`(deleted_at IS NULL).
- 진단: 기간별 `analyses`(status='success'), `ai_models.provider`로 엔진별(YOLO vs OpenAI 폴백 비율).
- 구독: plan별 분포 — `subscriptions` GROUP BY plan.
- 비용: `apps/ai` 콜백 누적값 출처(1부/ai). MVP는 stub/합산. day/week GROUP BY + 인덱스, 무거운 쿼리는 Redis 캐시 TTL 60s.
- 집계 쿼리는 전부 `@helpbee/database/queries/*` 헬퍼(직접 SQL 금지). admin은 전체 접근이나 **soft delete 필터·파라미터 바인딩** 동일 적용.

### 12.10 신규 에러 코드 — §6.3 enum: `FORBIDDEN_ROLE`(403), `ADMIN_SELF_DEMOTE_FORBIDDEN`(409). `NOT_FOUND`/`VALIDATION_FAILED`/`AUTH_UNAUTHORIZED`는 공통 재사용.

---

## 13. 🔒 보안 강화 (엄격) — OWASP API Top 10 + PIPA 매핑 표

> 채택 hardening을 **MUST(본문 이미 반영)** / **SHOULD(권장, 본문 반영)** 로 분류. nice-to-have는 §17. 각 항목은 실측 근거(파일·라인 또는 확정결정)를 가진다.

### 13.1 P0 운영 사고 (출시 차단 게이트 — 설계 검토보다 우선)

| # | 영역 | 분류 | 조치 | 근거 |
|---|---|---|---|---|
| P0 | Secrets/Ops · API8 Misconfiguration | **MUST** | **AWS ROOT 액세스 키(account 491919374695) 즉시 비활성화·삭제·회전.** root MFA 강제, 모든 S3 접근을 ECS task role + GHA OIDC로 전환. CloudTrail로 root 키 과거 사용·유출 점검. `.env.example`의 `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` 장기키 슬롯 제거(로컬=SSO/aws-vault, 배포=task role). | `docs/05-implementation/2026-06-08-v010-yolo-baseline.md:30,154`에 "root 키 사용, 즉시 회전 필수" 미해결 명문. root 키는 권한경계 없이 S3 사용자 사진(개인정보) 포함 계정 전체 장악 가능. |
| P0 | Secrets 누출 방지 · API8 | **MUST** | **gitleaks를 pre-commit hook + CI(GHA) 필수 게이트**로 설치(권장→필수). `.gitignore`를 `.env*` 광역 + `!.env.example` 화이트리스트로 보강(현재 `.env.staging` 미커버). `REFRESH_TOKEN_PEPPER`/`JWT_SECRET`/`AI_INTERNAL_HMAC_SECRET` 커스텀 룰. | 실측: gitleaks 미설치, `.pre-commit-config.yaml` 없음, `git check-ignore .env.staging` = NOT IGNORED. staging 시크릿 우발 커밋 경로 실재. infra §8 '권장' 통제 0건. |

### 13.2 OWASP API Top 10 매핑

| OWASP 항목 | 위협(HelpBee 맥락) | 채택 hardening | 분류 |
|---|---|---|---|
| **API1: BOLA/IDOR** | 임의 hiveId/analysisId/imageId로 타인 데이터(raw_response 포함) 조회·생성 | `listAnalysesByHive`→`listAnalysesByHiveForUser(db,hiveId,userId)` 재시그니처(`getHiveTrend` 패턴 복제: innerJoin(hives)+userId+isNull(deletedAt)). `getAnalysisByIdForUser`/`getAnalysisImageByIdForUser` 신규. `userId`를 모든 read 헬퍼 필수 인자. 비소유→`NOT_FOUND`(404). (§9.3, §10.3, 1부 analyses) | **MUST** |
| **API1 (write-side)** | 타인 imageId로 분석 생성(cross-tenant write) | `POST /analyses`는 추론 전 `getAnalysisImageByIdForUser(db,imageId,userId)`(uploaded_by + hive.userId + deletedAt) → 미소유 404. `hiveId`는 검증된 image row에서 파생/교차검증(클라 입력 불신). (§10, 1부) | **MUST** |
| **API1 (logout 경로)** | victim refresh를 attacker가 `/logout` 제시 → victim 세션 대량 revoke | `/logout` user_id≠caller면 no-op(200, suspicious audit), reuse-detection 분기 진입 금지. 전체 revoke는 `/refresh`의 grace-밖 revoked-owned 토큰에만(§8.3, §8.4) | **SHOULD** |
| **API2: Broken Authentication** | JWT alg confusion / refresh 재사용 무력화 / 세션 비회수 / 약한 시크릿 | (a)JWT **alg 핀 강제**(HS256만, none/RS256/헤더불일치 거부; `jwt-simple` decode 4번째 인자 필수, `jose` 권장). (b)refresh `token_hash`=**HMAC-SHA256(pepper)**, 비번=argon2id, 별도 서비스 분리; `refreshTokens.ts:8` 주석 정정. (c)**`users.blocked_at` + Redis `sessions_valid_after:{userId}` 마커**로 즉시 회수(block/탈퇴/비번·이메일 변경/reuse 시 bump + `revokeAllRefreshTokensForUser`). (d)`JWT_SECRET` min 64·플레이스홀더 부팅 거부, access 시크릿≠refresh pepper, admin 토큰 별 audience. `JWT_EXPIRATION=24h` 제거→access 15m/refresh 7d, `AWS_REGION=ap-northeast-2`, S3 버킷 env 분리, SMTP_PASSWORD→SES IAM/Secrets. (§7.9, §8.4, §8.5, §16) | **MUST** |
| **API2 (brute-force)** | argon2(19MB/호출) 매 시도 → CPU/메모리 DoS, victim lockout-DoS | rate-limit/lockout 카운터를 **argon2 verify 이전** 게이트. 복합 키(email+IP) + 별도 per-IP cap. 예: 10 fails/15min/email-IP→15m lockout, per-IP 30/min(§8.5.3) | **MUST** |
| **API2 (refresh 동시성)** | 모바일 다중 refresh 동시 발사 → loser가 reuse-detection→강제 로그아웃(오탐) | refresh 회전 **grace window**(같은 user/device, grace 내 revoke면 유효쌍 반환). token-family. 동시 2 refresh 강제 로그아웃 0 검증(§8.4) | **MUST** |
| **API2 (이메일 검증 게이트)** | 자가주장 `ev` 클레임을 authorization 소스로 신뢰 | 권위 소스는 Redis(`email_verified:{userId}`)+DB fallback, `ev`는 UX 힌트만. 검증 시 마커 bump/refresh 강제(§8.8) | **SHOULD** |
| **API2 (IP 추출)** | XFF 위조로 limiter 우회 / audit IP 오염 / lockout framing | 신뢰 프록시 홉 인지 파서(CloudFront+ALB 홉 기준 XFF N번째 또는 CloudFront 주입). 위조 XFF가 limiter 리셋 못 함(§7.5) | **SHOULD** |
| **API3: BOPLA/Mass Assignment** | `{...body}` 스프레드로 user_id/role/deleted_at 주입 → ownership 탈취 | 모든 mutation zod `.strict()`(모르는 키 400). DB insert/update 명시 화이트리스트만(스프레드 금지). WHERE user_id 스코프. 'DB set/values 통째 스프레드 금지' 리뷰 체크리스트화. 실측: `createDualAnalysis`(analyses.ts:26,44) 스프레드 컨벤션을 hive에 전파 금지(§6.4, §9.2, §10.5) | **MUST** |
| **API3 (raw_response PII)** | 어드민 dual이 raw_response 원본 노출, hard 보존 | 저장 전 **allowlist 정제**(bbox/score/tier만, OpenAI 원본/base64/free-text/url/exif/gps/filepath/email drop)를 apps/api 코드 강제(주석 아닌 테스트 가드). 일반 사용자 응답엔 raw_response 미포함(PublicAnalysis 투영). 어드민 dual도 동일 투영. 테스트: 응답에 `http(s)://`·gps/lat/lng·이메일 0건(§12.6) | **MUST** |
| **API4: Unrestricted Resource Consumption** | 같은 image_id 재전송→YOLO CPU 무한/유료 OpenAI 비용 재발생 | **멱등 게이트를 추론 호출 이전으로 이동**: `POST /analyses` 진입 시 `SELECT WHERE image_id,model_id,status='success'`면 AI 미호출+기존 반환(short-circuit). `createSingleAnalysis`는 onConflictDoNothing+재조회, success row 절대 덮어쓰기 금지(failed/pending에만 조건부 update `WHERE status<>'success'`). 실측: `createDualAnalysis`(analyses.ts:27-58)의 onConflictDoUpdate가 success까지 덮어씀=확정 위반(1부 must, 확정4) | **MUST** |
| **API4 (quota TOCTOU)** | 검사<4 동시 N건 통과→N건 추론(quota 초과 소비) | quota **reserve-then-refund**: 추론 직전 원자 INCR 예약→반환>4면 차단(402), success면 유지, 실패면 DECR 환불. 멱등 short-circuit만 무차감. EXPIRE 월말 KST. Redis 장애 fail-closed. 확정2(success 차감)의 의도와 정합하며 동시성 차단(§7.5, 1부) | **MUST** |
| **API4 (커넥션 풀)** | 동기 AI 호출(30s)이 db.transaction 안에서 커넥션 점유→풀 고갈→전체 정지 | (1)검증·quota예약 짧은 커넥션→반납 (2)AI 호출 커넥션 미보유 (3)영속 짧은 커넥션. **db.transaction 안 외부 HTTP 금지**. (task수×POOL_MAX)≤RDS max_connections 검증. `/analyses` task 전역 in-flight 세마포어(초과 429+Retry-After). 실측: `client.ts` 풀 max 10(§16) | **MUST** |
| **API4 (OpenAI 폴백 비용)** | 유료 quota=null → 결함 이미지 반복으로 폴백 비용 무한 | 폴백 월/일 soft cap, 초과 시 YOLO-only graceful. ai 예산초과를 `AI_BUDGET_EXCEEDED`로 식별→폴백 차단+Slack. api에도 예산 가드 이중화. 멱등 short-circuit으로 재전송 폴백 차단(확정 폴백=유료전용 불위반)(§6.3, 1부) | **MUST** |
| **API4 (계정 양산)** | 분산 IP signup 폭주→argon2 메모리 DoS + 무료 quota 무한 우회 | signup IP+이메일도메인 엄격 sliding window(5/min/IP+일일 상한)+WAF rate-based. argon2가 카운터 게이트 이후 도달. 무료 quota를 이메일 검증 완료 전 0(§7.5, §8.3, §8.8) | **MUST** |
| **API4 (페이지네이션)** | `GET /hives` 무한 반환 / 헬퍼 limit 미클램프 / 깊은 offset 풀스캔 | `GET /hives`에도 paginationSchema. 헬퍼 내부 `limit=min(opts.limit??50,100)` 방어 클램프. offset hard cap(≤10000) 또는 keyset. bigint cursor string 직렬화. 인덱스 검토(§6.4, §9.3, §12.3) | **SHOULD** |
| **API4 (audit_log 성장)** | credential stuffing이 login_failed insert 폭증→gp3 디스크 소진→DB 장애 | 공격유발 이벤트(로그인/서명 실패)는 매건 insert 대신 집계/샘플링. audit_log 보존기간(90~180일)·월 파티셔닝·정리 cron 베타 전 확정. 레이트리밋이 audit insert보다 먼저 게이트. RDS 디스크<20% 알람(§8.6, §14.3) | **SHOULD** |
| **API4 (이미지 폭탄)** | 수MB JPEG가 수억 픽셀 디코드→sharp OOM→컨테이너 사망 연쇄 | confirm sharp `limitInputPixels`(24~50MP)+timeout+실패 객체삭제. width×height 픽셀 상한. `file-type`로 컨테이너 판별, sharp try/catch 격리. 재인코딩으로 polyglot 무력화. filename 정규화/미보관(§10.5) | **MUST** |
| **API5: BFLA** | admin 라우트 가드 누락 / preview·staging ZeroTrust 미적용 | `/v1/admin/*` 단일 마운트(prefix 밖 핸들러 금지). anon→401/user→403 BFLA 매트릭스 CI. 모든 비-prod ZeroTrust/IP allowlist fail-closed. self-demote `FOR UPDATE`+1미만 거부(§12.1, §12.8) | **SHOULD** |
| **API6: SSRF** | 오염된 storage_url을 ai가 따라가 내부 메타데이터/사설망 GET | AI 위임 시 storage_url 원문 금지→objectKey만 추출해 자체 presigned GET(90~120s) 단일화. apps/ai host allowlist(S3/cdn) + 사설/링크로컬/메타데이터 IP 거부(DNS rebinding). presign content-length-range·버킷 도메인 화이트리스트(§10.7) | **MUST** |
| **API7: SSRF/Injection 일반** | search ILIKE·SQL 보간 | Drizzle parameterize에 위임(직접 보간 금지). admin search 파라미터 바인딩(§12.3, 1부) | (1부 참조) |
| **API8: Security Misconfiguration** | 에러 정보 노출 / CORS·헤더 미흡 / presign 남용·고아 객체 | 비-AppError detail 고정 문구(원본 Sentry만), zod issue path만, pg constraint명 미노출. CORS allowlist 정확 매칭+credentials 매칭 시만, CSP/Permissions-Policy 추가. presign 서명에 content-length-range, 미확정 prefix lifecycle 1day(Terraform). (§6.2, §7.3, §7.4, §7.8, §10.4, §10.6) | **SHOULD** |
| **API9: Improper Inventory** | env별 통제 드리프트 | env 통제 일치(preview도 fail-closed), `.env.example` 동기화 의무, region/버킷 env 분리(§12.0, §16) | **SHOULD** |
| **API10: Unsafe Consumption** | OpenAI 응답 무검증 수용 | ai 응답을 Pydantic/zod로 검증·정제 후 allowlist 투영(API3 raw_response와 동일)(§12.6, 1부) | (1부 참조) |

### 13.3 추가 인증/감사 무결성

| 영역 | 조치 | 분류 |
|---|---|---|
| audit 무결성 (API2) | `audit_log.actor_id` ON DELETE SET NULL 유지하되 metadata에 불변 actor 참조(uuid를 text 복사/이메일 해시) 영속. audit history 있는 계정은 보존기간 내 hard delete 금지(soft-only). (§8.6, §12.7) | **SHOULD** |
| webhook 보안 (API5/API8) | raw bytes HMAC `timingSafeEqual`, 서명 미들웨어 zValidator 이전, event_id Redis SET NX EX(24h) replay 차단, 서명 payload 내 subscription만 변경, fail-closed(§11.4) | **SHOULD** |
| 입력 정규화 (API8) | `normalizeEmail(trim→NFKC→toLowerCase)` 단일 유틸로 signup/login/실패카운터/조회 통일(homoglyph 중복·카운터 우회 차단)(§8.2) | **SHOULD** |
| PII 로깅 (API8) | pino redact 단일 목록에 lat/lng/address/capturedAt/uploadUrl/rawResponse/내부bearer 추가, req.body 통째 금지, Sentry beforeSend 동일 deep-redact(§7.2, §14.1) | **SHOULD** |
| audit metadata (API8) | audit insert 전용 헬퍼로 허용 키 화이트리스트 타입 강제(임의 jsonb 금지), webhook은 eventType/eventId만, ip/user_agent 보존기간 명시. `apps/api §9.2` 컬럼 문서를 실제 스키마로 정정(§12.7, §14.3) | **SHOULD** |

### 13.4 PIPA / 위치정보보호법 매핑

| 법적 요건 | HelpBee 위협 | 채택 조치 | 분류 |
|---|---|---|---|
| 개인정보 파기(법 제21조) / 삭제권 | analysis_images·analyses hard 보존이라 탈퇴해도 사진(개인정보)+좌표(위치정보) 영구 잔존→파기 의무 위반 | 탈퇴/파기요구 흐름: analysis_images가 가리키는 **S3 객체 삭제**(단기 grace 후 영구 파기)+storage_url null화/행 anonymize. '통계 보존'은 사진 파기 후 **집계 수치만 남기는 비식별 파이프라인**으로 분리(원본 사진 hard 보존 금지). 보존기간·파기 cron·삭제 SLA(예 30일)+audit 기록(§9.5) | **MUST** |
| EXIF/GPS 위치정보 처리 최소화 | 사진 EXIF의 GPS가 그대로 저장→위치정보 무단 보관 | confirm EXIF/GPS strip 필수 경로, 실패 시 저장 거부. 위경도는 추출 후 즉시 폐기, capturedAt만 사용(§10.5) | **MUST** |
| raw_response 내 위치/PII | OpenAI raw payload에 위치·식별정보 echo 가능, hard 보존 | 저장 전 allowlist 정제(GPS/lat/lng/url/email drop), 어드민 노출도 화이트리스트 투영(§12.6, API3) | **MUST** |
| 위치정보·개인정보 동의(별도 동의·고지) | 모바일이 계정·벌통 이미지·EXIF 위치 대량 수집하나 백엔드에 동의 획득·버전 기록·철회 처리 부재 | signup/최초 진단 전 '개인정보 수집·이용' + '위치정보(선택)' **분리 동의**, 동의 버전/시각/항목을 서버 기록(consents 테이블 또는 `audit_log action='consent.granted'`). EXIF GPS는 capturedAt만 쓰고 위경도 즉시 폐기. hive 좌표는 명시 입력 시만 위치정보 취급·동의 연결. 철회 시 좌표/사진 파기 경로 연결(§9.5) | **SHOULD** |
| 로그/감사 내 위치정보 마스킹 | 좌표가 로그·audit metadata 평문 잔존 | redact 단일 목록에 lat/lng/address(§7.2, §14.1). audit metadata 좌표 제외(§9.7, §12.7) | **SHOULD** |

---

## 14. 관측성 · 감사

### 14.1 구조화 로깅 (pino)
- 단일 pino 설정(`lib/logger.ts`)을 logger 미들웨어·서비스 계층이 공유: `requestId, userId, route, latencyMs, status`(+ 서비스 로그는 `engine`, `modelVersion`).
- **redact 단일 소스**(§7.2): `authorization`/`cookie`/`set-cookie`, `password*`/`token*`/`tokenHash`/`refreshToken`, presigned URL 서명 쿼리스트링, **`latitude`/`longitude`/`address`/`capturedAt`**(위치정보), `rawResponse`/`raw_payload`, 내부 bearer. AI raw payload 통째 로깅 금지(필요 시 키만). req.body allowlist만.
- `infra §11` `awslogs` 드라이버로 stdout→CloudWatch(api=pino, ai=structlog).

### 14.2 에러 추적 (Sentry)
- api(Hono) Sentry. `requestId`를 tag로 부착(로그↔이벤트 추적). **PII/secret은 beforeSend deep-redact**(§14.1 목록 재사용). DSN env(`SENTRY_DSN`), 미설정 시 비활성(로컬).

### 14.3 audit_log 스코프 — 기록/비기록
실제 테이블: `audit_log(id bigserial, actor_id uuid nullable FK set null, action, entity, entity_id uuid nullable, metadata jsonb, ip, user_agent, created_at)`. **`created_at`만 존재**(updated_at 없음, hard 보존).

**기록 대상**(보안·운영 추적 필요): 로그인/로그아웃/refresh 회전/재사용 감지, 비번·이메일·role 변경, 결제/구독 상태 변경(webhook), admin 데이터 수정. consent 획득/철회(§13.4).

**비기록**(1부 확정): **분석 성공/일상 조회는 audit_log에 넣지 않는다**(양 많고 보안 추적 대상 아님 — `analyses`가 진실 원천, 운영 지표는 메트릭/로그). quota 차감/조회도 비대상.

기록 규칙: `actor_id`(시스템/익명이면 NULL 가능), `entity`/`entity_id` 대상, `metadata` PII 최소화. **공격유발 이벤트(로그인/서명 실패)는 집계/샘플링**(§13 SHOULD). ip/user_agent 보존기간·파티셔닝·정리 cron은 1M row 전 결정(§17). insert 실패가 본요청을 깨지 않게 try/catch 격리 + ERROR 로그. 
> 정합 메모: `apps/api §9.2`의 `userId/actorId/target` 표기는 실제 스키마(`actor_id/entity/entity_id`)와 드리프트 — 구현은 실제 스키마, 문서 후속 정정(§17).

### 14.4 헬스/준비성
- 기존 `GET /health`(liveness, 의존성 미접근) 보존. 별도 `GET /ready`(readiness)에서 DB ping + Redis ping(`infra` smoke: /health,/ready). **AI 의존성은 readiness 미포함**(폴백 가능 + 순환 의존 회피).

---

## 15. 테스트 전략 (보안 테스트 포함)

러너 `vitest`, 라우트는 Hono `app.request(...)` in-process. DB Testcontainers PG, Redis db 15 + 매 테스트 `FLUSHDB`(`apps/api §11`).

### 15.1 인프라 격리
- `tests/helpers/`: test app factory(미들웨어 체인 동일 마운트), Testcontainers PG 기동→`@helpbee/database` 마이그레이션 적용, Redis db15, JWT 발급 유틸(access/refresh). 매 suite 깨끗한 PG, 매 테스트 Redis `FLUSHDB`. AI/S3 모킹(추론 자동재시도 없음 — 1부 — 이므로 단일 호출 mock).

### 15.2 커버리지/도메인
- 목표 routes 80%, services/lib 90%. envelope/problem 헬퍼: 성공 봉투 형태, 에러 코드↔status round-trip.

### 15.3 보안 테스트 (`tests/security.test.ts`, CI 게이트 포함)
1. **IDOR**: user A 토큰으로 user B의 hiveId/analysisId/imageId GET/PATCH/DELETE → **404 NOT_FOUND**(존재 누설 X). 쿼리 계층 userId 조인이 빈 결과 반환 동반 검증.
2. **refresh 재사용 감지**: 1회전 후 구 refresh 재사용 → `REFRESH_REUSE_DETECTED`(401) + 해당 user 전체 refresh `revoked_at` 세팅 확인. **grace window**: 동시 2 refresh → 강제 로그아웃 0 검증.
3. **logout cross-tenant**: victim refresh를 attacker `/logout` 제시 → victim 세션 유지(no-op).
4. **quota**: 무료 user 성공 4회 후 5번째 → `QUOTA_EXCEEDED`(402). 실패 분석 무차감(AI mock 실패→카운터 불변). 동시 병렬 2건 reserve-then-refund로 5회 초과 안 됨(레이스). 멱등 short-circuit 무차감.
5. **멱등**: 같은 image_id,model_id success 재요청 → AI 미호출 + 기존 리소스 반환(재과금 0).
6. **매직넘버/폭탄**: image/jpeg 위장 비-이미지 confirm → `IMAGE_INVALID`(415/422). 10MB 초과 → `IMAGE_TOO_LARGE`(413). 초고픽셀 → limitInputPixels 거부.
7. **JWT alg**: alg=none 거부, alg=RS256 거부, 다른 시크릿 서명 거부, 헤더 alg≠HS256 서명검증 전 거부.
8. **brute-force 순서**: 로그인 throttle 중 argon2 미호출(11 fails→`AUTH_ACCOUNT_LOCKED` 429+Retry-After).
9. **세션 즉시 회수**: block/비번변경 후 기존 access(미만료)로 보호 라우트 → 거부(`sessions_valid_after` 마커).
10. **BFLA**: 일반 user `/v1/admin/*` → `FORBIDDEN_ROLE`(403), 무인증 → 401. self-demote 동시 2건 → ≥1 admin 잔존.
11. **Mass Assignment**: hive PATCH에 `userId`/`deleted_at`/`role` 주입 → `.strict()` 400(or 무시되어 DB 미반영).
12. **PII 누출**: raw_response/사용자 응답에 `http(s)://`·gps/lat/lng·이메일 0건. 에러 detail에 테이블/컬럼/constraint명 0건.
13. **webhook**: 서명 불일치→`WEBHOOK_SIGNATURE_INVALID`(401), inert 시 plan 미변경, replay(동일 event_id) 차단.

### 15.4 CI 게이트
`type-check → lint → test`(보안 테스트 포함). gitleaks(§13.1)도 CI 필수 게이트. BFLA 매트릭스 포함.

---

## 16. 설정 · 시크릿

### 16.1 `config/env.ts` — zod 검증 단일 진입점 (fail-fast)
`process.env` 직접 참조 **전면 금지**(`apps/api §13.2`). 부팅 시 zod 1회 검증·파싱, typed 객체만 export. 미충족/플레이스홀더 시 **즉시 fail-fast**(기동 거부, §13 MUST).

```ts
const EnvSchema = z.object({
  NODE_ENV: z.enum(['development','test','production']).default('development'),
  PORT: z.coerce.number().default(3001),               // 현 index.ts의 PORT와 통일(아래 정정)
  DATABASE_URL: z.string().url(),
  DATABASE_POOL_MAX: z.coerce.number().default(10),     // (task수×POOL_MAX)≤RDS max_connections 검증
  REDIS_URL: z.string().url(),
  JWT_SECRET: z.string().min(64),                       // 강도 강제(§13 MUST)
  JWT_ACCESS_TTL: z.string().default('15m'),            // 1부 access 15m
  JWT_REFRESH_TTL: z.string().default('7d'),            // 1부 refresh 7d
  JWT_ADMIN_AUDIENCE: z.string().default('helpbee-admin'),
  REFRESH_TOKEN_PEPPER: z.string().min(32),             // HMAC-SHA256(server pepper), JWT_SECRET과 다른 값
  CORS_ALLOWLIST: z.string().transform(s => s.split(',').map(v=>v.trim()).filter(Boolean)),
  AI_BASE_URL: z.string().url(),                        // 사설 서브넷
  AI_INTERNAL_HMAC_SECRET: z.string().min(32),          // 1부 D10: api→ai 단기 HMAC bearer
  AI_REQUEST_TIMEOUT_MS: z.coerce.number().default(30000),
  AI_INFLIGHT_MAX: z.coerce.number().default(8),        // /analyses 세마포어(API4 풀 보호)
  AWS_REGION: z.string().default('ap-northeast-2'),     // 서울(§13: us-east-1 정정)
  S3_IMAGES_BUCKET: z.string(),                         // helpbee-images-{env}
  S3_PRESIGNED_GET_TTL_SEC: z.coerce.number().default(120),  // 1부 90~120s
  S3_GET_HOST_ALLOWLIST: z.string().transform(s => s.split(',')),  // SSRF host allowlist
  WEBHOOK_HMAC_SECRET: z.string().min(32).optional(),
  SUBSCRIPTION_WEBHOOK_ENABLED: z.coerce.boolean().default(false),
  SENTRY_DSN: z.string().url().optional(),
  OPENAI_API_KEY: z.string().optional(),               // 유료 폴백 전용(1부)
  OPENAI_FALLBACK_MONTHLY_CAP: z.coerce.number().default(0),  // 0=무제한 아님, 운영값 주입
  AUTH_LOGIN_MAX_FAILS: z.coerce.number().default(10),
  AUTH_LOCKOUT_WINDOW_SEC: z.coerce.number().default(900),
}).superRefine((v, ctx) => {
  if (/your_.*_here|changeme|placeholder/i.test(v.JWT_SECRET)) ctx.addIssue({ code:'custom', message:'placeholder JWT_SECRET' });
  if (v.JWT_SECRET === v.REFRESH_TOKEN_PEPPER) ctx.addIssue({ code:'custom', message:'JWT_SECRET must differ from pepper' });
});
export const env = EnvSchema.parse(process.env);
```

규칙: 신규 변수는 **`config/env.ts` zod + `.env.example` 동시 갱신**(`apps/api §14` 체크리스트). 시크릿(JWT_SECRET, REFRESH_TOKEN_PEPPER, AI_INTERNAL_HMAC_SECRET, WEBHOOK_HMAC_SECRET, OPENAI_API_KEY, DB 패스워드)은 **AWS Secrets Manager**, 비민감 설정은 **SSM Parameter Store**(`infra §8`). 로컬만 `.env`(git ignored, gitleaks §13.1). ECS task role 주입, 평문 환경변수 시크릿 금지.

### 16.2 현 `.env.example` ↔ 설계 정합 정정 (구현 PR 대상)

| 현재 값 | 문제 | 정정 |
|---|---|---|
| `API_PORT=3001` | 코드/env 키 불일치(`index.ts`는 `PORT` 읽음) | `PORT=3001`로 단일화(둘 다 지원 금지 — typo 은폐 방지) |
| `JWT_EXPIRATION=24h` | 1부 access 15m/refresh 7d 불일치(폭발반경 96배) | `JWT_ACCESS_TTL=15m`, `JWT_REFRESH_TTL=7d` |
| `JWT_SECRET=your_jwt_secret_here` | 강도 무강제, admin 공유 | min 64, 플레이스홀더 부팅 거부, admin은 audience 분리 |
| (없음) | refresh pepper / AI HMAC / CORS allowlist / Sentry / presigned TTL / GET host allowlist 누락 | §16.1 키 추가 |
| `AWS_REGION=us-east-1` | infra 서울 정책 위반(데이터 거주성/PIPA) | `ap-northeast-2` |
| `S3_BUCKET_NAME=helpbee-images` | env별 미분리 | `S3_IMAGES_BUCKET=helpbee-images-staging`/`-prod` |
| `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` | 장기키 슬롯(P0 root 키 사고) | 슬롯 제거, 로컬=SSO/aws-vault, 배포=task role(§13.1) |
| `SMTP_PASSWORD=...` 평문 | 평문 시크릿 | SES IAM/Secrets Manager |

> 결정 가드: 환경변수 키 네이밍을 한 번에 통일하고 `config/env.ts`가 fallback을 두지 말 것(typo 은폐 방지). 두 키 동시 지원 금지.

---

## 17. 열어둔 결정 · 기본값 (2부)

아래는 MVP 출시를 차단하지 않으나 베타 전/Phase 2에 확정해야 하는 항목. 각 항목에 **현재 기본값(default)** 을 둬 미결정 상태에서도 동작 가능하게 한다.

1. **차단 컬럼 위치** — `users.blocked_at` 추가는 DB 도메인 PR로 위임(§12.5). default: blocked_at 컬럼 + `sessions_valid_after` 마커(MUST). 컬럼 마이그레이션 전까지 임시로 마커-only 운영 금지(완전 차단 보장 위해 컬럼 우선).
2. **audit_log 보존기간/파티셔닝** — default 보존 180일, 월 파티셔닝·정리 cron은 1M row 도달 전 확정(§14.3, schema 주석 미정과 동일).
3. **무료 quota 월 경계** — 확정: KST(`YYYYMM-KST`). UTC 혼용 금지(1부 미해결 → KST로 확정).
4. **OpenAI 폴백 cap 값** — `OPENAI_FALLBACK_MONTHLY_CAP` 운영값 미정, default 0(미설정 시 폴백 보수적 비활성 권장) — 베타 트래픽 측정 후 산정(§13 API4).
5. **이메일 인증 발송/콜백·비밀번호 재설정** — 별도 섹션(§8 비범위). default: 미구현 상태에서 `email_verified_at` 게이트가 분석을 차단(미인증 사용자는 진단 불가) → 발송 흐름이 출시 전제. 베타 전 구현 필수.
6. **consent 저장 위치** — `consents` 전용 테이블 vs `audit_log action='consent.granted'`(§13.4 SHOULD). default: MVP는 audit_log, Phase 2에 전용 테이블 승급.
7. **사진 파기 cron / 삭제 SLA** — default 30일 SLA, 비식별 통계 파이프라인 분리(§13.4 MUST) — cron 구현은 베타 전.
8. **jwt-simple → jose 교체** — default: MVP는 jwt-simple 유지하되 **alg 핀 강제(MUST)**, jose는 Phase 2(RS256·키 회전과 함께).
9. **mTLS (api↔ai)** — default: MVP는 사설 서브넷+SG+단기 HMAC(1부 D10). mTLS는 Phase 2 승급.
10. **RDS Multi-AZ / GPU 추론 분리** — Phase 2(`infra` 정합). default: 단일 AZ + CPU ONNX.
11. **nice-to-have(추후)**: refresh token-family 정식 모델링, CAPTCHA, audit 이벤트 샘플링 비율 튜닝, presigned GET DNS rebinding 방어 강화(IP 재검증 캐시), Sentry 트레이싱(APM/OpenTelemetry → Grafana Tempo).

---

### ✅ 2부 후속 결정 확정 (사용자 4건 — 본 문서 전반에 우선 적용)

1. **무료 쿼터 = reserve-then-refund** *(확정, 1부 결정#2 대체)*: 추론 직전 원자 `INCR quota:{userId}:{YYYYMM-KST}` 예약 → 반환값 > 4면 `QUOTA_EXCEEDED`(402), success면 확정, **실패면 DECR 환불**, 멱등 short-circuit만 무차감. Redis 장애 시 fail-closed → TOCTOU 경합 차단. (1부 §2-③·D4 동기화 완료)
2. **무료 quota = 이메일 검증 후 활성** *(확정)*: `email_verified_at` 전에는 무료 quota 0 → 계정 양산·argon2 DoS 인센티브 제거. (§8.8 게이트를 quota 부여 시점으로 강화. §17-5 이메일 발송 흐름이 출시 전제)
3. **유료 OpenAI 폴백 = 사용자별 일 5회 cap** *(확정, §17-4의 default 0 대체)*: 초과 시 YOLO 결과만 graceful 반환. api 정책 계층이 `AI_BUDGET_EXCEEDED`로 글로벌 예산초과 식별 → 전면 YOLO 강등 + Slack 알림 (개인 일 cap + 글로벌 월예산 가드 이중화).
4. **admin JWT = 별도 audience/시크릿 분리** *(확정)*: admin 토큰은 api 사용자 토큰과 다른 `aud`·시크릿으로 스코프 → 일반 사용자 토큰으로 admin 접근 불가, blast radius 축소. (apps/admin/CLAUDE.md의 "동일 시크릿 공유" 가정은 본 결정으로 **정정** — 시크릿 2개, 둘 다 Secrets Manager)

> 본 2부는 1부 확정 결정과 정합하며, §13의 MUST는 본문에 모두 반영, SHOULD는 본문 반영 + 표기, nice-to-have는 본 §17에 격리했다. P0(§13.1 AWS root 키·gitleaks)는 설계 검토와 무관하게 **즉시** 처리해야 하는 운영 게이트다.
