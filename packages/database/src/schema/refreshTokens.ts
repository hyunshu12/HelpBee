import { sql } from 'drizzle-orm';
import { index, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

import { users } from './users';

/**
 * JWT refresh 토큰 해시 저장.
 * - token_hash: **HMAC-SHA256(server pepper)** 로 해시된 refresh token (raw token 저장 금지).
 *   결정적 해시라야 raw→row 조회·재사용 감지가 가능(argon2 같은 랜덤 솔트 해시 금지 — backend-design §8.0 MUST).
 *   비밀번호는 argon2id(별도 서비스). 두 해싱은 스왑 불가하게 분리.
 * - 회전(rotation) 시 revoked_at 마킹 + 새 row insert
 * - 재사용 감지 시 해당 user의 모든 row revoke + sessions_valid_after 마커 bump
 */
export const refreshTokens = pgTable(
  'refresh_tokens',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    tokenHash: text('token_hash').notNull().unique(),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    revokedAt: timestamp('revoked_at', { withTimezone: true }),
    userAgent: text('user_agent'),
    ip: text('ip'), // inet은 drizzle 0.28에서 직접 지원 안 함, text로 저장
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    userIdIdx: index('refresh_tokens_user_id_idx').on(t.userId),
  }),
);

export type RefreshToken = typeof refreshTokens.$inferSelect;
export type NewRefreshToken = typeof refreshTokens.$inferInsert;
