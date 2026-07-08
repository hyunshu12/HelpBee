/**
 * Auth 라우트 (backend-design §8). signup/login/refresh/logout/me.
 * - 동기 오케스트레이션, DI로 외부(DB·Redis·argon2·jwt) 분리 → 목으로 단위 검증.
 * - 보안 핵심(재설계 금지): argon2id 비번 / HMAC refresh / JWT alg핀 / 회전+재사용감지+grace /
 *   계정보호(argon2 이전 게이트) / enumeration 방지(미존재·불일치 동일 코드 + 더미 verify) /
 *   logout cross-tenant no-op / 즉시 회수 마커 bump.
 * app.ts가 실제 구현(@helpbee/database queries, services/*)을 주입.
 */
import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { getClientIp } from '../lib/client-ip';
import { created, ok } from '../lib/envelope';
import { AppError } from '../lib/error-codes';
import { problem } from '../lib/problem';
import { loginSchema, logoutSchema, refreshSchema, signupSchema, toPublicUser } from '../schemas/auth';
import { renderVerifyEmailResultPage } from '../services/email-service';

const ACCESS_EXPIRES_IN = 900; // 15m (응답 expiresIn 고지용)
const REFRESH_GRACE_SEC = 10; // 동시 refresh 오탐 방지(§8.4 grace window)

export type UserRow = {
  id: string;
  email: string;
  name: string;
  role: string;
  passwordHash: string;
  emailVerifiedAt: Date | null;
  createdAt: Date;
};

export type RefreshRow = {
  id: string;
  userId: string;
  expiresAt: Date;
  revokedAt: Date | null;
};

export type AuthDeps = {
  // queries
  createUser(input: { email: string; name: string; passwordHash: string }): Promise<UserRow>; // email 충돌 시 throw(23505)
  getUserByEmail(email: string): Promise<UserRow | undefined>;
  getActiveUserById(userId: string): Promise<UserRow | undefined>;
  getSubscription(userId: string): Promise<{ plan: string; status: string } | undefined>;
  getRefreshByHash(hash: string): Promise<RefreshRow | undefined>;
  createRefresh(input: {
    userId: string;
    tokenHash: string;
    expiresAt: Date;
    userAgent: string | null;
    ip: string | null;
  }): Promise<unknown>;
  revokeRefreshById(id: string): Promise<number>; // 조건부 revoke affected(승자만)
  revokeAllRefresh(userId: string): Promise<number>;
  // services
  hashPassword(pw: string): Promise<string>;
  verifyPassword(hash: string, pw: string): Promise<boolean>;
  getDummyHash(): Promise<string>;
  signAccess(input: { userId: string; role: string; emailVerified: boolean }): string;
  generateRefresh(): string;
  hashRefresh(token: string): string;
  refreshExpiry(): Date;
  // account protection (Redis)
  assertNotLocked(input: { email: string; ip: string }): Promise<void>; // 초과 시 AUTH_ACCOUNT_LOCKED throw
  recordLoginFailure(input: { email: string; ip: string }): Promise<void>;
  clearLoginFailures(input: { email: string; ip: string }): Promise<void>;
  // sessions marker (Redis)
  bumpSessions(userId: string): Promise<void>;
  // email verification (P1-4) — 발송/검증/마킹. 발송은 절대 흐름을 깨지 않음(라우트가 try/catch).
  sendVerificationEmail(user: { id: string; email: string }): Promise<void>;
  verifyEmailToken(token: string):
    | { ok: true; payload: { sub: string; em: string; exp: number } }
    | { ok: false; reason: 'invalid' | 'expired' };
  markEmailVerified(userId: string): Promise<void>;
  // audit (best-effort)
  audit(entry: {
    actorId: string | null;
    action: string;
    entity: string;
    entityId: string | null;
    metadata?: Record<string, unknown> | null;
    ip: string | null;
    userAgent: string | null;
  }): Promise<void>;
  now(): number;
};

function isUniqueViolation(err: unknown): boolean {
  return typeof err === 'object' && err !== null && (err as { code?: string }).code === '23505';
}

