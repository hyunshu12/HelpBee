# @helpbee/database — Database & Schema Domain

이 문서는 Claude(또는 다른 개발자)가 이 패키지를 cold-start로 이어 작업할 수 있도록 작성된 작업 가이드다. PR을 올리기 전에 마지막 섹션의 체크리스트를 반드시 통과시킬 것.

---

## 1. 목적

`@helpbee/database`는 HelpBee MVP의 **데이터 영속 계층** 단일 진입점이다. PostgreSQL 16 + Drizzle ORM(TypeScript)으로 스키마, 마이그레이션, 시드, 자주 쓰는 쿼리 헬퍼를 제공한다. Backend API(`apps/api`), AI 서비스(`apps/ai`), 어드민(`apps/admin`)이 모두 이 패키지를 통해서만 DB에 접근한다. 베타 단계(2026년 7~8월)에 OpenAI Vision과 자체 YOLO 결과를 동시에 비교 가능한 **dual-engine schema**를 제공하는 것이 핵심 책임이다.

---

## 2. 폴더 구조

앞으로 만들 파일까지 포함한 최종 형태:

```
packages/database/
├── CLAUDE.md                 # 이 문서
├── package.json              # @helpbee/database, drizzle-kit/drizzle-orm/postgres deps
├── drizzle.config.ts         # drizzle-kit 설정 (이미 존재)
├── src/
│   ├── index.ts              # public re-export 진입점 (이미 존재, 확장 예정)
│   ├── client.ts             # postgres-js Client + drizzle() 인스턴스 생성
│   ├── schema/
│   │   ├── index.ts          # 모든 테이블 namespace 재수출
│   │   ├── enums.ts          # pgEnum 또는 text+check 정의
│   │   ├── users.ts          # users 테이블
│   │   ├── refreshTokens.ts  # refresh_tokens 테이블
│   │   ├── hives.ts          # hives 테이블
│   │   ├── analysisImages.ts # analysis_images 테이블
│   │   ├── aiModels.ts       # ai_models 테이블
│   │   ├── analyses.ts       # analyses 테이블 (dual-engine UNIQUE 제약)
│   │   ├── recommendations.ts# recommendations 테이블
│   │   ├── subscriptions.ts  # subscriptions 테이블
│   │   └── auditLog.ts       # audit_log 테이블 (bigserial PK)
│   ├── queries/
│   │   ├── hives.ts          # listHivesByUser, getHiveTrend
│   │   └── analyses.ts       # createDualAnalysis 등
│   └── seeds/
│       └── dev.ts            # 개발용 시드 스크립트 (tsx로 실행)
└── migrations/
    └── NNNN_snake_case.sql   # drizzle-kit generate 산출물 (git 커밋)
```

`.gitkeep`은 빈 디렉터리 추적용이며, 각 폴더에 첫 실제 파일이 생기면 같은 PR에서 제거할 것.

---

## 3. 개발 방식

### 3.1 ORM / DB 선택 이유
- **PostgreSQL 16**: jsonb, generated columns, citext, gen_random_uuid() 지원. AWS RDS / docker-compose 모두 동일 메이저 버전.
- **Drizzle ORM**: TypeScript first, SQL-like API, 추론 타입(`InferSelectModel` / `InferInsertModel`)으로 `packages/types`와 자연스럽게 동기화. Prisma 대비 마이그레이션이 투명하고 번들 가볍다.
- 드라이버는 `postgres` (postgres-js). `pg`보다 빠르고 prepared statement 호환.

### 3.2 Schema 파일 분리 원칙
- **테이블당 1파일** (`src/schema/{tableName}.ts`). join 대상도 같은 디렉터리 내에서 import.
- `enums.ts`에 enum/check 제약을 모아두고 각 테이블이 import.
- `schema/index.ts`는 단순 배럴 — 모든 테이블/enum/relation을 하나의 namespace로 export.
- 테이블명 카멀케이스 파일명, 실제 PG 테이블은 snake_case (`analysisImages.ts` → `analysis_images`).

