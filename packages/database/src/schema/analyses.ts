import { sql } from 'drizzle-orm';
import {
  check,
  index,
  integer,
  jsonb,
  pgTable,
  smallint,
  text,
  timestamp,
  unique,
  uuid,
} from 'drizzle-orm/pg-core';

import { timestamps } from './_shared';
import { aiModels } from './aiModels';
import { analysisImages } from './analysisImages';
import { hives } from './hives';

/**
 * 분석 결과 (dual-engine 핵심).
 *
 * - UNIQUE(image_id, model_id): 같은 이미지에 같은 모델로 분석 1번. 다른 모델은 별 row.
 *   → 한 이미지에 OpenAI 결과 1 row + YOLO 결과 1 row가 공존.
 *   → 'engine' 컬럼은 두지 않음. ai_models.provider로 식별.
 * - status: 'pending' | 'success' | 'failed' (CHECK)
 * - varroa_infection_risk: 0~100 smallint (CHECK)
 * - overall_health: 'healthy' | 'warning' | 'critical' (CHECK, PG enum 사용 X — 마이그레이션 유연성)
 * - raw_response: 엔진별 원본 응답. ⚠️ EXIF/PII는 apps/api에서 사전 제거된 상태여야 함.
 * - hard 보존 (법적/통계 추적)
 */
export const analyses = pgTable(
  'analyses',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    hiveId: uuid('hive_id')
      .notNull()
      .references(() => hives.id, { onDelete: 'cascade' }),
    imageId: uuid('image_id')
      .notNull()
      .references(() => analysisImages.id, { onDelete: 'cascade' }),
    modelId: uuid('model_id')
      .notNull()
      .references(() => aiModels.id, { onDelete: 'restrict' }),
    status: text('status').notNull().default('pending'),
    varroaInfectionRisk: smallint('varroa_infection_risk'),
    estimatedVarroaCount: integer('estimated_varroa_count'),
    overallHealth: text('overall_health'),
    rawResponse: jsonb('raw_response'),
    latencyMs: integer('latency_ms'),
    error: text('error'),
    analyzedAt: timestamp('analyzed_at', { withTimezone: true }),
    ...timestamps,
  },
  (t) => ({
    imageModelUnique: unique('analyses_image_model_unique').on(t.imageId, t.modelId),
    hiveIdIdx: index('analyses_hive_id_idx').on(t.hiveId),
    imageIdIdx: index('analyses_image_id_idx').on(t.imageId),
    statusCheck: check(
      'analyses_status_check',
      sql`${t.status} IN ('pending', 'success', 'failed')`,
    ),
    riskCheck: check(
      'analyses_risk_check',
      sql`${t.varroaInfectionRisk} IS NULL OR (${t.varroaInfectionRisk} >= 0 AND ${t.varroaInfectionRisk} <= 100)`,
    ),
    healthCheck: check(
      'analyses_overall_health_check',
      sql`${t.overallHealth} IS NULL OR ${t.overallHealth} IN ('healthy', 'warning', 'critical')`,
    ),
  }),
);

export type Analysis = typeof analyses.$inferSelect;
export type NewAnalysis = typeof analyses.$inferInsert;

export const OVERALL_HEALTH_VALUES = ['healthy', 'warning', 'critical'] as const;
export type OverallHealth = (typeof OVERALL_HEALTH_VALUES)[number];

export const ANALYSIS_STATUS_VALUES = ['pending', 'success', 'failed'] as const;
export type AnalysisStatus = (typeof ANALYSIS_STATUS_VALUES)[number];
