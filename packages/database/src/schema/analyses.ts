import { sql } from 'drizzle-orm';
import {
  check,
  index,
  integer,
  jsonb,
  numeric,
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
 * - vdi, vdi_ci_low/high, bee_total, bee_infested: two-stage 행만 채움(구 YOLO/OpenAI 행은 NULL).
 *   트렌드는 two-stage=vdi, 구 row=varroa_infection_risk 로 분리(단위 상이, coalesce 금지).
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
    // ── two-stage 계약 (스펙 v2.2 §3·§8-1) — 전부 nullable, 구 row는 NULL ──
    // vdi: Rogan–Gladen 보정 지수(%). numeric → 드라이버는 문자열로 반환(API가 number로 직렬화).
    vdi: numeric('vdi', { precision: 6, scale: 3 }),
    vdiCiLow: numeric('vdi_ci_low', { precision: 6, scale: 3 }),
    vdiCiHigh: numeric('vdi_ci_high', { precision: 6, scale: 3 }),
    // 원시 카운트: N장 합산(읽기 시 집계)의 원천 — 저장된 vdi는 clip돼 역산 불가.
    beeTotal: integer('bee_total'),
    beeInfested: integer('bee_infested'),
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
