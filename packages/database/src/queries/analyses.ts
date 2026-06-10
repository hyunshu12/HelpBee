import { and, desc, eq, isNull } from 'drizzle-orm';

import type { Database } from '../client';
import { type Analysis, analyses, type NewAnalysis } from '../schema/analyses';
import { hives } from '../schema/hives';
import { recommendations } from '../schema/recommendations';

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
 * @deprecated userId 필터가 없어 IDOR 위험. listAnalysesByHiveForUser 사용.
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

export type SingleAnalysisInput = {
  hiveId: string;
  imageId: string;
  modelId: string;
  analysis: Omit<NewAnalysis, 'hiveId' | 'imageId' | 'modelId'>;
  recommendations: { order: number; content: string; severity: string }[];
};

/**
 * 단일 엔진 분석 1행 + recommendations N행을 한 트랜잭션에 저장 (store-one-engine).
 * - onConflictDoNothing(target [imageId, modelId]): 기존 success 행을 **절대 덮어쓰지 않음**.
 *   (재분석=새 image_id 정책 + 라우트 멱등 short-circuit과 함께 중복 추론/과금 방지)
 * - 신규 삽입일 때만 recommendations 삽입(기존 행 보존). 충돌 시 기존 행 반환.
 */
export async function createSingleAnalysis(
  db: Database,
  input: SingleAnalysisInput,
): Promise<Analysis> {
  return db.transaction(async (tx) => {
    const inserted = await tx
      .insert(analyses)
      .values({
        ...input.analysis,
        hiveId: input.hiveId,
        imageId: input.imageId,
        modelId: input.modelId,
      })
      .onConflictDoNothing({ target: [analyses.imageId, analyses.modelId] })
      .returning();

    const fresh = inserted[0];
    if (fresh) {
      if (input.recommendations.length > 0) {
        await tx
          .insert(recommendations)
          .values(input.recommendations.map((r) => ({ ...r, analysisId: fresh.id })));
      }
      return fresh;
    }

    // 충돌(이미 존재): 기존 행을 그대로 반환 (덮어쓰기 X)
    const [existing] = await tx
      .select()
      .from(analyses)
      .where(and(eq(analyses.imageId, input.imageId), eq(analyses.modelId, input.modelId)))
      .limit(1);
    if (!existing) {
      throw new Error('[createSingleAnalysis] conflict but no existing row');
    }
    return existing;
  });
}

/**
 * Hive별 분석 이력 (소유권 검증 포함, 최신순). getHiveTrend의 INNER JOIN 패턴 재사용.
 * 다른 user의 hiveId면 빈 배열 → IDOR 차단.
 */
export async function listAnalysesByHiveForUser(
  db: Database,
  hiveId: string,
  userId: string,
  opts: { limit?: number; offset?: number } = {},
): Promise<Analysis[]> {
  const limit = Math.min(opts.limit ?? 50, 100);
  const offset = Math.max(opts.offset ?? 0, 0);
  const rows = await db
    .select({ a: analyses })
    .from(analyses)
    .innerJoin(hives, eq(hives.id, analyses.hiveId))
    .where(and(eq(analyses.hiveId, hiveId), eq(hives.userId, userId), isNull(hives.deletedAt)))
    .orderBy(desc(analyses.analyzedAt))
    .limit(limit)
    .offset(offset);
  return rows.map((r) => r.a);
}

/** 단일 분석 조회 (소유권 검증). 비소유/없음 → undefined → 라우트 404. */
export async function getAnalysisByIdForUser(
  db: Database,
  analysisId: string,
  userId: string,
): Promise<Analysis | undefined> {
  const rows = await db
    .select({ a: analyses })
    .from(analyses)
    .innerJoin(hives, eq(hives.id, analyses.hiveId))
    .where(and(eq(analyses.id, analysisId), eq(hives.userId, userId), isNull(hives.deletedAt)))
    .limit(1);
  return rows[0]?.a;
}

/** 멱등 short-circuit용: 해당 이미지의 success 분석(소유권 검증). 있으면 재추론 스킵. */
export async function findSuccessAnalysisByImage(
  db: Database,
  imageId: string,
  userId: string,
): Promise<Analysis | undefined> {
  const rows = await db
    .select({ a: analyses })
    .from(analyses)
    .innerJoin(hives, eq(hives.id, analyses.hiveId))
    .where(
      and(
        eq(analyses.imageId, imageId),
        eq(analyses.status, 'success'),
        eq(hives.userId, userId),
        isNull(hives.deletedAt),
      ),
    )
    .orderBy(desc(analyses.analyzedAt))
    .limit(1);
  return rows[0]?.a;
}