export function authRoutes(deps: AuthDeps) {
  const app = new Hono();

  // POST /signup (201)
  app.post('/signup', zValidator('json', signupSchema), async (c) => {
    const { email, password, name } = c.req.valid('json');
    const ip = getClientIp(c);
    const ua = c.req.header('user-agent') ?? null;

    const passwordHash = await deps.hashPassword(password);

    let user: UserRow;
    try {
      user = await deps.createUser({ email, name, passwordHash });
    } catch (err) {
      if (isUniqueViolation(err)) return problem(c, 'AUTH_EMAIL_TAKEN');
      throw err;
    }

    const refreshRaw = deps.generateRefresh();
    await deps.createRefresh({
      userId: user.id,
      tokenHash: deps.hashRefresh(refreshRaw),
      expiresAt: deps.refreshExpiry(),
      userAgent: ua,
      ip,
    });
    const accessToken = deps.signAccess({ userId: user.id, role: user.role, emailVerified: false });

    await deps.audit({
      actorId: user.id,
      action: 'auth.signup',
      entity: 'user',
      entityId: user.id,
      metadata: {},
      ip,
      userAgent: ua,
    });

    // 인증 메일 발송 — 실패해도 201을 막지 않는다(발송은 부가효과, catch-all).
    try {
      await deps.sendVerificationEmail({ id: user.id, email: user.email });
    } catch {
      /* best-effort: 발송 실패는 signup을 실패시키지 않음 */
    }

    return created(c, {
      user: toPublicUser(user),
      accessToken,
      refreshToken: refreshRaw,
      expiresIn: ACCESS_EXPIRES_IN,
    });
  });

  // POST /login (200)
  app.post('/login', zValidator('json', loginSchema), async (c) => {
    const { email, password } = c.req.valid('json');
    const ip = getClientIp(c);
    const ua = c.req.header('user-agent') ?? null;

    // 계정 보호 게이트 — argon2 verify 이전(메모리 DoS·lockout-DoS 차단)
    await deps.assertNotLocked({ email, ip });

    const user = await deps.getUserByEmail(email);
    // user 미존재여도 더미 해시로 1회 verify(타이밍 차이 최소화 + enumeration 방지)
    const hash = user?.passwordHash ?? (await deps.getDummyHash());
    const okPw = await deps.verifyPassword(hash, password);

    if (!user || !okPw) {
      await deps.recordLoginFailure({ email, ip });
      await deps.audit({
        actorId: null,
        action: 'auth.login_failed',
        entity: 'user',
        entityId: null,
        metadata: { reason: 'invalid_credentials' }, // 입력값·비번 미기록
        ip,
        userAgent: ua,
      });
      return problem(c, 'AUTH_INVALID_CREDENTIALS');
    }

    await deps.clearLoginFailures({ email, ip });

    const refreshRaw = deps.generateRefresh();
    await deps.createRefresh({
      userId: user.id,
      tokenHash: deps.hashRefresh(refreshRaw),
      expiresAt: deps.refreshExpiry(),
      userAgent: ua,
      ip,
    });
    const accessToken = deps.signAccess({
      userId: user.id,
      role: user.role,
      emailVerified: user.emailVerifiedAt != null,
    });

    await deps.audit({
      actorId: user.id,
      action: 'auth.login',
      entity: 'user',
      entityId: user.id,
      metadata: { via: 'password' },
      ip,
      userAgent: ua,
    });

    return ok(c, {
      user: toPublicUser(user),
      accessToken,
      refreshToken: refreshRaw,
      expiresIn: ACCESS_EXPIRES_IN,
    });
  });

  // POST /refresh (200) — 회전 + 재사용 감지 + grace window
  app.post('/refresh', zValidator('json', refreshSchema), async (c) => {
    const { refreshToken } = c.req.valid('json');
    const ip = getClientIp(c);
    const ua = c.req.header('user-agent') ?? null;
    const hash = deps.hashRefresh(refreshToken);

    const row = await deps.getRefreshByHash(hash);
    if (!row) return problem(c, 'AUTH_REFRESH_INVALID');
    if (row.expiresAt.getTime() <= deps.now()) return problem(c, 'AUTH_REFRESH_INVALID');

    if (row.revokedAt) {
      const sinceRevokeMs = deps.now() - row.revokedAt.getTime();
      if (sinceRevokeMs <= REFRESH_GRACE_SEC * 1000) {
        // benign 동시 refresh(loser) — 전체 폐기하지 않음(강제 로그아웃 0). 승자 토큰으로 재시도.
        return problem(c, 'AUTH_REFRESH_INVALID');
      }
      // grace 밖 revoked 재사용 = 공격 신호 → 전체 폐기 + 마커 bump
      const revokedCount = await deps.revokeAllRefresh(row.userId);
      await deps.bumpSessions(row.userId);
      await deps.audit({
        actorId: row.userId,
        action: 'auth.refresh_reuse_detected',
        entity: 'user',
        entityId: row.userId,
        metadata: { tokenHashPrefix: hash.slice(0, 8), revokedCount },
        ip,
        userAgent: ua,
      });
      return problem(c, 'REFRESH_REUSE_DETECTED');
    }

    // 활성 토큰 — 조건부 revoke(승자만)
    const affected = await deps.revokeRefreshById(row.id);
    if (affected === 0) {
      // 동시요청이 먼저 회전(race) → benign, 전체 폐기 금지
      return problem(c, 'AUTH_REFRESH_INVALID');
    }

    const user = await deps.getActiveUserById(row.userId);
    if (!user) return problem(c, 'AUTH_REFRESH_INVALID'); // 탈퇴/차단

    const newRefreshRaw = deps.generateRefresh();
    await deps.createRefresh({
      userId: user.id,
      tokenHash: deps.hashRefresh(newRefreshRaw),
      expiresAt: deps.refreshExpiry(),
      userAgent: ua,
      ip,
    });
    const accessToken = deps.signAccess({
      userId: user.id,
      role: user.role,
      emailVerified: user.emailVerifiedAt != null,
    });

    await deps.audit({
      actorId: user.id,
      action: 'auth.refresh',
      entity: 'user',
      entityId: user.id,
      metadata: {},
      ip,
      userAgent: ua,
    });

    return ok(c, { accessToken, refreshToken: newRefreshRaw, expiresIn: ACCESS_EXPIRES_IN });
  });

  // POST /logout (200) — requireAuth는 app.ts에서 마운트. 항상 200(idempotent).
  app.post('/logout', zValidator('json', logoutSchema), async (c) => {
    const userId = c.get('userId') as string;
    const { refreshToken } = c.req.valid('json');
    const ip = getClientIp(c);
    const ua = c.req.header('user-agent') ?? null;

    const row = await deps.getRefreshByHash(deps.hashRefresh(refreshToken));
    // 본인 소유 + 미폐기일 때만 revoke. 타인 토큰이면 no-op(cross-tenant denial 차단, §8.3).
    if (row && row.userId === userId && !row.revokedAt) {
      await deps.revokeRefreshById(row.id);
      await deps.audit({
        actorId: userId,
        action: 'auth.logout',
        entity: 'user',
        entityId: userId,
        metadata: {},
        ip,
        userAgent: ua,
      });
    }
    return ok(c, { revoked: true });
  });

  // GET /verify-email?token= (🔓) — 이메일 링크에서 브라우저로 진입. 항상 HTML(성공/만료/무효).
  app.get('/verify-email', async (c) => {
    const token = c.req.query('token') ?? '';
    const ip = getClientIp(c);
    const ua = c.req.header('user-agent') ?? null;

    const result = deps.verifyEmailToken(token);
    if (!result.ok) {
      const state = result.reason === 'expired' ? 'expired' : 'invalid';
      return c.html(renderVerifyEmailResultPage(state), state === 'expired' ? 410 : 400);
    }

    const user = await deps.getActiveUserById(result.payload.sub);
    // 사용자 없음(탈퇴/차단) 또는 이메일 불일치(가입 후 이메일 변경) → 무효 처리.
    if (!user || user.email.toLowerCase() !== result.payload.em.toLowerCase()) {
      return c.html(renderVerifyEmailResultPage('invalid'), 400);
    }

    // 멱등: 이미 인증된 계정은 재마킹/재감사 없이 동일 성공 페이지.
    if (user.emailVerifiedAt == null) {
      await deps.markEmailVerified(user.id);
      await deps.audit({
        actorId: user.id,
        action: 'auth.email_verified',
        entity: 'user',
        entityId: user.id,
        metadata: {},
        ip,
        userAgent: ua,
      });
    }
    return c.html(renderVerifyEmailResultPage('success'), 200);
  });

  // POST /resend-verification (🔐) — requireAuth + 3회/시간/user 레이트리밋은 app.ts에서 마운트.
  app.post('/resend-verification', async (c) => {
    const userId = c.get('userId') as string;
    const ip = getClientIp(c);
    const ua = c.req.header('user-agent') ?? null;

    const user = await deps.getActiveUserById(userId);
    if (!user) return problem(c, 'AUTH_USER_NOT_FOUND');
    // 이미 인증됨 → 409(재발송 불필요를 명시). 모바일은 이 코드로 "이미 인증됨" 안내.
    if (user.emailVerifiedAt != null) return problem(c, 'AUTH_EMAIL_ALREADY_VERIFIED');

    try {
      await deps.sendVerificationEmail({ id: user.id, email: user.email });
    } catch {
      /* best-effort: 발송 실패해도 200(사용자에게 재시도 여지) */
    }
    await deps.audit({
      actorId: userId,
      action: 'auth.verification_resent',
      entity: 'user',
      entityId: userId,
      metadata: {},
      ip,
      userAgent: ua,
    });
    return ok(c, { sent: true });
  });

  // GET /me (200) — requireAuth는 app.ts에서 마운트.
  app.get('/me', async (c) => {
    const userId = c.get('userId') as string;
    const user = await deps.getActiveUserById(userId);
    if (!user) return problem(c, 'AUTH_USER_NOT_FOUND');
    const sub = await deps.getSubscription(userId);
    return ok(c, {
      user: toPublicUser(user),
      subscription: { plan: sub?.plan ?? 'free', status: sub?.status ?? 'active' },
    });
  });

  return app;
}

export { AppError };
