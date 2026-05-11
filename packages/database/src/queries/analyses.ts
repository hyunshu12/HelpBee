import { desc, eq } from 'drizzle-orm';

import type { Database } from '../client';
import { type Analysis, analyses, type NewAnalysis } from '../schema/analyses';

export type DualAnalysisInput = {
  hiveId: string;
  imageId: string;
  openai: Omit<NewAnalysis, 'hiveId' | 'imageId'>;
  yolo: Omit<NewAnalysis, 'hiveId' | 'imageId'>;
};

/**
 * 같은 image_id에 두 엔진(openai, yolo) 결과를 한 트랜잭션에 insert.
 * UNIQUE(image_id, model_id) 제약 위반 시 onConflictDoUpdate로 멱등 처리.
 *
 * 두 row의 model_id는 호출자가 미리 ai_models 테이블에서 조회하여 주입.
 */
export async function createDualAnalysis(
  db: Database,
  input: DualAnalysisInput,
): Promise<{ openai: Analysis; yolo: Analysis }> {
  return db.transaction(async (tx) => {
    const [openai] = await tx
      .insert(analyses)
      .values({ ...input.openai, hiveId: input.hiveId, imageId: input.imageId })
      .onConflictDoUpdate({
        target: [analyses.imageId, analyses.modelId],
        set: {
          status: input.openai.status,
          varroaInfectionRisk: input.openai.varroaInfectionRisk,
          estimatedVarroaCount: input.openai.estimatedVarroaCount,
          overallHealth: input.openai.overallHealth,
          rawResponse: input.openai.rawResponse,
          latencyMs: input.openai.latencyMs,
          error: input.openai.error,
          analyzedAt: input.openai.analyzedAt,
        },
      })
      .returning();

    const [yolo] = await tx
      .insert(analyses)
      .values({ ...input.yolo, hiveId: input.hiveId, imageId: input.imageId })
      .onConflictDoUpdate({
        target: [analyses.imageId, analyses.modelId],
        set: {
          status: input.yolo.status,
          varroaInfectionRisk: input.yolo.varroaInfectionRisk,
          estimatedVarroaCount: input.yolo.estimatedVarroaCount,
          overallHealth: input.yolo.overallHealth,
          rawResponse: input.yolo.rawResponse,
          latencyMs: input.yolo.latencyMs,
          error: input.yolo.error,
          analyzedAt: input.yolo.analyzedAt,
        },
      })
      .returning();

    if (!openai || !yolo) {
      throw new Error('[createDualAnalysis] insert returned no rows');
    }
    return { openai, yolo };
  });
}

/**
 * Hive별 분석 이력 (최신순). dual-engine 환경에서는 모델별 row가 따로 나온다.
 */
export async function listAnalysesByHive(
  db: Database,
  hiveId: string,
  opts: { limit?: number; offset?: number } = {},
): Promise<Analysis[]> {
  const limit = opts.limit ?? 50;
  const offset = opts.offset ?? 0;
  return db
    .select()
    .from(analyses)
    .where(eq(analyses.hiveId, hiveId))
    .orderBy(desc(analyses.analyzedAt))
    .limit(limit)
    .offset(offset);
}