### 3.3 마이그레이션 정책
- `pnpm --filter @helpbee/database drizzle-kit generate` 으로 SQL 파일 생성 → **반드시 git에 커밋**.
- 파일명 규칙: drizzle-kit 기본 (`NNNN_snake_case.sql`). 직접 수정 금지.
- **Forward-only**: 한 번 머지된 마이그레이션은 절대 수정/삭제 금지. 문제 발생 시 보정용 새 마이그레이션을 추가.
- Production 적용은 `drizzle-kit migrate` (CD에서 실행). 로컬은 `migrate` 또는 `push` 둘 다 허용 (단, push는 커밋 직전 generate로 normalize).
- CI에 `drizzle-kit check`로 schema ↔ 마이그레이션 drift 감지.

### 3.4 PK 규약
- 거의 모든 테이블: `id uuid PRIMARY KEY DEFAULT gen_random_uuid()`.
- 유일한 예외: `audit_log.id bigserial PRIMARY KEY` (시간 정렬 + 대량 삽입 비용 절감).
- FK는 항상 `references(() => ...).onDelete('cascade')` 또는 `'restrict'` 명시. `set null`은 nullable FK에만.

### 3.5 Soft Delete
- `users`, `hives`만 `deleted_at timestamptz`를 가진다. 쿼리 헬퍼에서 기본 필터 적용.
- `analyses`, `analysis_images`, `audit_log` 등 분석/감사 데이터는 **hard 보존** (법적/통계 추적 목적).
- soft delete된 user의 hives는 함께 마스킹하지만 row는 유지.

### 3.6 Timestamps
- 모든 테이블에 `created_at timestamptz NOT NULL DEFAULT now()` + `updated_at timestamptz NOT NULL DEFAULT now()`.
- Drizzle helper로 공통 mixin 정의:
  - `created_at`: `.defaultNow()`
  - `updated_at`: `.defaultNow().$onUpdate(() => new Date())`
- 시간은 항상 timestamptz (UTC 저장, 클라이언트에서 KST 변환).

### 3.7 Dual-engine 패턴
- `ai_models` 테이블에 (`openai`, `gpt-4o-mini`, `2024-07-18`) / (`yolo`, `helpbee-yolov8s`, `0.1.0`) 두 row.
- `analyses.model_id` FK + **`UNIQUE(image_id, model_id)`** 제약 → 같은 이미지에 OpenAI 결과와 YOLO 결과를 각각 row 1개씩 저장.
- nullable FK 없이 두 엔진 결과 공존 가능. 비교 쿼리는 self-join 또는 `GROUP BY image_id` 패턴.
- `engine` 컬럼은 두지 않는다 (정규화 위반). `ai_models.provider`로 식별.

---

## 4. 테이블 목록

| 테이블 | 한 줄 요약 |
|---|---|
| **users** | 이메일/비밀번호 해시 인증 사용자. soft delete 대상. |
| **refresh_tokens** | JWT refresh 회전 + 재사용 감지용 해시 저장소. |
| **hives** | 사용자별 벌통 (위치, 메모, 설치일). soft delete 대상. |
| **analysis_images** | S3 storage_url 메타 (mime, 크기, checksum, 촬영 시각). |
| **ai_models** | provider(openai|yolo) + name + version. UNIQUE(provider, name, version). |
| **analyses** | 분석 결과 (risk 0-100, tier, jsonb raw, latency). UNIQUE(image_id, model_id). |
| **recommendations** | analysis_id에 종속된 권장 조치 (i18n/검색을 위해 분리 테이블). |
| **subscriptions** | user_id UNIQUE, plan(free|basic|pro), trial_ends_at. |
| **audit_log** | bigserial PK. actor_id/action/entity/entity_id/jsonb metadata. (entity, entity_id) 인덱스. |

자세한 컬럼 정의는 `~/.claude/plans/refactored-percolating-church.md`의 `### 1. Database & Schema → 테이블 설계` 섹션 참조.

---

## 5. Export 인터페이스

