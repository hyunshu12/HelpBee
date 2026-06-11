/**
 * Subscriptions 라우트 (backend-design §11). plan을 단일 진실 소스로 노출(폴백·quota 게이트).
 * - GET /me (auth): 현재 plan/features. GET /plans (public): 정적 카탈로그.
 * - POST /webhook: 서명 가드(app.ts에서 라우트 최상단 마운트) 통과분만. MVP inert(ack만, plan 미변경).
 */
import { Hono } from 'hono';

import { ok } from '../lib/envelope';
import { PLAN_CATALOG } from '../schemas/subscriptions';
import { resolveUserPlan, type SubscriptionRow } from '../services/subscription-service';

export type SubscriptionsDeps = {
  getSubscription(userId: string): Promise<SubscriptionRow | undefined>;
  audit(entry: {
    actorId: string | null;
    action: string;
    entity: string;
    entityId: string | null;
    metadata?: Record<string, unknown> | null;
    ip: string | null;
    userAgent: string | null;
  }): Promise<void>;
};

export function subscriptionsRoutes(deps: SubscriptionsDeps) {
  const app = new Hono();

  // GET /v1/subscriptions/me (auth는 app.ts protectedMount)
  app.get('/me', async (c) => {
    const userId = c.get('userId') as string;
    const sub = await deps.getSubscription(userId);
    const resolved = resolveUserPlan(sub);
    return ok(c, {
      plan: resolved.plan,
      status: resolved.status,
      trialEndsAt: resolved.trialEndsAt,
      currentPeriodEnd: resolved.currentPeriodEnd,
      features: {
        openaiFallback: resolved.openaiFallback,
        monthlyAnalysisQuota: resolved.monthlyAnalysisQuota,
      },
    });
  });

  // GET /v1/subscriptions/plans (public — app.ts에서 인증 밖 마운트)
  app.get('/plans', (c) => ok(c, PLAN_CATALOG));

  // POST /v1/subscriptions/webhook (서명 가드 통과 후) — MVP inert
  app.post('/webhook', async (c) => {
    const body = (c.get('webhookBody') ?? {}) as { eventType?: string; eventId?: string };
    await deps.audit({
      actorId: null,
      action: 'subscription.webhook',
      entity: 'subscription',
      entityId: null,
      metadata: { eventType: body.eventType ?? null, eventId: body.eventId ?? null }, // PII/카드 금지
      ip: c.req.header('x-forwarded-for')?.split(',')[0]?.trim() ?? null,
      userAgent: c.req.header('user-agent') ?? null,
    });
    // MVP: 서명·타임스탬프 검증만 통과시키고 plan mutation은 Phase 2(inert).
    return ok(c, { received: true });
  });

  return app;
}
