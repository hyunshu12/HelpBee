import { and, avg, count, desc, eq, gte, isNull, lte, sql } from 'drizzle-orm';

import type { Database } from '../client';
import { analyses } from '../schema/analyses';
import { hives, type Hive } from '../schema/hives';

/**
 * 사용자별 hive 목록 (soft delete 제외, 최신 update 순).
 */
export async function listHivesByUser(db: Database, userId: string): Promise<Hive[]> {
  return db
    .select()
    .from(hives)
    .where(and(eq(hives.userId, userId), isNull(hives.deletedAt)))
    .orderBy(desc(hives.updatedAt));
}

/**
 * 특정 hive의 단일 조회 (소유 검증 포함, soft delete 제외).
 */
export async function getHiveByIdForUser(
  db: Database,
  hiveId: string,
  userId: string,
): Promise<Hive | undefined> {
  const rows = await db
    .select()
    .from(hives)
    .where(and(eq(hives.id, hiveId), eq(hives.userId, userId), isNull(hives.deletedAt)))
    .limit(1);
  return rows[0];
}

export type HiveTrendPoint = {
  bucket: string; // ISO date (UTC)
  avgRisk: number | null;
  analysisCount: number;
};

/**
 * Hive별 일자별 평균 risk 트렌드.
 * dual-engine 환경에서는 같은 image_id에 2 row가 있을 수 있어 단순 평균이 두 모델 합 평균이 됨.
 * 베타 비교 기간에는 이 동작 의도적 — 후속 PR에서 model_id로 분리 트렌드 함수 추가 예정.
 */
export async function getHiveTrend(
  db: Database,
  hiveId: string,
  from: Date,
  to: Date,
): Promise<HiveTrendPoint[]> {
  const bucket = sql<string>`to_char(date_trunc('day', ${analyses.analyzedAt}), 'YYYY-MM-DD')`;
  const rows = await db
    .select({
      bucket,
      avgRisk: avg(analyses.varroaInfectionRisk).mapWith(Number),
      analysisCount: count(analyses.id).mapWith(Number),
    })
    .from(analyses)
    .where(
      and(
        eq(analyses.hiveId, hiveId),
        eq(analyses.status, 'success'),
        gte(analyses.analyzedAt, from),
        lte(analyses.analyzedAt, to),
      ),
    )
    .groupBy(bucket)
    .orderBy(bucket);

  return rows.map((r) => ({
    bucket: r.bucket,
    avgRisk: r.avgRisk,
    analysisCount: r.analysisCount,
  }));
}