다른 패키지/앱이 의존하는 public surface — 이 형태를 변경하면 downstream 빌드가 깨지므로 신중히.

```ts
// packages/database/src/index.ts
export { db } from './client';                      // drizzle 인스턴스 (싱글톤)
export * as schema from './schema';                 // namespace import 용
export * as queries from './queries';               // 헬퍼 함수 모음
export type {
  User, NewUser,
  Hive, NewHive,
  AnalysisImage, NewAnalysisImage,
  AiModel, NewAiModel,
  Analysis, NewAnalysis,
  Recommendation, NewRecommendation,
  Subscription, NewSubscription,
  AuditLog, NewAuditLog,
} from './schema';                                  // Drizzle 추론 타입
```

소비자 사용 예:
```ts
import { db, schema, queries } from '@helpbee/database';
const hives = await queries.hives.listHivesByUser(db, userId);
await db.insert(schema.analyses).values({ ... });
```

`packages/types`의 도메인 모델과 컬럼/필드명을 **반드시 일치**시킬 것 (PR 체크리스트 참고).

---

## 6. 로컬 개발

### 6.1 인프라 기동
```bash
# 모노레포 루트에서
docker compose up -d postgres
# (필요시) docker compose logs -f postgres
```
`docker-compose.yml`이 Postgres 16 + Redis 7을 띄운다. 기본 DB: `helpbee_dev`, user: `helpbee`, password: `helpbee`. 정확한 값은 `.env.local` / `docker-compose.yml` 참조.

### 6.2 마이그레이션 / 스튜디오
```bash
# 스키마 변경 후 SQL 생성
pnpm --filter @helpbee/database drizzle-kit generate

# 로컬 DB에 적용
pnpm --filter @helpbee/database drizzle-kit migrate

# 시각 검증 (브라우저 대시보드)
pnpm --filter @helpbee/database drizzle-kit studio
```

### 6.3 시드
```bash
pnpm --filter @helpbee/database tsx src/seeds/dev.ts
```
시드는 idempotent해야 한다 — 재실행 시 ON CONFLICT 처리. 내용:
- admin 1명, user 2명 (이메일/비밀번호 해시 포함, 비밀번호는 README 또는 시드 스크립트 상단 주석에 명시)
- 유저당 벌통 2~3개
- `ai_models` 2 row (openai, yolo)
- 동일 이미지에 dual analysis 5세트
- 분석당 recommendations 1~3개
- free subscription auto-row

### 6.4 환경 변수
- `DATABASE_URL=postgres://helpbee:helpbee@localhost:5432/helpbee_dev`
- `drizzle.config.ts`가 이 변수를 읽는다. `.env`는 git ignored.

---

## 7. 검증

PR 머지 전 다음을 통과해야 한다:

1. **drizzle-kit studio**로 9개 테이블이 모두 보이고 FK 라인이 정상 연결.
2. `scripts/check-schema.ts` (모노레포 루트)가 다음 흐름을 PASS:
   - user 생성 → hive 생성 → image 생성 → analyses 2 row(openai+yolo, 같은 image_id) 생성 → 트렌드 쿼리 결과 확인 → user soft delete → hive 함께 숨김 처리 확인.
3. `pnpm --filter @helpbee/database drizzle-kit check` — drift 없음.
4. 새 마이그레이션 SQL 파일이 PR diff에 포함됨 (수동 작성 금지, `generate` 산출물).

---

## 8. AI 작업 가이드라인 (Claude가 이 폴더에서 일할 때)

### 8.1 새 테이블 추가
1. `src/schema/{name}.ts` 파일 1개 생성 (테이블당 1파일, 다른 테이블 정의와 섞지 말 것).
2. `src/schema/index.ts`에 re-export 한 줄 추가.
3. 필요하면 `src/queries/{name}.ts` 생성하고 헬퍼 함수 추가.
4. `pnpm --filter @helpbee/database drizzle-kit generate`로 마이그레이션 생성, 산출물 그대로 커밋.
5. `packages/types`에 대응 타입이 있다면 동기화 (또는 추론 타입 re-export로 위임).

