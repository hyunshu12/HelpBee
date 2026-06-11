import { describe, expect, it } from 'vitest';

import { idParamSchema, normalizeEmail, paginationSchema, uuid } from './common';
import { loginSchema, signupSchema, toPublicUser } from './auth';

describe('normalizeEmail', () => {
  it('trims, NFKC, lowercases', () => {
    expect(normalizeEmail('  Foo@Bar.COM  ')).toBe('foo@bar.com');
  });
});

describe('signupSchema', () => {
  it('accepts valid + normalizes email', () => {
    const r = signupSchema.parse({ email: '  USER@Ex.com ', password: '0123456789', name: '홍길동' });
    expect(r.email).toBe('user@ex.com');
    expect(r.name).toBe('홍길동');
  });

  it('rejects unknown keys (.strict — Mass Assignment)', () => {
    expect(
      signupSchema.safeParse({
        email: 'a@b.com',
        password: '0123456789',
        name: 'n',
        role: 'admin', // 주입 시도
      }).success,
    ).toBe(false);
  });

  it('rejects short password (<10)', () => {
    expect(signupSchema.safeParse({ email: 'a@b.com', password: 'short', name: 'n' }).success).toBe(
      false,
    );
  });

  it('rejects invalid email', () => {
    expect(
      signupSchema.safeParse({ email: 'not-an-email', password: '0123456789', name: 'n' }).success,
    ).toBe(false);
  });
});

describe('loginSchema', () => {
  it('password length only (min 1) — does not enforce signup policy', () => {
    expect(loginSchema.safeParse({ email: 'a@b.com', password: 'x' }).success).toBe(true);
  });
});

describe('common schemas', () => {
  it('uuid regex accepts/rejects', () => {
    expect(uuid.safeParse('00000000-0000-4000-8000-000000000001').success).toBe(true);
    expect(uuid.safeParse('nope').success).toBe(false);
  });

  it('paginationSchema defaults + clamps', () => {
    expect(paginationSchema.parse({})).toEqual({ limit: 50, offset: 0 });
    expect(paginationSchema.safeParse({ limit: 101 }).success).toBe(false);
    expect(paginationSchema.safeParse({ offset: 99999 }).success).toBe(false);
  });

  it('idParamSchema strict uuid', () => {
    expect(idParamSchema.safeParse({ id: '00000000-0000-4000-8000-000000000001' }).success).toBe(
      true,
    );
    expect(idParamSchema.safeParse({ id: 'x' }).success).toBe(false);
  });
});

describe('toPublicUser', () => {
  it('projects without password_hash; emailVerified derived', () => {
    const pub = toPublicUser({
      id: 'u1',
      email: 'a@b.com',
      name: 'n',
      role: 'user',
      emailVerifiedAt: null,
      createdAt: new Date('2026-06-11T00:00:00Z'),
    });
    expect(pub).toEqual({
      id: 'u1',
      email: 'a@b.com',
      name: 'n',
      role: 'user',
      emailVerified: false,
      createdAt: '2026-06-11T00:00:00.000Z',
    });
    expect((pub as Record<string, unknown>).passwordHash).toBeUndefined();
  });

  it('emailVerified true when timestamp present', () => {
    const pub = toPublicUser({
      id: 'u1',
      email: 'a@b.com',
      name: 'n',
      role: 'admin',
      emailVerifiedAt: new Date(),
      createdAt: new Date(),
    });
    expect(pub.emailVerified).toBe(true);
    expect(pub.role).toBe('admin');
  });
});
