import { and, eq, isNull } from 'drizzle-orm';

import type { Database } from '../client';
import { type Subscription, subscriptions } from '../schema/subscriptions';
import { type User, users } from '../schema/users';

/** 사용자 조회 (soft delete 제외). 이메일 검증/role 게이트에 사용. */
export async function getUserById(db: Database, userId: string): Promise<User | undefined> {
  const rows = await db
    .select()
    .from(users)
    .where(and(eq(users.id, userId), isNull(users.deletedAt)))
    .limit(1);
  return rows[0];
}

/**
 * 이메일 인증 완료 마킹 (P1-4). email_verified_at=now().
 * WHERE email_verified_at IS NULL → idempotent(재검증 시 최초 타임스탬프 보존). soft-deleted 제외.
 */
export async function markEmailVerified(db: Database, userId: string): Promise<void> {
  await db
    .update(users)
    .set({ emailVerifiedAt: new Date() })
    .where(and(eq(users.id, userId), isNull(users.deletedAt), isNull(users.emailVerifiedAt)));
}

/** 사용자 구독 (user_id UNIQUE). plan 게이트(무료=YOLO/유료=폴백)에 사용. */
export async function getSubscriptionForUser(
  db: Database,
  userId: string,
): Promise<Subscription | undefined> {
  const rows = await db
    .select()
    .from(subscriptions)
    .where(eq(subscriptions.userId, userId))
    .limit(1);
  return rows[0];
}