### 8.2 컬럼/제약 변경
- **이미 머지된 마이그레이션 SQL 파일은 절대 수정하지 말 것.** drizzle-kit이 새 파일(`NNNN`)을 만들도록 schema TS만 고치고 `generate` 재실행.
- `DROP COLUMN` / `DROP TABLE`이 필요하면 사전에 데이터 보존 계획(백업, 마이그레이션 데이터 이관)을 PR 설명에 명시.

### 8.3 파일 삭제 / 정리
- `rm` **사용 금지** (전역 hook이 차단). 항상 `trash <path>` 사용.
- `git reset --hard`, `git push --force`, `git clean -f`, `git checkout .`, `git branch -D` 모두 hook이 차단함. 작업 중 실수로 호출하지 않도록 주의.

### 8.4 packages/types 동기화 의무
- DB schema가 사실상 도메인 진실의 원천. `packages/types`의 `User`, `Hive`, `AnalysisResult`, `Subscription`, `Report`와 컬럼명/타입이 어긋나면 PR을 머지하지 말 것.
- 가능하면 `packages/types`가 `@helpbee/database`의 추론 타입을 재수출하는 방향으로 정리 (중복 정의 금지).

### 8.5 의사결정 가드
- citext extension을 못 쓰는 환경에서는 `email`을 `text`로 두고 `lower(email)` UNIQUE 인덱스로 대체.
- `overall_health`는 PG enum 대신 `text + CHECK (overall_health IN ('healthy','warning','critical'))` 권장 (마이그레이션 유연성).
- `audit_log` 보존 기간 / 파티셔닝은 미정 — 1M row 도달 전 결정.

### 8.6 보안
- 시드 비밀번호는 개발 전용. production 시드는 별도 (`seeds/prod.ts`)로 분리하고 secret은 Secrets Manager에서 주입.
- `raw_response jsonb`에 OpenAI raw payload를 저장할 때 **PII / 위치정보(EXIF)는 사전 제거**된 상태여야 함 (apps/api 책임이지만 schema 수준에서 컬럼 코멘트로 명시).

---

## 9. PR 체크리스트

PR을 열기 전에 다음을 모두 확인할 것:

- [ ] `pnpm --filter @helpbee/database drizzle-kit generate` 산출 SQL이 diff에 포함됨
- [ ] `pnpm --filter @helpbee/database drizzle-kit check`가 clean
- [ ] `pnpm --filter @helpbee/database tsx src/seeds/dev.ts`가 깨끗한 DB / 재실행 모두 성공
- [ ] `drizzle-kit studio`에서 신규/변경 테이블 시각 확인
- [ ] `scripts/check-schema.ts` (있다면) 통과
- [ ] `packages/types`와 도메인 모델 필드명/타입 정합 확인
- [ ] 새 테이블에 `created_at`/`updated_at` 누락 없음 (audit_log는 created_at만)
- [ ] FK에 `onDelete` 동작 명시
- [ ] soft delete 정책 위반 없음 (users/hives 외에 `deleted_at` 추가 금지)
- [ ] dual-engine 영향 있는 변경이면 `UNIQUE(image_id, model_id)` 제약이 살아있음
- [ ] CLAUDE.md 폴더 구조 / 테이블 목록 / 인터페이스 섹션이 변경 사항과 일치하도록 업데이트
- [ ] `rm` / `git reset --hard` 등 차단된 명령을 사용하지 않았음

---

## 10. 참고

- 전체 분야 마스터 플랜: `~/.claude/plans/refactored-percolating-church.md`
- Backend 인터페이스: `apps/api/src/services/*` 가 이 패키지의 export만 import할 것 (직접 SQL 금지)
- AI 서비스 인터페이스: `apps/ai`는 분석 완료 시 API를 통해 row 2개(openai/yolo) insert 트리거 — 직접 DB 접근 금지
- 마일스톤: May W1~W4 + Jun W1 (마스터 플랜 분야 1 참조)
