import { Hono } from 'hono';
import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../lib/error-codes';
import { errorHandler } from '../middleware/error-handler';
import { requestId } from '../middleware/request-id';
import { authRoutes, type AuthDeps, type UserRow } from './auth';

const NOW = 1_800_000_000_000;

function userFixture(over: Partial<UserRow> = {}): UserRow {
  return {
    id: 'u1',
    email: 'a@b.com',
    name: '홍길동',
    role: 'user',
    passwordHash: '$argon2id$hash',
    emailVerifiedAt: null,
    createdAt: new Date('2026-06-11T00:00:00Z'),
    ...over,
  };
}

function makeDeps(over: Partial<AuthDeps> = {}): AuthDeps {
  return {
    createUser: vi.fn(async (i) => userFixture({ id: 'new-user', email: i.email, name: i.name })),
    getUserByEmail: vi.fn(async () => userFixture()),
    getActiveUserById: vi.fn(async () => userFixture()),
    getSubscription: vi.fn(async () => ({ plan: 'free', status: 'active' })),
    getRefreshByHash: vi.fn(async () => undefined),
    createRefresh: vi.fn(async () => ({})),
    revokeRefreshById: vi.fn(async () => 1),
    revokeAllRefresh: vi.fn(async () => 3),
    hashPassword: vi.fn(async () => '$argon2id$newhash'),
    verifyPassword: vi.fn(async () => true),
    getDummyHash: vi.fn(async () => '$argon2id$dummy'),
    signAccess: vi.fn(() => 'access.jwt.token'),
    generateRefresh: vi.fn(() => 'raw-refresh-token'),
    hashRefresh: vi.fn((t) => `hash(${t})`),
    refreshExpiry: vi.fn(() => new Date(NOW + 7 * 86400_000)),
    assertNotLocked: vi.fn(async () => undefined),
    recordLoginFailure: vi.fn(async () => undefined),
    clearLoginFailures: vi.fn(async () => undefined),
    bumpSessions: vi.fn(async () => undefined),
    sendVerificationEmail: vi.fn(async () => undefined),
    verifyEmailToken: vi.fn(() => ({
      ok: true as const,
      payload: { sub: 'u1', em: 'a@b.com', exp: Math.floor(NOW / 1000) + 3600 },
    })),
    markEmailVerified: vi.fn(async () => undefined),
    audit: vi.fn(async () => undefined),
    now: vi.fn(() => NOW),
    ...over,
  };
}

/** authRoutes + 공통 미들웨어. /logout,/me는 requireAuth를 흉내내 userId 주입. */
function makeApp(deps: AuthDeps, authedUserId = 'u1') {
  const app = new Hono();
  app.onError(errorHandler);
  app.use('*', requestId);
  app.use('/logout', async (c, next) => {
    c.set('userId', authedUserId);
    await next();
  });
  app.use('/me', async (c, next) => {
    c.set('userId', authedUserId);
    await next();
  });
  app.use('/resend-verification', async (c, next) => {
    c.set('userId', authedUserId);
    await next();
  });
  app.route('/', authRoutes(deps));
  return app;
}

