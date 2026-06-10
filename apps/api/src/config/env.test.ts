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
