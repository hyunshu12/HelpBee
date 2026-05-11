/**
 * 마이그레이션 러너 (tsx로 실행).
 * `pnpm --filter @helpbee/database migrate` 호출 시 진입점.
 *
 * 동작:
 *   1. DATABASE_URL 연결
 *   2. ./migrations 폴더의 모든 SQL 순차 적용
 *   3. drizzle_migrations 메타 테이블에 기록 (재실행 시 idempotent)
 */
import { drizzle } from 'drizzle-orm/postgres-js';
import { migrate } from 'drizzle-orm/postgres-js/migrator';
import postgres from 'postgres';

const DEFAULT_URL = 'postgresql://helpbee_user:helpbee_password@localhost:5432/helpbee';

async function main(): Promise<void> {
  const url = process.env.DATABASE_URL ?? DEFAULT_URL;
  console.log(`[migrate] connecting to ${url.replace(/:[^@:]+@/, ':***@')}`);

  const migrationClient = postgres(url, { max: 1 });
  const db = drizzle(migrationClient);

  try {
    await migrate(db, { migrationsFolder: './migrations' });
    console.log('[migrate] done');
  } finally {
    await migrationClient.end({ timeout: 5 });
  }
}

main().catch((err) => {
  console.error('[migrate] failed', err);
  process.exit(1);
});
