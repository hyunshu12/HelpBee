import { Hono } from 'hono';
import { describe, expect, it, vi } from 'vitest';

import { errorHandler } from '../middleware/error-handler';
import { requestId } from '../middleware/request-id';
import { subscriptionsRoutes, type SubscriptionsDeps } from './subscriptions';

function makeApp(deps: SubscriptionsDeps, userId = 'u1', webhookBody?: unknown) {
  const app = new Hono();
  app.onError(errorHandler);
  app.use('*', requestId);
  app.use('/me', async (c, next) => {
    c.set('userId', userId);
    await next();
  });
  app.use('/webhook', async (c, next) => {
    c.set('webhookBody', webhookBody ?? {});
    await next();
  });
  app.route('/', subscriptionsRoutes(deps));
  return app;
}

const deps = (): SubscriptionsDeps => ({
  getSubscription: vi.fn(async () => undefined),
  audit: vi.fn(async () => undefined),
});

describe('GET /subscriptions/me', () => {
  it('free 기본 (row 없음)', async () => {
    const res = await makeApp(deps()).request('/me');
    expect(res.status).toBe(200);
    const { data } = await res.json();
    expect(data.plan).toBe('free');
    expect(data.features).toEqual({ openaiFallback: false, monthlyAnalysisQuota: 4 });
  });

  it('유료 active → 폴백/무제한', async () => {
    const d = deps();
    d.getSubscription = vi.fn(async () => ({
      plan: 'pro',
      status: 'active',
      trialEndsAt: null,
      currentPeriodEnd: null,
    }));
    const { data } = await (await makeApp(d).request('/me')).json();
    expect(data.features.openaiFallback).toBe(true);
    expect(data.features.monthlyAnalysisQuota).toBeNull();
  });
});

describe('GET /subscriptions/plans', () => {
  it('정적 카탈로그 (public)', async () => {
    const res = await makeApp(deps()).request('/plans');
    expect(res.status).toBe(200);
    const { data } = await res.json();
    expect(data.plans).toHaveLength(3);
    expect(data.plans[0].id).toBe('free');
  });
});

describe('POST /subscriptions/webhook (inert)', () => {
  it('200 received + audit (PII 없는 메타만)', async () => {
    const d = deps();
    const res = await makeApp(d, 'u1', { eventType: 'payment.succeeded', eventId: 'evt_1', card: '4242' }).request(
      '/webhook',
      { method: 'POST' },
    );
    expect(res.status).toBe(200);
    expect((await res.json()).data.received).toBe(true);
    expect(d.audit).toHaveBeenCalledWith(
      expect.objectContaining({
        action: 'subscription.webhook',
        metadata: { eventType: 'payment.succeeded', eventId: 'evt_1' }, // card 미포함
      }),
    );
  });
});
