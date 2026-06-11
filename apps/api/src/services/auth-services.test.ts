import { describe, expect, it } from 'vitest';
import jwt from 'jwt-simple';

import { AppError } from '../lib/error-codes';
import { bumpSessionsValidAfter, isSessionRevoked } from '../lib/sessions';
import {
  assertNotLocked,
  clearFailures,
  recordFailure,
  type RedisLike as ProtRedis,
} from './account-protection';
import {
  ACCESS_TTL_SEC,
  generateRefreshToken,
  hashRefreshToken,
  signAccessToken,
} from './jwt-service';
import { getDummyHash, hashPassword, verifyPassword } from './password-service';

const SECRET = 'x'.repeat(64);
const PEPPER = 'p'.repeat(40);

/** 최소 fake Redis (string KV). */
function fakeRedis() {
  const store = new Map<string, string>();
  return {
    store,
    async incr(k: string) {
      const v = (Number(store.get(k) ?? '0') || 0) + 1;
      store.set(k, String(v));
      return v;
    },
    async expire() {
      return 1;
    },
    async ttl() {
      return 900;
    },
    async get(k: string) {
      return store.get(k) ?? null;
    },
    async set(k: string, v: string) {
      store.set(k, v);
      return 'OK';
    },
    async del(k: string) {
      store.delete(k);
      return 1;
    },
  };
}

describe('password-service (argon2id)', () => {
  it('hash → verify roundtrip', async () => {
    const h = await hashPassword('correct-horse-battery');
    expect(h).toMatch(/^\$argon2id\$/);
    expect(await verifyPassword(h, 'correct-horse-battery')).toBe(true);
  });

  it('wrong password → false', async () => {
    const h = await hashPassword('correct-horse-battery');
    expect(await verifyPassword(h, 'wrong-password')).toBe(false);
  });

  it('malformed hash → false (no throw)', async () => {
    expect(await verifyPassword('not-a-hash', 'whatever')).toBe(false);
  });

  it('getDummyHash returns a real verifiable argon2 hash (timing equalization)', async () => {
    const d = await getDummyHash();
    expect(d).toMatch(/^\$argon2id\$/);
    expect(await verifyPassword(d, 'anything-wrong')).toBe(false);
  });
});

describe('jwt-service', () => {
  it('signAccessToken: HS256 decodable with claims + 15m exp', () => {
    const now = Date.now(); // 실제 시각 기반(jwt.decode가 exp를 현재시각과 비교)
    const t = signAccessToken(SECRET, {
      userId: 'u1',
      role: 'user',
      emailVerified: true,
      now,
    });
    const decoded = jwt.decode(t, SECRET, false, 'HS256');
    expect(decoded.sub).toBe('u1');
    expect(decoded.role).toBe('user');
    expect(decoded.ev).toBe(true);
    expect(decoded.iat).toBe(Math.floor(now / 1000));
    expect(decoded.exp).toBe(Math.floor(now / 1000) + ACCESS_TTL_SEC);
    expect(decoded.aud).toBeUndefined();
  });

  it('signAccessToken: admin audience scoping', () => {
    const t = signAccessToken(SECRET, {
      userId: 'a1',
      role: 'admin',
      emailVerified: true,
      audience: 'helpbee-admin',
    });
    expect(jwt.decode(t, SECRET, false, 'HS256').aud).toBe('helpbee-admin');
  });

  it('generateRefreshToken: opaque, unique', () => {
    const a = generateRefreshToken();
    const b = generateRefreshToken();
    expect(a).not.toBe(b);
    expect(a.length).toBeGreaterThanOrEqual(43); // 32 bytes base64url
    expect(a).toMatch(/^[A-Za-z0-9_-]+$/);
  });

  it('hashRefreshToken: deterministic, token- and pepper-dependent', () => {
    const tok = generateRefreshToken();
    expect(hashRefreshToken(PEPPER, tok)).toBe(hashRefreshToken(PEPPER, tok));
    expect(hashRefreshToken(PEPPER, tok)).not.toBe(hashRefreshToken(PEPPER, generateRefreshToken()));
    expect(hashRefreshToken(PEPPER, tok)).not.toBe(hashRefreshToken('q'.repeat(40), tok));
  });
});

describe('account-protection (argon2 이전 게이트)', () => {
  const base = { email: 'a@b.com', ip: '1.2.3.4' };

  it('assertNotLocked: under threshold passes', async () => {
    const r = fakeRedis() as unknown as ProtRedis;
    await expect(assertNotLocked(r, { ...base, maxFails: 10 })).resolves.toBeUndefined();
  });

  it('recordFailure increments; lockout at threshold throws 429 + retryAfter', async () => {
    const r = fakeRedis() as unknown as ProtRedis;
    for (let i = 0; i < 10; i++) await recordFailure(r, { ...base, windowSec: 900 });
    await expect(assertNotLocked(r, { ...base, maxFails: 10 })).rejects.toMatchObject({
      code: 'AUTH_ACCOUNT_LOCKED',
      retryAfterSec: 900,
    });
  });

  it('AppError carries AUTH_ACCOUNT_LOCKED', async () => {
    const r = fakeRedis() as unknown as ProtRedis;
    for (let i = 0; i < 5; i++) await recordFailure(r, { ...base, windowSec: 900 });
    let caught: unknown;
    try {
      await assertNotLocked(r, { ...base, maxFails: 5 });
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(AppError);
  });

  it('clearFailures resets counter (lockout lifted)', async () => {
    const r = fakeRedis() as unknown as ProtRedis;
    for (let i = 0; i < 10; i++) await recordFailure(r, { ...base, windowSec: 900 });
    await clearFailures(r, base);
    await expect(assertNotLocked(r, { ...base, maxFails: 10 })).resolves.toBeUndefined();
  });

  it('composite key: different IP not locked by victim email failures', async () => {
    const r = fakeRedis() as unknown as ProtRedis;
    for (let i = 0; i < 10; i++)
      await recordFailure(r, { email: 'victim@b.com', ip: 'attacker', windowSec: 900 });
    // victim's own IP unaffected (lockout-DoS 차단)
    await expect(
      assertNotLocked(r, { email: 'victim@b.com', ip: 'victim-ip', maxFails: 10 }),
    ).resolves.toBeUndefined();
  });
});

describe('sessions marker (즉시 회수)', () => {
  it('no marker → not revoked', async () => {
    const r = fakeRedis();
    expect(await isSessionRevoked(r, 'u1', 1000)).toBe(false);
  });

  it('iat before marker → revoked; iat at/after → valid', async () => {
    const r = fakeRedis();
    await bumpSessionsValidAfter(r, 'u1', 2_000_000); // marker = 2000s
    expect(await isSessionRevoked(r, 'u1', 1999)).toBe(true);
    expect(await isSessionRevoked(r, 'u1', 2000)).toBe(false);
    expect(await isSessionRevoked(r, 'u1', 2001)).toBe(false);
  });

  it('marker is per-user', async () => {
    const r = fakeRedis();
    await bumpSessionsValidAfter(r, 'u1', 2_000_000);
    expect(await isSessionRevoked(r, 'u2', 1)).toBe(false);
  });
});