function post(app: Hono, path: string, body: unknown) {
  return app.request(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('POST /signup', () => {
  it('201 with tokens; PublicUser has no passwordHash; refreshToken is raw', async () => {
    const deps = makeDeps();
    const res = await post(makeApp(deps), '/signup', {
      email: 'New@Ex.com',
      password: '0123456789',
      name: 'n',
    });
    expect(res.status).toBe(201);
    const { data } = await res.json();
    expect(data.user.passwordHash).toBeUndefined();
    expect(data.user.email).toBe('new@ex.com'); // 정규화
    expect(data.refreshToken).toBe('raw-refresh-token'); // raw(해시 아님)
    expect(data.accessToken).toBe('access.jwt.token');
    expect(data.expiresIn).toBe(900);
    expect(deps.hashPassword).toHaveBeenCalledOnce();
  });

  it('409 AUTH_EMAIL_TAKEN on unique violation (23505)', async () => {
    const deps = makeDeps({
      createUser: vi.fn(async () => {
        throw Object.assign(new Error('dup'), { code: '23505' });
      }),
    });
    const res = await post(makeApp(deps), '/signup', {
      email: 'a@b.com',
      password: '0123456789',
      name: 'n',
    });
    expect(res.status).toBe(409);
    expect((await res.json()).code).toBe('AUTH_EMAIL_TAKEN');
  });

  it('400 on unknown key (.strict — Mass Assignment)', async () => {
    const res = await post(makeApp(makeDeps()), '/signup', {
      email: 'a@b.com',
      password: '0123456789',
      name: 'n',
      role: 'admin',
    });
    expect(res.status).toBe(400);
  });
});

describe('POST /login', () => {
  it('200 on valid credentials', async () => {
    const res = await post(makeApp(makeDeps()), '/login', { email: 'a@b.com', password: 'pw' });
    expect(res.status).toBe(200);
    expect((await res.json()).data.accessToken).toBe('access.jwt.token');
  });

  it('401 AUTH_INVALID_CREDENTIALS when user missing (enumeration-safe + dummy verify)', async () => {
    const deps = makeDeps({ getUserByEmail: vi.fn(async () => undefined) });
    const res = await post(makeApp(deps), '/login', { email: 'x@y.com', password: 'pw' });
    expect(res.status).toBe(401);
    expect((await res.json()).code).toBe('AUTH_INVALID_CREDENTIALS');
    expect(deps.getDummyHash).toHaveBeenCalledOnce(); // 타이밍 평준화
    expect(deps.verifyPassword).toHaveBeenCalledOnce();
    expect(deps.recordLoginFailure).toHaveBeenCalledOnce();
  });

  it('401 same code on wrong password (no enumeration差)', async () => {
    const deps = makeDeps({ verifyPassword: vi.fn(async () => false) });
    const res = await post(makeApp(deps), '/login', { email: 'a@b.com', password: 'bad' });
    expect(res.status).toBe(401);
    expect((await res.json()).code).toBe('AUTH_INVALID_CREDENTIALS');
  });

  it('429 AUTH_ACCOUNT_LOCKED before argon2 (verify NOT called)', async () => {
    const deps = makeDeps({
      assertNotLocked: vi.fn(async () => {
        throw new AppError('AUTH_ACCOUNT_LOCKED', 'locked', 300);
      }),
    });
    const res = await post(makeApp(deps), '/login', { email: 'a@b.com', password: 'pw' });
    expect(res.status).toBe(429);
    expect(res.headers.get('retry-after')).toBe('300');
    expect(deps.verifyPassword).not.toHaveBeenCalled(); // argon2 미도달(DoS 차단)
  });
});

describe('POST /refresh', () => {
  function refreshRow(over: Record<string, unknown> = {}) {
    return {
      id: 'r1',
      userId: 'u1',
      expiresAt: new Date(NOW + 86400_000),
      revokedAt: null,
      ...over,
    };
  }

  it('200 rotation: revokes old (winner), issues new pair', async () => {
    const deps = makeDeps({ getRefreshByHash: vi.fn(async () => refreshRow()) });
    const res = await post(makeApp(deps), '/refresh', { refreshToken: 'raw' });
    expect(res.status).toBe(200);
    const { data } = await res.json();
    expect(data.refreshToken).toBe('raw-refresh-token');
    expect(deps.revokeRefreshById).toHaveBeenCalledWith('r1');
    expect(deps.createRefresh).toHaveBeenCalledOnce();
  });

  it('401 AUTH_REFRESH_INVALID when no row', async () => {
    const res = await post(makeApp(makeDeps()), '/refresh', { refreshToken: 'raw' });
    expect(res.status).toBe(401);
    expect((await res.json()).code).toBe('AUTH_REFRESH_INVALID');
  });

  it('401 AUTH_REFRESH_INVALID when expired', async () => {
    const deps = makeDeps({
      getRefreshByHash: vi.fn(async () => refreshRow({ expiresAt: new Date(NOW - 1) })),
    });
    const res = await post(makeApp(deps), '/refresh', { refreshToken: 'raw' });
    expect(res.status).toBe(401);
  });

  it('REUSE_DETECTED: grace 밖 revoked → revoke all + bump marker', async () => {
    const deps = makeDeps({
      getRefreshByHash: vi.fn(async () =>
        refreshRow({ revokedAt: new Date(NOW - 60_000) }), // 60s 전(grace 10s 밖)
      ),
    });
    const res = await post(makeApp(deps), '/refresh', { refreshToken: 'raw' });
    expect(res.status).toBe(401);
    expect((await res.json()).code).toBe('REFRESH_REUSE_DETECTED');
    expect(deps.revokeAllRefresh).toHaveBeenCalledWith('u1');
    expect(deps.bumpSessions).toHaveBeenCalledWith('u1');
  });

  it('GRACE: grace 내 revoked → 강제 로그아웃 0 (revoke all/bump 미호출)', async () => {
    const deps = makeDeps({
      getRefreshByHash: vi.fn(async () =>
        refreshRow({ revokedAt: new Date(NOW - 2_000) }), // 2s 전(grace 내)
      ),
    });
    const res = await post(makeApp(deps), '/refresh', { refreshToken: 'raw' });
    expect(res.status).toBe(401);
    expect((await res.json()).code).toBe('AUTH_REFRESH_INVALID');
    expect(deps.revokeAllRefresh).not.toHaveBeenCalled();
    expect(deps.bumpSessions).not.toHaveBeenCalled();
  });

  it('RACE: 활성이나 조건부 revoke affected=0 → benign(전체 폐기 X)', async () => {
    const deps = makeDeps({
      getRefreshByHash: vi.fn(async () => refreshRow()),
      revokeRefreshById: vi.fn(async () => 0),
    });
    const res = await post(makeApp(deps), '/refresh', { refreshToken: 'raw' });
    expect(res.status).toBe(401);
    expect((await res.json()).code).toBe('AUTH_REFRESH_INVALID');
    expect(deps.revokeAllRefresh).not.toHaveBeenCalled();
  });
});

describe('POST /logout', () => {
  it('200 + revoke when own active token', async () => {
    const deps = makeDeps({
      getRefreshByHash: vi.fn(async () => ({
        id: 'r1',
        userId: 'u1',
        expiresAt: new Date(NOW + 1),
        revokedAt: null,
      })),
    });
    const res = await post(makeApp(deps, 'u1'), '/logout', { refreshToken: 'raw' });
    expect(res.status).toBe(200);
    expect((await res.json()).data.revoked).toBe(true);
    expect(deps.revokeRefreshById).toHaveBeenCalledWith('r1');
  });

  it('cross-tenant: victim 토큰 제시 → no-op(revoke 미호출, 200)', async () => {
    const deps = makeDeps({
      getRefreshByHash: vi.fn(async () => ({
        id: 'victim-r',
        userId: 'victim',
        expiresAt: new Date(NOW + 1),
        revokedAt: null,
      })),
    });
    const res = await post(makeApp(deps, 'attacker'), '/logout', { refreshToken: 'victim-raw' });
    expect(res.status).toBe(200);
    expect(deps.revokeRefreshById).not.toHaveBeenCalled(); // victim 세션 보존
  });
});

describe('GET /me', () => {
  it('200 user + subscription', async () => {
    const app = makeApp(makeDeps(), 'u1');
    const res = await app.request('/me', { headers: {} });
    expect(res.status).toBe(200);
    const { data } = await res.json();
    expect(data.user.id).toBe('u1');
    expect(data.subscription).toEqual({ plan: 'free', status: 'active' });
    expect(data.user.passwordHash).toBeUndefined();
  });

  it('404 AUTH_USER_NOT_FOUND when user gone', async () => {
    const deps = makeDeps({ getActiveUserById: vi.fn(async () => undefined) });
    const res = await makeApp(deps, 'ghost').request('/me');
    expect(res.status).toBe(404);
    expect((await res.json()).code).toBe('AUTH_USER_NOT_FOUND');
  });
});

describe('POST /signup — verification email', () => {
  it('sends verification email on success', async () => {
    const deps = makeDeps();
    const res = await post(makeApp(deps), '/signup', {
      email: 'new@ex.com',
      password: '0123456789',
      name: 'n',
    });
    expect(res.status).toBe(201);
    expect(deps.sendVerificationEmail).toHaveBeenCalledOnce();
  });

  it('201 even if sender throws (email send never fails signup)', async () => {
    const deps = makeDeps({
      sendVerificationEmail: vi.fn(async () => {
        throw new Error('resend down');
      }),
    });
    const res = await post(makeApp(deps), '/signup', {
      email: 'new@ex.com',
      password: '0123456789',
      name: 'n',
    });
    expect(res.status).toBe(201);
  });
});

describe('GET /verify-email', () => {
  function verifiedUser(over = {}) {
    return { ...userFixture({ email: 'a@b.com' }), ...over };
  }

  it('200 sets verified + audits on valid token (unverified user)', async () => {
    const deps = makeDeps({
      getActiveUserById: vi.fn(async () => verifiedUser({ emailVerifiedAt: null })),
    });
    const res = await makeApp(deps).request('/verify-email?token=good');
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toMatch(/text\/html/);
    expect(await res.text()).toContain('인증이 완료');
    expect(deps.markEmailVerified).toHaveBeenCalledWith('u1');
    expect(deps.audit).toHaveBeenCalledWith(
      expect.objectContaining({ action: 'auth.email_verified' }),
    );
  });

  it('idempotent: already-verified user → 200 success, no re-mark', async () => {
    const deps = makeDeps({
      getActiveUserById: vi.fn(async () => verifiedUser({ emailVerifiedAt: new Date() })),
    });
    const res = await makeApp(deps).request('/verify-email?token=good');
    expect(res.status).toBe(200);
    expect(await res.text()).toContain('인증이 완료');
    expect(deps.markEmailVerified).not.toHaveBeenCalled();
  });

  it('410 expired token → expired page', async () => {
    const deps = makeDeps({
      verifyEmailToken: vi.fn(() => ({ ok: false as const, reason: 'expired' as const })),
    });
    const res = await makeApp(deps).request('/verify-email?token=old');
    expect(res.status).toBe(410);
    expect(await res.text()).toContain('만료');
    expect(deps.markEmailVerified).not.toHaveBeenCalled();
  });

  it('400 invalid signature → invalid page', async () => {
    const deps = makeDeps({
      verifyEmailToken: vi.fn(() => ({ ok: false as const, reason: 'invalid' as const })),
    });
    const res = await makeApp(deps).request('/verify-email?token=bad');
    expect(res.status).toBe(400);
    expect(await res.text()).toContain('올바르지 않');
  });

  it('400 email mismatch (token em != current email) → invalid', async () => {
    const deps = makeDeps({
      getActiveUserById: vi.fn(async () => verifiedUser({ email: 'changed@ex.com' })),
    });
    const res = await makeApp(deps).request('/verify-email?token=good');
    expect(res.status).toBe(400);
    expect(deps.markEmailVerified).not.toHaveBeenCalled();
  });
});

describe('POST /resend-verification', () => {
  it('200 {sent:true} sends when unverified', async () => {
    const deps = makeDeps({
      getActiveUserById: vi.fn(async () => userFixture({ emailVerifiedAt: null })),
    });
    const res = await post(makeApp(deps, 'u1'), '/resend-verification', {});
    expect(res.status).toBe(200);
    expect((await res.json()).data).toEqual({ sent: true });
    expect(deps.sendVerificationEmail).toHaveBeenCalledOnce();
  });

  it('409 AUTH_EMAIL_ALREADY_VERIFIED when already verified (no send)', async () => {
    const deps = makeDeps({
      getActiveUserById: vi.fn(async () => userFixture({ emailVerifiedAt: new Date() })),
    });
    const res = await post(makeApp(deps, 'u1'), '/resend-verification', {});
    expect(res.status).toBe(409);
    expect((await res.json()).code).toBe('AUTH_EMAIL_ALREADY_VERIFIED');
    expect(deps.sendVerificationEmail).not.toHaveBeenCalled();
  });

  it('404 when user missing', async () => {
    const deps = makeDeps({ getActiveUserById: vi.fn(async () => undefined) });
    const res = await post(makeApp(deps, 'ghost'), '/resend-verification', {});
    expect(res.status).toBe(404);
  });
});
