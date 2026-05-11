import { sql } from 'drizzle-orm';
import { boolean, check, pgTable, text, timestamp, unique, uuid } from 'drizzle-orm/pg-core';

/**
 * AI 모델 메타 (OpenAI Vision / 자체 YOLO).
 * - provider: 'openai' | 'yolo' (CHECK 제약)
 * - dual-engine 식별의 단일 진실 소스. analyses.model_id로 FK.
 * - UNIQUE(provider, name, version): 같은 (provider, name, version) 조합은 1 row만.
 * - is_active: 동시 활성 여러 버전 가능 (canary/blue-green 운영)
 */
export const aiModels = pgTable(
  'ai_models',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    provider: text('provider').notNull(),
    name: text('name').notNull(),
    version: text('version').notNull(),
    releasedAt: timestamp('released_at', { withTimezone: true }),
    isActive: boolean('is_active').notNull().default(true),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    providerCheck: check('ai_models_provider_check', sql`${t.provider} IN ('openai', 'yolo')`),
    providerNameVersionUnique: unique('ai_models_provider_name_version_unique').on(
      t.provider,
      t.name,
      t.version,
    ),
  }),
);

export type AiModel = typeof aiModels.$inferSelect;
export type NewAiModel = typeof aiModels.$inferInsert;
