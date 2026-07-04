/**
 * @helpbee/database — public 진입점.
 *
 * 사용 예:
 *   import { db, schema, queries } from '@helpbee/database';
 *   const list = await queries.hives.listHivesByUser(db, userId);
 *   await db.insert(schema.users).values({ ... });
 *
 * downstream(@apps/api, @apps/admin, @apps/ai)은 반드시 이 패키지의 export만 import한다.
 * 직접 pg/postgres 인스턴스 생성 금지.
 */

export { db, type Database } from './client';

import * as schemaNS from './schema';
import * as queriesNS from './queries';

export { schemaNS as schema };
export { queriesNS as queries };

// Drizzle 추론 타입 재수출 — packages/types가 이걸 다시 export한다.
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
  Inquiry,
  NewInquiry,
  InquiryStatus,
} from './schema';

// enum-like value arrays (런타임 사용)
export {
  ANALYSIS_STATUS_VALUES,
  OVERALL_HEALTH_VALUES,
  RECOMMENDATION_SEVERITY_VALUES,
  SUBSCRIPTION_PLAN_VALUES,
  SUBSCRIPTION_STATUS_VALUES,
  INQUIRY_STATUS_VALUES,
} from './schema';
