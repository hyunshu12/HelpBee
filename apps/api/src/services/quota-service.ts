/**
 * 무료 분석 쿼터 — reserve-then-refund (backend-design §2-③, D4).
 * - 추론 직전 원자 INCR로 "예약" → freeLimit 초과면 즉시 DECR 롤백 + QUOTA_EXCEEDED.
 * - 추론 성공 시 예약 확정(아무것도 안 함). 실패 시 refund(DECR). 멱등 short-circuit은 미예약.
 * - 키/TTL 모두 KST 월경계 기준(다음 KST 월초까지). Redis 장애 시 호출부는 fail-closed.
 * Redis 직접 의존 대신 RedisLike 인터페이스 주입(테스트는 fake).
 */
import { AppError } from '../lib/error-codes';

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

export type RedisLike = {
  incr(key: string): Promise<number>;
  decr(key: string): Promise<number>;
  expire(key: string, seconds: number): Promise<unknown>;
  ttl(key: string): Promise<number>;
};

export function kstMonthKey(userId: string, now: Date): string {
  const k = new Date(now.getTime() + KST_OFFSET_MS);
  const year = k.getUTCFullYear();
  const month = String(k.getUTCMonth() + 1).padStart(2, '0');
  return `quota:${userId}:${year}${month}`;
}

export function secondsUntilKstMonthEnd(now: Date): number {
  const k = new Date(now.getTime() + KST_OFFSET_MS);
  // KST wall-clock 기준 다음 달 1일 00:00 → 실제 UTC ms로 환산(오프셋 빼기)
  const nextMonthKstWall = Date.UTC(k.getUTCFullYear(), k.getUTCMonth() + 1, 1, 0, 0, 0);
  const nextMonthRealMs = nextMonthKstWall - KST_OFFSET_MS;
  return Math.max(1, Math.ceil((nextMonthRealMs - now.getTime()) / 1000));
}

export async function reserve(
  redis: RedisLike,
  userId: string,
  opts: { freeLimit?: number; now?: Date } = {},
): Promise<number> {
  const now = opts.now ?? new Date();
  const limit = opts.freeLimit ?? 4;
  const key = kstMonthKey(userId, now);

  const count = await redis.incr(key);
  if (count === 1) {
    await redis.expire(key, secondsUntilKstMonthEnd(now));
  } else {
    const ttl = await redis.ttl(key);
    if (ttl < 0) await redis.expire(key, secondsUntilKstMonthEnd(now)); // 방어: 만료 누락 복구
  }

  if (count > limit) {
    await redis.decr(key); // 초과 시도는 무차감 — 예약 롤백
    throw new AppError('QUOTA_EXCEEDED', `free tier limit (${limit}/month) reached`);
  }
  return count;
}

export async function refund(redis: RedisLike, userId: string, now: Date = new Date()): Promise<void> {
  const key = kstMonthKey(userId, now);
  const v = await redis.decr(key);
  if (v < 0) await redis.incr(key); // floor at 0
}
