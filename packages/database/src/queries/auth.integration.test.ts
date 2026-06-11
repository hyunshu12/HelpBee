/**
 * Auth 쿼리 헬퍼 실 DB 통합테스트 (backend-design §8.9).
 * 실행(opt-in): DB_ITEST=1 DATABASE_URL=... pnpm --filter @helpbee/database test:integration
 * ⚠️ DB_ITEST 미설정 시 전체 스킵(CI/`turbo run test`에서 깨지지 않게).
 * 검증: 가입(user+subscription tx)·이메일 UNIQUE·차단/탈퇴 필터·refresh 회전 primitive.
 */
import { eq, sql } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { db, queries, schema } from '../index';

const RUN = process.env.DB_ITEST === '1';

describe.skipIf(!RUN)('Auth queries (real PostgreSQL)', () => {
  beforeAll(async () => {
    // 이 스위트 전용 데이터만 정리(다른 통합테스트 데이터 보존 위해 이메일 prefix로 한정)
    await db.delete(schema.users).where(sql`email LIKE 'authq-%@itest.local'`);
  });

  afterAll(async () => {
    await db.delete(schema.users).where(sql`email LIKE 'authq-%@itest.local'`);
    await (db as unknown as { $client?: { end?: () => Promise<void> } }).$client?.end?.();
  });

  it('createUserWithSubscription: user + subscription(free/active) tx', async () => {
    const user = await queries.auth.createUserWithSubscription(db, {
      email: 'authq-a@itest.local',
      name: 'A',
      passwordHash: '$argon2id$x',
    });
    expect(user.role).toBe('user');
    expect(user.emailVerifiedAt).toBeNull();
    const sub = await queries.accounts.getSubscriptionForUser(db, user.id);
    expect(sub?.plan).toBe('free');
    expect(sub?.status).toBe('active');
  });

  it('이메일 UNIQUE(lower): 대소문자 다른 중복 → 23505 throw', async () => {
    await queries.auth.createUserWithSubscription(db, {
      email: 'authq-dup@itest.local',
      name: 'D',
      passwordHash: '$argon2id$x',
    });
    let code: string | undefined;
    try {
      await queries.auth.createUserWithSubscription(db, {
        email: 'authq-dup@itest.local',
        name: 'D2',
        passwordHash: '$argon2id$y',
      });
    } catch (e) {
      code = (e as { code?: string }).code;
    }
    expect(code).toBe('23505');
  });

  it('getUserByEmailForAuth: 활성만(차단/탈퇴 제외)', async () => {
    const u = await queries.auth.createUserWithSubscription(db, {
      email: 'authq-filter@itest.local',
      name: 'F',
      passwordHash: '$argon2id$x',
    });
    expect(await queries.auth.getUserByEmailForAuth(db, 'authq-filter@itest.local')).toBeTruthy();

    // 차단 → 제외
    await db.update(schema.users).set({ blockedAt: new Date() }).where(eq(schema.users.id, u.id));
    expect(await queries.auth.getUserByEmailForAuth(db, 'authq-filter@itest.local')).toBeUndefined();
    expect(await queries.auth.getActiveUserById(db, u.id)).toBeUndefined();
  });

  it('refresh 회전 primitive: create→getByHash→revokeById(조건부)→재revoke 0', async () => {
    const u = await queries.auth.createUserWithSubscription(db, {
      email: 'authq-rt@itest.local',
      name: 'R',
      passwordHash: '$argon2id$x',
    });
    const row = await queries.auth.createRefreshToken(db, {
      userId: u.id,
      tokenHash: 'hash-rt-1',
      expiresAt: new Date(Date.now() + 86400_000),
    });
    expect((await queries.auth.getRefreshTokenByHash(db, 'hash-rt-1'))?.id).toBe(row.id);

    // 첫 revoke = 1(승자), 두번째 = 0(이미 revoked → race benign)
    expect(await queries.auth.revokeRefreshTokenById(db, row.id)).toBe(1);
    expect(await queries.auth.revokeRefreshTokenById(db, row.id)).toBe(0);
  });

  it('revokeAllRefreshTokensForUser: 활성만 일괄 폐기', async () => {
    const u = await queries.auth.createUserWithSubscription(db, {
      email: 'authq-all@itest.local',
      name: 'AL',
      passwordHash: '$argon2id$x',
    });
    for (const h of ['all-1', 'all-2', 'all-3']) {
      await queries.auth.createRefreshToken(db, {
        userId: u.id,
        tokenHash: h,
        expiresAt: new Date(Date.now() + 86400_000),
      });
    }
    await queries.auth.revokeRefreshTokenById(
      db,
      (await queries.auth.getRefreshTokenByHash(db, 'all-1'))!.id,
    );
    // 이미 1개 revoked → 남은 활성 2개만 폐기
    expect(await queries.auth.revokeAllRefreshTokensForUser(db, u.id)).toBe(2);
  });
});
