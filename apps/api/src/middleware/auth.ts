/**
 * 인증/인가 미들웨어 (backend-design §7.8, §7.9, §8).
 * - requireAuth(secret, opts?): Bearer access(JWT HS256, **alg 명시 검증** — alg confusion 차단).
 *   성공 시 c.set('userId','role'). 실패 401(만료는 AUTH_TOKEN_EXPIRED).
 *   opts.isRevoked 주입 시 sessions_valid_after 마커로 즉시 회수 검사(§7.9 MUST):
 *   block/탈퇴/비번변경/refresh-reuse 시 bump된 마커보다 iat가 이전이면 거부.
 * - requireRole(role): role 불충분 시 403 FORBIDDEN_ROLE (requireAuth 이후 마운트).
 */
import { createMiddleware } from 'hono/factory';
import jwt from 'jwt-simple';

import { AppError } from '../lib/error-codes';

export type RequireAuthOpts = {
  /** access iat가 회수 마커 이전이면 true → AUTH_UNAUTHORIZED. */
  isRevoked?: (userId: string, iat: number) => Promise<boolean>;
};

export function requireAuth(secret: string, opts: RequireAuthOpts = {}) {
  return createMiddleware(async (c, next) => {
    const header = c.req.header('authorization');
    if (!header || !header.startsWith('Bearer ')) {
      throw new AppError('AUTH_UNAUTHORIZED');
    }
    const token = header.slice('Bearer '.length).trim();

    let payload: { sub?: string; role?: string; exp?: number; iat?: number };
    try {
      // 4번째 인자로 HS256 강제 → none/RS256/HS512 등 alg confusion 거부.
      payload = jwt.decode(token, secret, false, 'HS256');
    } catch (err) {
      const message = err instanceof Error ? err.message.toLowerCase() : '';
      if (message.includes('expired')) {
        throw new AppError('AUTH_TOKEN_EXPIRED');
      }
      throw new AppError('AUTH_UNAUTHORIZED');
    }

    if (typeof payload.exp !== 'number') {
      throw new AppError('AUTH_UNAUTHORIZED'); // exp 없는 영구 access 토큰 거부(15m 정책)
    }
    if (Date.now() / 1000 > payload.exp) {
      throw new AppError('AUTH_TOKEN_EXPIRED');
    }
    if (!payload.sub) {
      throw new AppError('AUTH_UNAUTHORIZED');
    }

    // 즉시 세션 회수 검사(§7.9). iat 없는 토큰은 마커 비교 불가 → 보수적으로 거부.
    if (opts.isRevoked) {
      if (typeof payload.iat !== 'number') {
        throw new AppError('AUTH_UNAUTHORIZED');
      }
      if (await opts.isRevoked(payload.sub, payload.iat)) {
        throw new AppError('AUTH_UNAUTHORIZED');
      }
    }

    c.set('userId', payload.sub);
    c.set('role', payload.role ?? 'user');
    await next();
  });
}

export function requireRole(role: string) {
  return createMiddleware(async (c, next) => {
    if (c.get('role') !== role) {
      throw new AppError('FORBIDDEN_ROLE');
    }
    await next();
  });
}
