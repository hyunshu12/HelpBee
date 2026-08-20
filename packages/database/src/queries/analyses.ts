import { and, asc, desc, eq, inArray, isNull, sql } from 'drizzle-orm';

import type { Database } from '../client';
import { type Analysis, analyses, type NewAnalysis } from '../schema/analyses';
import { hives } from '../schema/hives';
import { recommendations } from '../schema/recommendations';

/** 응답용 권장 조치(표시 순서 order 오름차순). id/analysisId/createdAt은 제외. */
export type AnalysisRecommendation = { order: number; content: string; severity: string };

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

/**
 * 사용자의 **모든 벌통**에 걸친 분석 이력 (최신순) — 모바일 "진단 이력" 탭용.
 * listAnalysesByHiveForUser와 같은 INNER JOIN + userId 필터라 IDOR 차단은 동일하고,
 * soft-deleted 벌통(deletedAt)의 분석은 제외된다.
 *
 * 정렬이 `desc(analyzedAt)` 한 컬럼이면 안 되는 이유:
 * ① analyzedAt은 nullable(pending) → PG 기본 DESC는 NULL을 맨 앞에 올려 미완료 건이
 *    최신 결과를 밀어낸다 → NULLS LAST.
 * ② 한 벌통에 같은 analyzedAt이 여러 건 존재한다(배치 시드/연속 분석 실측 확인).
 *    tie-breaker가 없으면 offset 페이지네이션에서 같은 행이 중복/누락된다
 *    → createdAt, id까지 내려 전순서(total order)를 만든다.
 */
export async function listAnalysesForUser(
  db: Database,
  userId: string,
  opts: { limit?: number; offset?: number } = {},
): Promise<Analysis[]> {
  const limit = Math.min(opts.limit ?? 50, 100);
  const offset = Math.max(opts.offset ?? 0, 0);
  const rows = await db
    .select({ a: analyses })
    .from(analyses)
    .innerJoin(hives, eq(hives.id, analyses.hiveId))
    .where(and(eq(hives.userId, userId), isNull(hives.deletedAt)))
    .orderBy(
      sql`${analyses.analyzedAt} DESC NULLS LAST`,
      desc(analyses.createdAt),
      desc(analyses.id),
    )
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

/**
 * 분석 ID들의 권장 조치를 order 오름차순으로 조회 → {analysisId: items[]} Map.
 * GET /:id 등 응답 조립 시 join용. 소유권 검증은 호출부(분석 자체 조회)에서 이미 수행.
 * ids가 비면 빈 Map 반환(쿼리 스킵).
 */
export async function listRecommendationsByAnalysisIds(
  db: Database,
  analysisIds: string[],
): Promise<Map<string, AnalysisRecommendation[]>> {
  const out = new Map<string, AnalysisRecommendation[]>();
  if (analysisIds.length === 0) return out;
  const rows = await db
    .select({
      analysisId: recommendations.analysisId,
      order: recommendations.order,
      content: recommendations.content,
      severity: recommendations.severity,
    })
    .from(recommendations)
    .where(inArray(recommendations.analysisId, analysisIds))
    .orderBy(asc(recommendations.order));
  for (const r of rows) {
    const list = out.get(r.analysisId);
    const item = { order: r.order, content: r.content, severity: r.severity };
    if (list) list.push(item);
    else out.set(r.analysisId, [item]);
  }
  return out;
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

/**
 * 재시도 후보: 해당 이미지의 failed 분석(소유권 검증).
 * success가 없을 때만 호출됨(라우트가 success short-circuit 먼저 수행).
 * 있으면 새 row insert 대신 제자리 UPDATE(retryFailedAnalysis)로 처리.
 */
export async function findFailedAnalysisByImage(
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
        eq(analyses.status, 'failed'),
        eq(hives.userId, userId),
        isNull(hives.deletedAt),
      ),
    )
    .orderBy(desc(analyses.analyzedAt))
    .limit(1);
  return rows[0]?.a;
}

export type RetryAnalysisInput = {
  analysisId: string;
  modelId: string;
  analysis: Omit<NewAnalysis, 'hiveId' | 'imageId' | 'modelId'>;
  recommendations: { order: number; content: string; severity: string }[];
};

/**
 * failed 분석 1행을 제자리 UPDATE(재시도) + recommendations 교체 (한 트랜잭션).
 * UNIQUE(image_id, model_id) 하 재분석=새 image_id 원칙의 예외 — **failed 행만** 재실행.
 *
 * - id 보존: 같은 row를 갱신(status/risk/health/rawResponse/latency/error/analyzedAt/updatedAt).
 * - CAS: WHERE id=? AND status='failed' — 동시 재시도의 loser는 0행 갱신 →
 *   winner가 확정한 현재 행을 재조회해 그대로 반환(중복 write·중복 recommendations 방지).
 * - recommendations는 전량 삭제 후 재삽입(순서·내용 갱신). 실패 재시도면 빈 배열 → 0행 남음.
 * - updatedAt은 명시 set(0.29.5는 $onUpdate 미지원, _shared.ts 참고).
 */
export async function retryFailedAnalysis(
  db: Database,
  input: RetryAnalysisInput,
): Promise<Analysis> {
  return db.transaction(async (tx) => {
    const updated = await tx
      .update(analyses)
      .set({
        modelId: input.modelId,
        status: input.analysis.status,
        varroaInfectionRisk: input.analysis.varroaInfectionRisk,
        estimatedVarroaCount: input.analysis.estimatedVarroaCount,
        overallHealth: input.analysis.overallHealth,
        rawResponse: input.analysis.rawResponse,
        latencyMs: input.analysis.latencyMs,
        error: input.analysis.error,
        analyzedAt: input.analysis.analyzedAt,
        updatedAt: new Date(),
      })
      .where(and(eq(analyses.id, input.analysisId), eq(analyses.status, 'failed')))
      .returning();

    const fresh = updated[0];
    if (!fresh) {
      // CAS 패자: winner가 이미 확정 — 현재 행을 그대로 반환(재조회, 재write 안 함)
      const [current] = await tx
        .select()
        .from(analyses)
        .where(eq(analyses.id, input.analysisId))
        .limit(1);
      if (!current) throw new Error('[retryFailedAnalysis] row disappeared during retry');
      return current;
    }

    // recommendations 교체: 기존 삭제 후 재삽입
    await tx.delete(recommendations).where(eq(recommendations.analysisId, fresh.id));
    if (input.recommendations.length > 0) {
      await tx
        .insert(recommendations)
        .values(input.recommendations.map((r) => ({ ...r, analysisId: fresh.id })));
    }
    return fresh;
  });
}
