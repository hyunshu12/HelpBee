/**
 * 즉시 세션 회수 마커 (backend-design §7.9, §8.4, §13 API2 MUST).
 * Redis `sessions_valid_after:{userId}` = unix초. access의 iat < marker면 거부.
 * full blacklist 아님, O(1). block/탈퇴/비번·이메일 변경/refresh-reuse 시 bump.
 * RedisLike 주입(테스트는 fake).
 */
export type RedisLike = {
  get(key: string): Promise<string | null>;
  set(key: string, value: string): Promise<unknown>;
};

function markerKey(userId: string): string {
  return `sessions_valid_after:${userId}`;
}

/** access 토큰 iat가 마커 이전이면 회수된 세션 → true. */
export async function isSessionRevoked(
  redis: RedisLike,
  userId: string,
  iat: number,
): Promise<boolean> {
  const raw = await redis.get(markerKey(userId));
  if (!raw) return false;
  const validAfter = Number(raw);
  if (!Number.isFinite(validAfter)) return false;
  return iat < validAfter;
}

/** 이 시점 이전 발급 access를 일괄 무효화(마커 bump). */
export async function bumpSessionsValidAfter(
  redis: RedisLike,
  userId: string,
  now: number = Date.now(),
): Promise<void> {
  await redis.set(markerKey(userId), String(Math.floor(now / 1000)));
}
