/**
 * 인증/인가 미들웨어 (backend-design §7.8, §8).
 * - requireAuth(secret): Bearer access(JWT HS256, **alg 명시 검증** — alg confusion 차단).
 *   성공 시 c.set('userId','role'). 실패 401(만료는 AUTH_TOKEN_EXPIRED).
 * - requireRole(role): role 불충분 시 403 FORBIDDEN_ROLE (requireAuth 이후 마운트).
 */
import { createMiddleware } from 'hono/factory';
import jwt from 'jwt-simple';

import { AppError } from '../lib/error-codes';

export function requireAuth(secret: string) {
  return createMiddleware(async (c, next) => {
    const header = c.req.header('authorization');
    if (!header || !header.startsWith('Bearer ')) {
      throw new AppError('AUTH_UNAUTHORIZED');
    }
    const token = header.slice('Bearer '.length).trim();

    let payload: { sub?: string; role?: string; exp?: number };
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

    if (typeof payload.exp === 'number' && Date.now() / 1000 > payload.exp) {
      throw new AppError('AUTH_TOKEN_EXPIRED');
    }
    if (!payload.sub) {
      throw new AppError('AUTH_UNAUTHORIZED');
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
