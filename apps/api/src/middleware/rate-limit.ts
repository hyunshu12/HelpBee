/**
 * 레이트리밋 — Redis 고정 윈도(분 단위) (backend-design §7.5).
 * - 초과 시 RATE_LIMITED(429) + Retry-After.
 * - **fail-closed**: Redis 장애 시 거부(가용성보다 남용 차단 우선 — quota와 동일 정책).
 * - quota(무료 월 4회)와는 별개 계층(역할 분리, 차감 안 함).
 * RedisLike 주입(테스트 fake).
 */
import { createMiddleware } from 'hono/factory';
import type { Context } from 'hono';

import { AppError } from '../lib/error-codes';

export type RateRedis = {
  incr(key: string): Promise<number>;
  expire(key: string, seconds: number): Promise<unknown>;
  ttl(key: string): Promise<number>;
};

export function rateLimit(opts: {
  redis: RateRedis;
  limit: number;
  windowSec: number;
  prefix: string;
  keyFn: (c: Context) => string;
  now?: () => number;
}) {
  const now = opts.now ?? (() => Date.now());
  return createMiddleware(async (c, next) => {
    try {
      const window = Math.floor(now() / 1000 / opts.windowSec);
      const key = `rl:${opts.prefix}:${opts.keyFn(c)}:${window}`;
      const count = await opts.redis.incr(key);
      if (count === 1) await opts.redis.expire(key, opts.windowSec);
      if (count > opts.limit) {
        const ttl = await opts.redis.ttl(key);
        throw new AppError('RATE_LIMITED', 'too many requests', ttl > 0 ? ttl : opts.windowSec);
      }
    } catch (err) {
      if (err instanceof AppError) throw err;
      // Redis 장애 → fail-closed(남용 차단 우선, §7.5)
      throw new AppError('RATE_LIMITED', 'rate limiter unavailable', opts.windowSec);
    }
    await next();
  });
}
