import { describe, expect, it } from 'vitest';

import { resolveUserPlan } from './subscription-service';

describe('resolveUserPlan', () => {
  it('row 없음 → free/active, 폴백 X, quota 4', () => {
    expect(resolveUserPlan(undefined)).toMatchObject({
      plan: 'free',
      status: 'active',
      openaiFallback: false,
      monthlyAnalysisQuota: 4,
    });
  });

  it('유료(basic)+active → 폴백 O, quota 무제한(null)', () => {
    const r = resolveUserPlan({
      plan: 'basic',
      status: 'active',
      trialEndsAt: null,
      currentPeriodEnd: null,
    });
    expect(r.openaiFallback).toBe(true);
    expect(r.monthlyAnalysisQuota).toBeNull();
  });

  it('유료라도 status≠active → 폴백 X, quota 4 (권한 즉시 회수)', () => {
    const r = resolveUserPlan({
      plan: 'pro',
      status: 'cancelled',
      trialEndsAt: null,
      currentPeriodEnd: null,
    });
    expect(r.openaiFallback).toBe(false);
    expect(r.monthlyAnalysisQuota).toBe(4);
    expect(r.plan).toBe('pro'); // 라벨은 유지
  });

  it('알 수 없는 plan/status → free/active 안전망', () => {
    const r = resolveUserPlan({
      plan: 'enterprise' as never,
      status: 'weird' as never,
      trialEndsAt: null,
      currentPeriodEnd: null,
    });
    expect(r.plan).toBe('free');
    expect(r.status).toBe('active');
  });

  it('날짜는 ISO 직렬화', () => {
    const r = resolveUserPlan({
      plan: 'basic',
      status: 'active',
      trialEndsAt: new Date('2026-07-01T00:00:00Z'),
      currentPeriodEnd: new Date('2026-08-01T00:00:00Z'),
    });
    expect(r.trialEndsAt).toBe('2026-07-01T00:00:00.000Z');
    expect(r.currentPeriodEnd).toBe('2026-08-01T00:00:00.000Z');
  });
});
