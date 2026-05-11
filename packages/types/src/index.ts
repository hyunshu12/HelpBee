/**
 * @helpbee/types — 공유 도메인 타입.
 *
 * 정책:
 *   - DB 컬럼과 동일한 모델은 @helpbee/database의 Drizzle 추론 타입을 그대로 재수출한다.
 *     → 직접 interface 중복 정의 금지 (drift 방지).
 *   - API DTO / 응답 봉투 / 통신 전용 타입은 이 파일 하단에 직접 정의한다.
 *
 * 변경 시:
 *   - DB 스키마 변경 → drizzle-kit generate → 자동 반영
 *   - API DTO 변경 → 이 파일 + Bruno 컬렉션 + apps/ai Pydantic 미러 동시 갱신
 */

// ─────────────────── DB-inferred types (DO NOT redefine) ───────────────────
export type {
  User,
  NewUser,
  RefreshToken,
  NewRefreshToken,
  Hive,
  NewHive,
  AnalysisImage,
  NewAnalysisImage,
  AiModel,
  NewAiModel,
  Analysis,
  NewAnalysis,
  AnalysisStatus,
  OverallHealth,
  Recommendation,
  NewRecommendation,
  RecommendationSeverity,
  Subscription,
  NewSubscription,
  SubscriptionPlan,
  SubscriptionStatus,
  AuditLog,
  NewAuditLog,
} from '@helpbee/database';

export {
  ANALYSIS_STATUS_VALUES,
  OVERALL_HEALTH_VALUES,
  RECOMMENDATION_SEVERITY_VALUES,
  SUBSCRIPTION_PLAN_VALUES,
  SUBSCRIPTION_STATUS_VALUES,
} from '@helpbee/database';

// ─────────────────── API DTOs (HTTP wire-level) ───────────────────

/**
 * 분석 요청 페이로드 (POST /v1/analyses).
 */
export interface AnalysisRequest {
  hiveId: string;
  imageId: string;
  engine?: 'auto' | 'openai' | 'yolo' | 'dual';
}

/**
 * Dual-engine 응답 (관리자 / 검증 채널).
 * primary/secondary가 각각 한 모델의 결과를 담고 agreement가 일치도 메트릭.
 */
export interface DualAnalysisResponse<TPrimary, TSecondary = TPrimary> {
  primary: TPrimary;
  secondary: TSecondary;
  agreement: {
    tierMatch: boolean;
    riskDiff: number;
  };
}

/**
 * 표준 응답 봉투 (apps/api 모든 성공 응답).
 */
export interface ApiEnvelope<T> {
  data: T;
  meta: {
    requestId: string;
    timestamp: string;
    pagination?: {
      page: number;
      pageSize: number;
      total: number;
    };
  };
}

/**
 * RFC 7807 Problem Details (apps/api 모든 에러 응답).
 */
export interface ProblemDetails {
  type: string;
  title: string;
  status: number;
  code: string;
  detail?: string;
  instance?: string;
  requestId?: string;
}
