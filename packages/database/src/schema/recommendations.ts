import { sql } from 'drizzle-orm';
import { check, index, integer, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

import { analyses } from './analyses';

/**
 * 분석별 권장 조치.
 * analyses.raw_response에 묶어두지 않고 분리 — i18n / 검색 / 표시 순서 제어 용도.
 * severity: 'info' | 'warn' | 'danger' (CHECK)
 */
export const recommendations = pgTable(
  'recommendations',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    analysisId: uuid('analysis_id')
      .notNull()
      .references(() => analyses.id, { onDelete: 'cascade' }),
    order: integer('order').notNull().default(0),
    content: text('content').notNull(),
    severity: text('severity').notNull().default('info'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    analysisIdIdx: index('recommendations_analysis_id_idx').on(t.analysisId),
    severityCheck: check(
      'recommendations_severity_check',
      sql`${t.severity} IN ('info', 'warn', 'danger')`,
    ),
  }),
);

export type Recommendation = typeof recommendations.$inferSelect;
export type NewRecommendation = typeof recommendations.$inferInsert;

export const RECOMMENDATION_SEVERITY_VALUES = ['info', 'warn', 'danger'] as const;
export type RecommendationSeverity = (typeof RECOMMENDATION_SEVERITY_VALUES)[number];
