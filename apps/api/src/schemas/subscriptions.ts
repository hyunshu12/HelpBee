/**
 * Subscriptions 스키마 + 정적 plan 카탈로그 (backend-design §11.2).
 * 카탈로그는 코드 상수(가격 변경 시 배포로 갱신 — 1인 운영 적정).
 */
export const PLAN_VALUES = ['free', 'basic', 'pro'] as const;

export const PLAN_CATALOG = {
  plans: [
    { id: 'free', name: '무료', monthlyAnalysisQuota: 4, openaiFallback: false, priceKrwMonthly: 0 },
    {
      id: 'basic',
      name: '베이직',
      monthlyAnalysisQuota: null,
      openaiFallback: true,
      priceKrwMonthly: 9900,
    },
    {
      id: 'pro',
      name: '프로',
      monthlyAnalysisQuota: null,
      openaiFallback: true,
      priceKrwMonthly: 29900,
    },
  ],
} as const;
