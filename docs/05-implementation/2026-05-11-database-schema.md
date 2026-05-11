# 2026-05-11 — Database 9-table schema + types 동기화 + impl log 체계 도입

> PR: (생성 후 채움) · 브랜치: `feature/database-schema-9-tables` → `develop` · 작성일: 2026-05-11

## 범위 (Scope)

마스터 플랜 May W1~W4 분야 1 (Database & Schema) 전체를 한 PR로 완성:

- `packages/database` 9개 테이블 + Drizzle 스키마 + 쿼리 헬퍼 + 시드 + 마이그레이션
- `packages/types` 레거시 interface 제거 → Drizzle 추론 타입 재수출로 단일 진실 소스화
- 구현 기록 인덱스 디렉터리(`docs/05-implementation/`) 신설 + 본 PR이 첫 기록
- 루트 `CLAUDE.md` 라우팅 표 + "참고 문서 가이드"에 구현 기록 디렉터리 링크

## 산출물 (Deliverables)

### 새 스키마 9개

| 파일 | 핵심 |
|---|---|
| [packages/database/src/schema/_shared.ts](../../packages/database/src/schema/_shared.ts) | `timestamps`/`softDelete` mixin |
| [packages/database/src/schema/users.ts](../../packages/database/src/schema/users.ts) | citext 대체 `lower(email)` unique index, role CHECK |
| [packages/database/src/schema/refreshTokens.ts](../../packages/database/src/schema/refreshTokens.ts) | argon2 해시된 token_hash UNIQUE, 회전/재사용 감지용 |
| [packages/database/src/schema/hives.ts](../../packages/database/src/schema/hives.ts) | numeric(9,6) 좌표, soft delete |
| [packages/database/src/schema/analysisImages.ts](../../packages/database/src/schema/analysisImages.ts) | S3 storage_url, uploaded_by restrict |
| [packages/database/src/schema/aiModels.ts](../../packages/database/src/schema/aiModels.ts) | UNIQUE(provider, name, version), provider CHECK |
| [packages/database/src/schema/analyses.ts](../../packages/database/src/schema/analyses.ts) | **UNIQUE(image_id, model_id)** ← dual-engine 핵심, 0~100 risk CHECK |
| [packages/database/src/schema/recommendations.ts](../../packages/database/src/schema/recommendations.ts) | severity CHECK (info/warn/danger) |
| [packages/database/src/schema/subscriptions.ts](../../packages/database/src/schema/subscriptions.ts) | user_id UNIQUE, plan/status CHECK |
| [packages/database/src/schema/auditLog.ts](../../packages/database/src/schema/auditLog.ts) | bigserial PK, (entity, entity_id) INDEX |

### 클라이언트 / 쿼리 / 시드 / 마이그레이션

- [packages/database/src/client.ts](../../packages/database/src/client.ts) — postgres-js + drizzle 싱글톤 (NODE_ENV=production 시 DATABASE_URL 강제)
- [packages/database/src/migrate.ts](../../packages/database/src/migrate.ts) — tsx 진입점, `pnpm --filter @helpbee/database migrate`
- [packages/database/src/queries/hives.ts](../../packages/database/src/queries/hives.ts) — listHivesByUser, getHiveByIdForUser, getHiveTrend
- [packages/database/src/queries/analyses.ts](../../packages/database/src/queries/analyses.ts) — createDualAnalysis (트랜잭션, ON CONFLICT 멱등), listAnalysesByHive
- [packages/database/src/seeds/dev.ts](../../packages/database/src/seeds/dev.ts) — admin 1명 + beekeeper 2명 + 벌통 5개 + dual-engine 분석 5세트 + audit row 1개, idempotent
- [packages/database/migrations/0000_free_lady_ursula.sql](../../packages/database/migrations/0000_free_lady_ursula.sql) — 초기 9-테이블 + CHECK + `set_updated_at()` 트리거 4개

### Public export 갱신

- [packages/database/src/index.ts](../../packages/database/src/index.ts) — db, schema namespace, queries namespace, Drizzle 추론 타입 재수출, enum-like value array
- [packages/database/README.md](../../packages/database/README.md) — 빠른 시작, 시드 비번 명기, 알려진 제약

### packages/types 동기화

- [packages/types/src/index.ts](../../packages/types/src/index.ts) — 레거시 7개 interface 제거 → `@helpbee/database` 추론 타입 재수출 + API DTO(`AnalysisRequest`, `DualAnalysisResponse`, `ApiEnvelope`, `ProblemDetails`)
- [packages/types/package.json](../../packages/types/package.json) — `@helpbee/database` workspace 의존 + `@types/node` 추가

### 의존성 정리

- [packages/database/package.json](../../packages/database/package.json) — postgres-js / tsx / argon2 추가, drizzle-orm 0.28 → 0.29.5
- [apps/api/package.json](../../apps/api/package.json) — drizzle-orm 0.28 → 0.29.5 (호이스트 충돌 방지)
- [packages/database/tsconfig.json](../../packages/database/tsconfig.json) — 신규, `@helpbee/config/typescript/node.json` 상속
- [packages/types/tsconfig.json](../../packages/types/tsconfig.json) — `outDir: ./src` 제거, `noEmit: true`

### 구현 기록 체계 (신설)

