import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';

import * as schema from './schema';

const DEFAULT_URL = 'postgresql://helpbee_user:helpbee_password@localhost:5432/helpbee';

function getConnectionString(): string {
  const url = process.env.DATABASE_URL;
  if (url && url.length > 0) return url;
  if (process.env.NODE_ENV === 'production') {
    throw new Error('[database] DATABASE_URL is required in production');
  }
  // dev fallback — docker-compose 기본값
  return DEFAULT_URL;
}

const globalForClient = globalThis as unknown as {
  __helpbeeSql?: ReturnType<typeof postgres>;
};

/**
 * postgres-js 클라이언트 싱글톤.
 * Next.js dev hot-reload 환경에서 connection 누수 방지를 위해 globalThis에 캐시.
 */
function getSql(): ReturnType<typeof postgres> {
  if (!globalForClient.__helpbeeSql) {
    globalForClient.__helpbeeSql = postgres(getConnectionString(), {
      max: Number(process.env.DATABASE_POOL_MAX ?? 10),
      idle_timeout: 20,
      connect_timeout: 10,
    });
  }
  return globalForClient.__helpbeeSql;
}

/**
 * Drizzle 인스턴스 (싱글톤).
 * 모든 패키지/앱은 이 `db`를 import해서 사용한다. 직접 SQL 호출 금지.
 *
 * 사용 예:
 *   import { db, schema } from '@helpbee/database';
 *   await db.select().from(schema.users);
 */
export const db = drizzle(getSql(), { schema });

export type Database = typeof db;
