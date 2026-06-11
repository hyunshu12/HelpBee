import { describe, expect, it } from 'vitest';

import { loadEnv } from './env';

const valid = {
  DATABASE_URL: 'postgres://u:p@localhost:5432/helpbee',
  REDIS_URL: 'redis://localhost:6379',
  JWT_SECRET: 'a'.repeat(64),
  REFRESH_TOKEN_PEPPER: 'b'.repeat(32),
  AI_BASE_URL: 'http://ai:8000',
  AI_INTERNAL_HMAC_SECRET: 'c'.repeat(32),
  S3_IMAGES_BUCKET: 'helpbee-images-dev',
};

describe('loadEnv', () => {
  it('parses valid env with defaults', () => {
    const env = loadEnv(valid);
    expect(env.AWS_REGION).toBe('ap-northeast-2');
    expect(env.PORT).toBe(3001);
    expect(env.NODE_ENV).toBe('development');
  });

  it('coerces PORT from string', () => {
    expect(loadEnv({ ...valid, PORT: '4000' }).PORT).toBe(4000);
  });

  it('throws when JWT_SECRET too short (<64)', () => {
    expect(() => loadEnv({ ...valid, JWT_SECRET: 'short' })).toThrow(/JWT_SECRET/);
  });

  it('throws when REFRESH_TOKEN_PEPPER too short (<32)', () => {
    expect(() => loadEnv({ ...valid, REFRESH_TOKEN_PEPPER: 'x' })).toThrow();
  });

  it('throws on missing required vars', () => {
    expect(() => loadEnv({})).toThrow(/invalid environment/);
  });
});

describe('loadEnv — 2부 보안 가드 (§16)', () => {
  it('new auth defaults', () => {
    const env = loadEnv(valid);
    expect(env.JWT_ACCESS_TTL_SEC).toBe(900);
    expect(env.JWT_REFRESH_TTL_SEC).toBe(604800);
    expect(env.JWT_ADMIN_AUDIENCE).toBe('helpbee-admin');
    expect(env.AUTH_LOGIN_MAX_FAILS).toBe(10);
    expect(env.AUTH_LOCKOUT_WINDOW_SEC).toBe(900);
    expect(env.CORS_ALLOWLIST).toEqual([]);
  });

  it('CORS_ALLOWLIST csv → trimmed array (와일드카드는 운영에서 금지)', () => {
    expect(loadEnv({ ...valid, CORS_ALLOWLIST: 'https://a.com, https://b.com ,' }).CORS_ALLOWLIST).toEqual([
      'https://a.com',
      'https://b.com',
    ]);
  });

  it('rejects placeholder JWT_SECRET (§13 MUST)', () => {
    expect(() => loadEnv({ ...valid, JWT_SECRET: 'your_jwt_secret_here_' + 'x'.repeat(60) })).toThrow(
      /placeholder/i,
    );
  });

  it('rejects JWT_SECRET === REFRESH_TOKEN_PEPPER', () => {
    const same = 'z'.repeat(64);
    expect(() => loadEnv({ ...valid, JWT_SECRET: same, REFRESH_TOKEN_PEPPER: same })).toThrow(
      /differ/i,
    );
  });

  it('rejects AI_INTERNAL_HMAC_SECRET === JWT_SECRET', () => {
    const same = 'z'.repeat(64);
    expect(() => loadEnv({ ...valid, JWT_SECRET: same, AI_INTERNAL_HMAC_SECRET: same })).toThrow(
      /differ/i,
    );
  });
});
