/**
 * plan 판정 단일 함수 (backend-design §11.3). 폴백·quota 게이트의 근원.
 * 규칙: ① row 없는 신규=free/active. ② 유료라도 status≠active면 폴백·무제한 미적용(결제 실패/취소 즉시 회수).
 * 순수 함수(테스트 용이) — DB 조회는 호출부(route deps.getSubscription).
 */
export type Plan = 'free' | 'basic' | 'pro';
export type SubStatus = 'active' | 'inactive' | 'cancelled';

export type SubscriptionRow = {
  plan: string;
  status: string;
  trialEndsAt: Date | null;
  currentPeriodEnd: Date | null;
};

export type ResolvedPlan = {
  plan: Plan;
  status: SubStatus;
  openaiFallback: boolean;
  monthlyAnalysisQuota: number | null; // free 또는 비active=4, 유료-active=null(무제한)
  trialEndsAt: string | null;
  currentPeriodEnd: string | null;
};

const FREE_MONTHLY_QUOTA = 4;

export function resolveUserPlan(sub?: SubscriptionRow | null): ResolvedPlan {
  const plan = (['free', 'basic', 'pro'].includes(sub?.plan ?? '') ? sub!.plan : 'free') as Plan;
  const status = (['active', 'inactive', 'cancelled'].includes(sub?.status ?? '')
    ? sub!.status
    : 'active') as SubStatus;
  const active = status === 'active';
  const paid = plan !== 'free' && active;
  return {
    plan,
    status,
    openaiFallback: paid,
    monthlyAnalysisQuota: paid ? null : FREE_MONTHLY_QUOTA,
    trialEndsAt: sub?.trialEndsAt ? sub.trialEndsAt.toISOString() : null,
    currentPeriodEnd: sub?.currentPeriodEnd ? sub.currentPeriodEnd.toISOString() : null,
  };
}