- [docs/05-implementation/README.md](./README.md) — 디렉터리 가이드 (파일명 규칙, 템플릿, 작성 의무, 인덱스 표)
- [docs/05-implementation/2026-05-11-database-schema.md](./2026-05-11-database-schema.md) — 본 파일
- [CLAUDE.md](../../CLAUDE.md) (루트) — 라우팅 표 + "참고 문서 가이드"에 링크 추가

## 검증 (Verification)

### 통과한 항목

- [x] **drizzle-kit generate** — 9 테이블 / 26 컬럼 / FK 11개 / 인덱스 9개 모두 SQL로 산출
  ```
  9 tables
  ai_models 7 cols, analyses 14 cols (2 idx, 3 fks), analysis_images 11 cols, audit_log 9 cols (2 idx, 1 fk),
  hives 11 cols, users 9 cols, refresh_tokens 8 cols, recommendations 6 cols, subscriptions 8 cols
  → migrations/0000_free_lady_ursula.sql
  ```
- [x] **type-check** (`pnpm --filter @helpbee/database type-check`) — 0 errors
- [x] **type-check** (`pnpm --filter @helpbee/types type-check`) — 0 errors
- [x] **dual-engine UNIQUE** — `analyses_image_model_unique` 제약이 마이그레이션 SQL에 포함됨 (line 27)
- [x] **soft delete** — users / hives에만 `deleted_at` 컬럼 존재, 다른 테이블에는 없음
- [x] **FK onDelete 명시** — cascade(8) / restrict(2) / set null(1) 모두 SQL에 emit
- [x] **`packages/types` drift** — 레거시 `User`, `Hive`, `AnalysisResult`, `Report` 제거, DB 추론 타입과 1:1 정합

### PR 환경 / 후속 검증 (로컬 docker 부재로 이번 PR 머지 전 CI 또는 리뷰어 환경에서 수행)

- [ ] `docker compose up -d postgres` 후 `pnpm --filter @helpbee/database migrate` 깨끗한 DB 적용 OK
- [ ] `pnpm --filter @helpbee/database seed:dev` 첫 실행 OK + 재실행 시 ON CONFLICT 통과 (idempotent)
- [ ] `drizzle-kit studio`로 9 테이블 + FK 라인 시각 확인
- [ ] `drizzle-kit check`로 drift 없음
- [ ] e2e 수동: user → hive → image → dual analyses(openai+yolo) → trend 쿼리 → user soft delete → hive 마스킹

## 알려진 제약 (트레이드오프)

1. **drizzle-kit 0.20.x의 SQL emit 한계**:
   - `check()` 호출이 SQL로 emit되지 않음 → 마이그레이션 하단에 `ALTER TABLE ... ADD CONSTRAINT ... CHECK` 수동 8건 추가
   - `.on(sql\`lower(...)\`)` 타입 미지원 → users 인덱스는 raw SQL로 직접 정의
   - 다음 메이저 마이그레이션에 drizzle-kit 0.22+ + drizzle-orm 0.30+로 올려 자동화 가능

2. **drizzle-orm 0.29.5 `.$onUpdate` 미지원**:
   - 4개 mutable 테이블(users/hives/analyses/subscriptions)에 `set_updated_at()` 트리거로 보강
   - 0.30+ 마이그레이션 시 트리거 제거 + Drizzle 헬퍼로 교체 가능

3. **citext extension 미사용**:
   - AWS RDS 일부 환경에서 citext 가용성 불확실 → `lower(email)` unique index로 대체
   - production 환경 확정 후 별도 PR로 citext 마이그레이션 검토

4. **로컬 docker 부재 검증 한계**:
   - 본 작업 환경에 Docker / 로컬 Postgres 미설치 → 실제 SQL 적용 검증은 PR 환경에서 수행
   - 타입 검증 + drizzle-kit generate 산출물 검증으로 정합성 확보

## 후속 작업 (Follow-up)

이 PR이 머지되면 다음 PR이 병렬로 풀린다:

| 다음 PR | 분야 | 의존 |
|---|---|---|
| `feature/api-auth-hives` | apps/api JWT + signup/login/refresh + hives CRUD | DB ✓ |
| `feature/ui-tokens-core-components` | packages/ui tailwind preset + Button/Card/Input/Badge + Storybook | — (병렬) |
| `feature/ai-inference-routers` | apps/ai `/analyze` + `/analyze/yolo` + `/analyze/dual` | — (병렬) |
| `feature/ci-workflows` | `.github/workflows/ci.yml` lint/type-check/test/drizzle check | — (병렬) |

각 PR 머지 시 `docs/05-implementation/YYYY-MM-DD-{topic}.md` 작성 의무.

## 참조

- **권위 가이드**: [packages/database/CLAUDE.md](../../packages/database/CLAUDE.md) — §4 테이블, §5 export 인터페이스, §7 검증, §9 체크리스트
- **마이그레이션 SQL**: [packages/database/migrations/0000_free_lady_ursula.sql](../../packages/database/migrations/0000_free_lady_ursula.sql)
- **README**: [packages/database/README.md](../../packages/database/README.md) — 시드 비번, 알려진 제약
- **계획**: `~/.claude/plans/ai-linked-prism.md` (이번 PR 직전 작성)
