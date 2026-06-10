import { and, eq } from 'drizzle-orm';

import type { Database } from '../client';
import { type AiModel, aiModels } from '../schema/aiModels';

/**
 * engine_used(provider) → 활성 ai_models 행 1개.
 * AI 응답 engine_used('yolo'|'openai')를 provider로 매핑해 analyses.model_id를 채운다.
 * provider+is_active 조회(느슨) — name/version 표기 변화에 견고(리뷰 권고).
 */
export async function resolveActiveModel(
  db: Database,
  provider: 'openai' | 'yolo',
): Promise<AiModel | undefined> {
  const rows = await db
    .select()
    .from(aiModels)
    .where(and(eq(aiModels.provider, provider), eq(aiModels.isActive, true)))
    .limit(1);
  return rows[0];
}
