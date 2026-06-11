/**
 * Auth 쿼리 헬퍼 (backend-design §8.9). 직접 SQL 금지 — 라우트/서비스는 이 함수만 사용.
 * - 이메일은 lower(email) 비교(0000 lower(email) UNIQUE 인덱스 정합, 입력은 normalizeEmail 후).
 * - login/refresh/me는 deleted_at IS NULL + blocked_at IS NULL 필터(차단/탈퇴 즉시 거부).
 * - refresh 토큰은 회전/재사용 감지 primitive만 제공(오케스트레이션은 라우트).
 */
import { and, eq, isNull, sql } from 'drizzle-orm';

import type { Database } from '../client';
import { refreshTokens, type RefreshToken } from '../schema/refreshTokens';
import { subscriptions } from '../schema/subscriptions';
import { type User, users } from '../schema/users';

/** 로그인용 조회: lower(email) 일치 + 활성(삭제/차단 제외). 없으면 undefined. */
export async function getUserByEmailForAuth(
  db: Database,
  email: string,
): Promise<User | undefined> {
  const rows = await db
    .select()
    .from(users)
    .where(
      and(
        sql`lower(${users.email}) = ${email}`,
        isNull(users.deletedAt),
        isNull(users.blockedAt),
      ),
    )
    .limit(1);
  return rows[0];
}

/** /me 등 활성 사용자 조회(삭제/차단 제외). */
export async function getActiveUserById(db: Database, userId: string): Promise<User | undefined> {
  const rows = await db
    .select()
    .from(users)
    .where(and(eq(users.id, userId), isNull(users.deletedAt), isNull(users.blockedAt)))
    .limit(1);
  return rows[0];
}

/**
 * 신규 가입: users + subscriptions(free/active) 단일 트랜잭션 insert.
 * 이메일 충돌은 lower(email) UNIQUE 위반(23505)으로 throw → 라우트가 AUTH_EMAIL_TAKEN 매핑(TOCTOU 회피).
 * role은 항상 'user'(코드 결정 — Mass Assignment 차단), email_verified_at=NULL.
 */
export async function createUserWithSubscription(
  db: Database,
  input: { email: string; name: string; passwordHash: string },
): Promise<User> {
  return db.transaction(async (tx) => {
    const [user] = await tx
      .insert(users)
      .values({
        email: input.email,
        name: input.name,
        passwordHash: input.passwordHash,
        role: 'user',
      })
      .returning();
    await tx.insert(subscriptions).values({ userId: user!.id, plan: 'free', status: 'active' });
    return user!;
  });
}

export async function getRefreshTokenByHash(
  db: Database,
  tokenHash: string,
): Promise<RefreshToken | undefined> {
  const rows = await db
    .select()
    .from(refreshTokens)
    .where(eq(refreshTokens.tokenHash, tokenHash))
    .limit(1);
  return rows[0];
}

export async function createRefreshToken(
  db: Database,
  input: {
    userId: string;
    tokenHash: string;
    expiresAt: Date;
    userAgent?: string | null;
    ip?: string | null;
  },
): Promise<RefreshToken> {
  const [row] = await db
    .insert(refreshTokens)
    .values({
      userId: input.userId,
      tokenHash: input.tokenHash,
      expiresAt: input.expiresAt,
      userAgent: input.userAgent ?? null,
      ip: input.ip ?? null,
    })
    .returning();
  return row!;
}

/**
 * 단일 refresh 회전(승자만): WHERE id=? AND revoked_at IS NULL 조건부 revoke.
 * 반환 affected 수 — 0이면 이미 다른 동시요청이 회전(race) → 라우트가 benign 처리.
 */
export async function revokeRefreshTokenById(db: Database, id: string): Promise<number> {
  const rows = await db
    .update(refreshTokens)
    .set({ revokedAt: new Date() })
    .where(and(eq(refreshTokens.id, id), isNull(refreshTokens.revokedAt)))
    .returning({ id: refreshTokens.id });
  return rows.length;
}

/** 재사용 감지/차단 시 user의 모든 활성 refresh 일괄 revoke. 반환 revoke된 수. */
export async function revokeAllRefreshTokensForUser(
  db: Database,
  userId: string,
): Promise<number> {
  const rows = await db
    .update(refreshTokens)
    .set({ revokedAt: new Date() })
    .where(and(eq(refreshTokens.userId, userId), isNull(refreshTokens.revokedAt)))
    .returning({ id: refreshTokens.id });
  return rows.length;
}
