import { sql } from 'drizzle-orm';
import { pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core';

import { softDelete, timestamps } from './_shared';

/**
 * 인증 사용자.
 * - email: case-insensitive UNIQUE는 lower(email) partial unique index로 보장.
 *   인덱스는 drizzle 0.29.5의 .on(sql`...`) 타입 한계로 마이그레이션 SQL에서 직접 정의함.
 *   (0001_init.sql: CREATE UNIQUE INDEX ... ON "users" (lower("email")))
 *   citext extension이 가용한 환경에서는 후속 마이그레이션으로 citext 교체 가능.
 * - role: 'user' | 'admin' (CHECK 제약은 마이그레이션 SQL에서 추가)
 * - soft delete 대상 (deleted_at)
 * - blocked_at: 관리자 차단(§12.5). NULL=정상. 설정 시 login/refresh 거부 +
 *   sessions_valid_after 마커 bump로 기존 access 즉시 회수(backend-design §13 API2 MUST).
 *   status는 파생: deleted_at→'deleted' / blocked_at→'blocked' / else 'active'.
 */
export const users = pgTable(
  'users',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    email: text('email').notNull(),
    passwordHash: text('password_hash').notNull(),
    name: text('name').notNull(),
    role: text('role').notNull().default('user'),
    emailVerifiedAt: timestamp('email_verified_at', { withTimezone: true }),
    blockedAt: timestamp('blocked_at', { withTimezone: true }),
    ...timestamps,
    ...softDelete,
  },
  (t) => ({
    // case-insensitive 이메일 UNIQUE. 0000 스냅샷과 동일하게 schema에 표현해야
    // generate가 매번 DROP하려는 drift를 방지(이전 누락이 0001 DROP INDEX 사고 유발).
    // drizzle 0.29.5 `.on()`은 SQL 표현식 타입을 미지원 → 캐스트(runtime generate는 정상 처리).
    emailLowerUnique: uniqueIndex('users_email_lower_unique').on(sql`lower(${t.email})` as never),
  }),
);

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
