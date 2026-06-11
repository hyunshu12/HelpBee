import { and, avg, count, desc, eq, gte, isNull, lte, sql } from 'drizzle-orm';

import type { Database } from '../client';
import { analyses } from '../schema/analyses';
import { hives, type Hive } from '../schema/hives';

/**
 * 사용자별 hive 목록 (soft delete 제외, 최신 update 순).
 * limit/offset은 헬퍼 내부에서 방어적 클램프(zod 우회 직접호출 대비, §9.3 SHOULD):
 * limit=min(opts.limit??50,100), offset=clamp(0..10000).
 */
export async function listHivesByUser(
  db: Database,
  userId: string,
  opts: { limit?: number; offset?: number } = {},
): Promise<Hive[]> {
  const limit = Math.min(Math.max(opts.limit ?? 50, 1), 100);
  const offset = Math.min(Math.max(opts.offset ?? 0, 0), 10000);
  return db
    .select()
    .from(hives)
    .where(and(eq(hives.userId, userId), isNull(hives.deletedAt)))
    .orderBy(desc(hives.updatedAt))
    .limit(limit)
    .offset(offset);
}

export type CreateHiveInput = {
  name: string;
  note?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  address?: string | null;
  installedAt?: Date | null;
};

/** hive 생성 — 명시 화이트리스트만 set(userId/id/deleted_at/timestamps는 코드 결정, Mass Assignment 차단). */
export async function createHive(
  db: Database,
  userId: string,
  input: CreateHiveInput,
): Promise<Hive> {
  const [row] = await db
    .insert(hives)
    .values({
      userId,
      name: input.name,
      note: input.note ?? null,
      latitude: input.latitude != null ? String(input.latitude) : null,
      longitude: input.longitude != null ? String(input.longitude) : null,
      address: input.address ?? null,
      installedAt: input.installedAt ?? null,
    })
    .returning();
  return row!;
}

export type UpdateHivePatch = Partial<CreateHiveInput>;

/**
 * hive 부분 수정 (소유 + soft delete 제외 조건부). 비소유/없음 → undefined(라우트 404).
 * 제공된 필드만 화이트리스트로 set(스프레드 금지). updated_at은 $onUpdate 자동.
 */
export async function updateHive(
  db: Database,
  hiveId: string,
  userId: string,
  patch: UpdateHivePatch,
): Promise<Hive | undefined> {
  const set: Record<string, unknown> = {};
  if (patch.name !== undefined) set.name = patch.name;
  if (patch.note !== undefined) set.note = patch.note;
  if (patch.latitude !== undefined) set.latitude = patch.latitude != null ? String(patch.latitude) : null;
  if (patch.longitude !== undefined) {
    set.longitude = patch.longitude != null ? String(patch.longitude) : null;
  }
  if (patch.address !== undefined) set.address = patch.address;
  if (patch.installedAt !== undefined) set.installedAt = patch.installedAt;
  if (Object.keys(set).length === 0) {
    return getHiveByIdForUser(db, hiveId, userId);
  }
  const [row] = await db
    .update(hives)
    .set(set)
    .where(and(eq(hives.id, hiveId), eq(hives.userId, userId), isNull(hives.deletedAt)))
    .returning();
  return row;
}

/** soft delete (hard delete 금지). 비소유/이미삭제 → undefined(라우트 404). */
export async function softDeleteHive(
  db: Database,
  hiveId: string,
  userId: string,
): Promise<{ id: string; deletedAt: Date | null } | undefined> {
  const [row] = await db
    .update(hives)
    .set({ deletedAt: new Date() })
    .where(and(eq(hives.id, hiveId), eq(hives.userId, userId), isNull(hives.deletedAt)))
    .returning({ id: hives.id, deletedAt: hives.deletedAt });
  return row;
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
 * Hive별 일자별 평균 risk 트렌드 (소유권 검증 포함).
 *
 * - hives INNER JOIN으로 소유권(userId) + soft delete(deletedAt IS NULL) 동시 검증.
 *   → 호출 라우트가 검증을 깜빡해도 IDOR 발생 X.
 *   → 다른 user의 hiveId로 호출 시 빈 배열 반환.
 * - dual-engine 환경에서는 같은 image_id에 2 row가 있을 수 있어 단순 평균이 두 모델 합 평균이 됨.
 *   베타 비교 기간에는 이 동작 의도적 — 후속 PR에서 model_id로 분리 트렌드 함수 추가 예정.
 *
 * @example
 *   // apps/api 라우트에서 (userId는 JWT 미들웨어에서 추출):
 *   const trend = await queries.hives.getHiveTrend(db, hiveId, userId, from, to);
 */
export async function getHiveTrend(
  db: Database,
  hiveId: string,
  userId: string,
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
    .innerJoin(hives, eq(hives.id, analyses.hiveId))
    .where(
      and(
        eq(analyses.hiveId, hiveId),
        eq(hives.userId, userId),
        isNull(hives.deletedAt),
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
