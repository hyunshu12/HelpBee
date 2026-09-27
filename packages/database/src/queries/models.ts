import { and, eq, ne } from 'drizzle-orm';

import type { Database } from '../client';
import { type AiModel, aiModels } from '../schema/aiModels';

/** 2-stage 재설계(v0.2.0~) ai_models.name — 스펙 §8-1. */
export const TWO_STAGE_MODEL_NAME = 'helpbee-two-stage';

/**
 * 결과를 낸 파이프라인. 'two-stage' = AI 응답에 model_versions 가 있는 새 계약,
 * 'v1' = 구 계약(단일 YOLO / OpenAI).
 */
export type ModelPipeline = 'two-stage' | 'v1';

/**
 * engine_used(provider) → 활성 ai_models 행 1개.
 * AI 응답 engine_used('yolo'|'openai')를 provider로 매핑해 analyses.model_id를 채운다.
 * provider+is_active 조회(느슨) — name/version 표기 변화에 견고(리뷰 권고).
 *
 * 같은 provider(yolo)에 구 v0.1.0 행과 two-stage 행이 공존하므로 pipeline으로 가른다:
 * - 'two-stage': name = helpbee-two-stage
 * - 'v1'(기본): name ≠ helpbee-two-stage (기존 동작 유지)
 */
export async function resolveActiveModel(
  db: Database,
  provider: 'openai' | 'yolo',
  pipeline: ModelPipeline = 'v1',
): Promise<AiModel | undefined> {
  const nameCond =
    pipeline === 'two-stage'
      ? eq(aiModels.name, TWO_STAGE_MODEL_NAME)
      : ne(aiModels.name, TWO_STAGE_MODEL_NAME);
  const rows = await db
    .select()
    .from(aiModels)
    .where(and(eq(aiModels.provider, provider), eq(aiModels.isActive, true), nameCond))
    .limit(1);
  return rows[0];
}
