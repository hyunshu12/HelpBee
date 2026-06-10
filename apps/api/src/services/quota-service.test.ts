import { describe, expect, it } from 'vitest';

import { AppError } from '../lib/error-codes';
import { kstMonthKey, refund, reserve, secondsUntilKstMonthEnd } from './quota-service';

class FakeRedis {
  store = new Map<string, number>();
  ttls = new Map<string, number>();
  async incr(k: string) {
    const v = (this.store.get(k) ?? 0) + 1;
    this.store.set(k, v);
    return v;
  }
  async decr(k: string) {
    const v = (this.store.get(k) ?? 0) - 1;
    this.store.set(k, v);
    return v;
  }
  async expire(k: string, s: number) {
    this.ttls.set(k, s);
    return 1;
  }
  async ttl(k: string) {
    return this.ttls.has(k) ? (this.ttls.get(k) as number) : -1;
  }
}

const NOW = new Date('2026-06-10T03:00:00Z');

describe('kstMonthKey', () => {
  it('uses KST month bucket', () => {
    expect(kstMonthKey('u1', NOW)).toBe('quota:u1:202606');
  });

  it('rolls to next month at KST boundary (UTC still prev month)', () => {
    // 2026-01-31 16:00 UTC = 2026-02-01 01:00 KST
    const t = new Date('2026-01-31T16:00:00Z');
    expect(kstMonthKey('u1', t)).toBe('quota:u1:202602');
  });
});

describe('secondsUntilKstMonthEnd', () => {
  it('is positive and within ~31 days', () => {
    const s = secondsUntilKstMonthEnd(NOW);
    expect(s).toBeGreaterThan(0);
    expect(s).toBeLessThan(32 * 24 * 3600);
  });
});

describe('reserve / refund (reserve-then-refund)', () => {
  it('reserves up to freeLimit and sets TTL on first', async () => {
    const r = new FakeRedis();
    expect(await reserve(r, 'u1', { freeLimit: 4, now: NOW })).toBe(1);
    expect(r.ttls.has('quota:u1:202606')).toBe(true);
    expect(await reserve(r, 'u1', { freeLimit: 4, now: NOW })).toBe(2);
  });

  it('throws QUOTA_EXCEEDED and rolls back the reservation past limit', async () => {
    const r = new FakeRedis();
    for (let i = 0; i < 4; i++) await reserve(r, 'u1', { freeLimit: 4, now: NOW });
    await expect(reserve(r, 'u1', { freeLimit: 4, now: NOW })).rejects.toBeInstanceOf(AppError);
    // 초과 시도는 무차감 — 카운트 4 유지
    expect(r.store.get('quota:u1:202606')).toBe(4);
  });

  it('refund decrements (failure path)', async () => {
    const r = new FakeRedis();
    await reserve(r, 'u1', { freeLimit: 4, now: NOW });
    await reserve(r, 'u1', { freeLimit: 4, now: NOW });
    await refund(r, 'u1', NOW);
    expect(r.store.get('quota:u1:202606')).toBe(1);
  });

  it('refund floors at 0', async () => {
    const r = new FakeRedis();
    await refund(r, 'u1', NOW);
    expect(r.store.get('quota:u1:202606')).toBe(0);
  });
});
