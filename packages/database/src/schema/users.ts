import { sql } from 'drizzle-orm';
import { pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

import { softDelete, timestamps } from './_shared';

/**
 * 인증 사용자.
 * - email: case-insensitive UNIQUE는 lower(email) partial unique index로 보장.
 *   인덱스는 drizzle 0.29.5의 .on(sql`...`) 타입 한계로 마이그레이션 SQL에서 직접 정의함.
 *   (0001_init.sql: CREATE UNIQUE INDEX ... ON "users" (lower("email")))
 *   citext extension이 가용한 환경에서는 후속 마이그레이션으로 citext 교체 가능.
 * - role: 'user' | 'admin' (CHECK 제약은 마이그레이션 SQL에서 추가)
 * - soft delete 대상 (deleted_at)
 */
export const users = pgTable('users', {
  id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
  email: text('email').notNull(),
  passwordHash: text('password_hash').notNull(),
  name: text('name').notNull(),
  role: text('role').notNull().default('user'),
  emailVerifiedAt: timestamp('email_verified_at', { withTimezone: true }),
  ...timestamps,
  ...softDelete,
});

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
