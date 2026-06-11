/**
 * 비밀번호 해싱 (backend-design §8.5.1, 1부 확정).
 * argon2id only. memoryCost=19456, timeCost=2, parallelism=1 (OWASP 2024).
 * bcrypt/scrypt/PBKDF2 금지. refresh 토큰 해싱(HMAC, jwt-service)과 별도 서비스로 분리(§13 MUST).
 */
import argon2 from 'argon2';

const ARGON2_OPTS = {
  type: argon2.argon2id,
  memoryCost: 19456,
  timeCost: 2,
  parallelism: 1,
} as const;

export function hashPassword(plain: string): Promise<string> {
  return argon2.hash(plain, ARGON2_OPTS);
}

export async function verifyPassword(hash: string, plain: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, plain);
  } catch {
    // 손상된 해시 등은 false (예외 전파 금지 — enumeration/500 방지)
    return false;
  }
}

/**
 * user 미존재 시에도 동일 비용의 argon2 verify를 1회 수행하기 위한 더미 해시.
 * 실제 argon2id 해시를 lazy 생성·캐시 (가짜 PHC는 파싱 단계에서 빨리 실패 → 타이밍 누출).
 */
let dummyHashPromise: Promise<string> | null = null;
export function getDummyHash(): Promise<string> {
  if (!dummyHashPromise) {
    dummyHashPromise = hashPassword('helpbee-dummy-password-for-timing-equalization');
  }
  return dummyHashPromise;
}
