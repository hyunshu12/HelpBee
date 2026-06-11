/**
 * 로그인 계정 보호 — argon2 verify 이전 게이트 (backend-design §8.5.3, §13 API2).
 * - 복합 키 auth:fail:{email}:{ip} 로 실패 누적 → maxFails 초과 시 AUTH_ACCOUNT_LOCKED(429)+Retry-After.
 * - 이메일만 키로 쓰면 victim lockout-DoS → 복합 키(email+ip)로 분리.
 * - 검사를 argon2 이전에 수행해 throttle된 시도가 argon2(19MB/호출)에 도달하지 못하게(메모리 DoS 차단).
 * - Redis 직접 의존 대신 RedisLike 주입(테스트는 fake).
 */
import { AppError } from '../lib/error-codes';

export type RedisLike = {
  incr(key: string): Promise<number>;
  expire(key: string, seconds: number): Promise<unknown>;
  ttl(key: string): Promise<number>;
  get(key: string): Promise<string | null>;
  del(key: string): Promise<unknown>;
};

function failKey(email: string, ip: string): string {
  return `auth:fail:${email}:${ip}`;
}

/** 잠금 상태면 AUTH_ACCOUNT_LOCKED throw (Retry-After 포함). argon2 verify 이전에 호출. */
export async function assertNotLocked(
  redis: RedisLike,
  opts: { email: string; ip: string; maxFails: number },
): Promise<void> {
  const key = failKey(opts.email, opts.ip);
  const raw = await redis.get(key);
  const count = raw ? Number(raw) : 0;
  if (count >= opts.maxFails) {
    const ttl = await redis.ttl(key);
    throw new AppError(
      'AUTH_ACCOUNT_LOCKED',
      'too many failed attempts',
      ttl > 0 ? ttl : undefined,
    );
  }
}

/** 로그인 실패 1건 기록(슬라이딩 TTL). */
export async function recordFailure(
  redis: RedisLike,
  opts: { email: string; ip: string; windowSec: number },
): Promise<number> {
  const key = failKey(opts.email, opts.ip);
  const count = await redis.incr(key);
  if (count === 1) {
    await redis.expire(key, opts.windowSec);
  }
  return count;
}

/** 로그인 성공 시 실패 카운터 제거. */
export async function clearFailures(
  redis: RedisLike,
  opts: { email: string; ip: string },
): Promise<void> {
  await redis.del(failKey(opts.email, opts.ip));
}
