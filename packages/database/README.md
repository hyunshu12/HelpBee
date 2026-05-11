# @helpbee/database

HelpBee 데이터 영속 계층의 단일 진입점. PostgreSQL 16 + Drizzle ORM(TypeScript).

상세한 아키텍처 / 컨벤션은 [CLAUDE.md](./CLAUDE.md)를 읽으세요.

---

## 빠른 시작

```bash
# 1. 인프라 기동 (모노레포 루트에서)
docker compose up -d postgres

# 2. 마이그레이션 적용
pnpm --filter @helpbee/database migrate

# 3. 개발용 시드 (idempotent)
pnpm --filter @helpbee/database seed:dev

# 4. (선택) 시각 검증
pnpm --filter @helpbee/database studio
# → http://local.drizzle.studio
```

## 환경 변수

```
DATABASE_URL=postgresql://helpbee_user:helpbee_password@localhost:5432/helpbee
```

`docker-compose.yml`의 기본값과 일치. production은 AWS Secrets Manager에서 주입.

## 사용 (downstream)

```ts
import { db, schema, queries } from '@helpbee/database';

const hives = await queries.hives.listHivesByUser(db, userId);
await db.insert(schema.users).values({ ... });
```

⚠️ downstream 패키지(`apps/api`, `apps/admin`, `apps/ai`)는 반드시 이 패키지의 export만
사용한다. 직접 `pg`/`postgres` 인스턴스 생성 금지.

## 시드 비밀번호 — DEV ONLY

`pnpm --filter @helpbee/database seed:dev` 가 생성하는 모든 dev 계정의 비밀번호는:

```
helpbee-dev-2026
```

| 이메일 | role |
|---|---|
| `admin@helpbee.local` | admin |
| `beekeeper1@helpbee.local` | user |
| `beekeeper2@helpbee.local` | user |

⚠️ **production에서 절대 사용 금지.** production seed는 `seeds/prod.ts` (별도 PR)로
분리하고 비밀번호는 Secrets Manager에서 1회성으로 주입한다.

## 명령어

| 명령 | 동작 |
|---|---|
| `pnpm --filter @helpbee/database generate` | 스키마 변경 → SQL 마이그레이션 생성 |
| `pnpm --filter @helpbee/database migrate` | 마이그레이션 적용 (idempotent) |
| `pnpm --filter @helpbee/database check` | 스키마 ↔ 마이그레이션 drift 확인 |
| `pnpm --filter @helpbee/database studio` | 시각 대시보드 |
| `pnpm --filter @helpbee/database seed:dev` | 개발용 시드 (재실행 OK) |
| `pnpm --filter @helpbee/database type-check` | `tsc --noEmit` |

## 폴더 구조

```
packages/database/
├── CLAUDE.md                    # 작업 가이드 (cold-pickup 필독)
├── README.md                    # 이 파일
├── package.json
├── tsconfig.json
├── drizzle.config.ts
├── src/
│   ├── index.ts                 # public re-export 진입점
│   ├── client.ts                # postgres-js + drizzle 싱글톤
│   ├── migrate.ts               # 마이그레이션 러너 (tsx 실행)
│   ├── schema/
│   │   ├── _shared.ts           # timestamps / softDelete mixin
│   │   ├── users.ts             # users (soft delete)
│   │   ├── refreshTokens.ts     # refresh_tokens
│   │   ├── hives.ts             # hives (soft delete)
│   │   ├── analysisImages.ts    # analysis_images
│   │   ├── aiModels.ts          # ai_models (UNIQUE provider+name+version)
│   │   ├── analyses.ts          # analyses (UNIQUE image_id+model_id ← dual-engine)
│   │   ├── recommendations.ts   # recommendations
│   │   ├── subscriptions.ts     # subscriptions (user_id UNIQUE)
│   │   ├── auditLog.ts          # audit_log (bigserial PK)
│   │   └── index.ts             # 배럴
│   ├── queries/
│   │   ├── hives.ts             # listHivesByUser, getHiveByIdForUser, getHiveTrend
│   │   ├── analyses.ts          # createDualAnalysis, listAnalysesByHive
│   │   └── index.ts             # 배럴
│   └── seeds/
│       └── dev.ts               # 개발용 시드
└── migrations/
    ├── 0000_free_lady_ursula.sql  # 초기 9-테이블 + CHECK + 트리거
    └── meta/                       # drizzle-kit journal
```

## 알려진 제약 (현재 버전)

1. **CHECK 제약은 마이그레이션 SQL에서 직접 정의** — drizzle-kit 0.20.x가
   `check()` 호출을 SQL로 emit하지 않음. 다음 메이저 마이그레이션에 0.22+로 올리면 자동화 가능.
2. **`updated_at` 자동 갱신은 SQL 트리거** — drizzle-orm 0.29.5는 `.$onUpdate` 미지원.
   0.30+ 마이그레이션 시 트리거 제거 + Drizzle 헬퍼로 교체 가능.
3. **email lower-unique 인덱스도 SQL 직접 정의** — drizzle 0.29.5의 `.on(sql\`...\`)` 타입 한계.
   citext extension이 가용한 환경에서는 후속 마이그레이션으로 citext로 단순화 가능.

이 제약들은 모두 [migrations/0000_free_lady_ursula.sql](./migrations/0000_free_lady_ursula.sql) 하단에 주석으로 명시되어 있다.

## 참조

- [CLAUDE.md](./CLAUDE.md) — 권위 작업 가이드
- 구현 기록: [docs/05-implementation/2026-05-11-database-schema.md](../../docs/05-implementation/2026-05-11-database-schema.md)
- 루트 [README_MONOREPO.md](../../README_MONOREPO.md) — 모노레포 빠른 시작
