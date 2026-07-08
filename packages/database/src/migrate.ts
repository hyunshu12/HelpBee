/**
 * 마이그레이션 러너 (tsx로 실행).
 * `pnpm --filter @helpbee/database migrate` 호출 시 진입점.
 *
 * 동작:
 *   1. DATABASE_URL 연결
 *   2. migrations 폴더의 모든 SQL 순차 적용
 *   3. drizzle_migrations 메타 테이블에 기록 (재실행 시 idempotent)
 *
 * migrations 경로는 cwd 가 아니라 이 모듈 위치 기준으로 해석한다 — 컨테이너
 * (docker compose run api, WORKDIR /app/apps/api)처럼 다른 cwd 에서 실행해도
 * 동작해야 한다 (리뷰 발견: cwd 상대경로는 beta 배포에서 100% 실패).
 */
import { fileURLToPath } from 'node:url';

import { drizzle } from 'drizzle-orm/postgres-js';
import { migrate } from 'drizzle-orm/postgres-js/migrator';
import postgres from 'postgres';

const DEFAULT_URL = 'postgresql://helpbee_user:helpbee_password@localhost:5432/helpbee';
const MIGRATIONS_DIR = fileURLToPath(new URL('../migrations', import.meta.url));

async function main(): Promise<void> {
  const url = process.env.DATABASE_URL ?? DEFAULT_URL;
  console.log(`[migrate] connecting to ${url.replace(/:[^@:]+@/, ':***@')}`);

  const migrationClient = postgres(url, { max: 1 });
  const db = drizzle(migrationClient);

  try {
    await migrate(db, { migrationsFolder: MIGRATIONS_DIR });
    console.log('[migrate] done');
  } finally {
    await migrationClient.end({ timeout: 5 });
  }
}

main().catch((err) => {
  console.error('[migrate] failed', err);
  process.exit(1);
});
