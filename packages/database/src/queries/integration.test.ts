/**
 * Group A 헬퍼 실 DB 통합테스트 (실제 PostgreSQL).
 * 실행(opt-in): DB_ITEST=1 DATABASE_URL=postgresql://localhost:5432/helpbee_test \
 *        pnpm --filter @helpbee/database test:integration
 * (마이그레이션 적용된 깨끗한 DB 필요)
 *
 * ⚠️ DB_ITEST 미설정 시 전체 스킵 — DB 없는 CI/`turbo run test`에서 깨지지 않게 한다.
 * 검증: 진짜 저장/조회/소유권(IDOR)/멱등/dual-engine UNIQUE/트렌드.
 */
import { eq } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { db, queries, schema } from '../index';

const RUN = process.env.DB_ITEST === '1';

const U1 = '00000000-0000-4000-8000-000000000001';
const U2 = '00000000-0000-4000-8000-000000000002';
const HIVE = '00000000-0000-4000-8000-0000000000a1';
const IMG = '00000000-0000-4000-8000-0000000000b1';

let yoloModelId: string;
let openaiModelId: string;

async function clean() {
  await db.delete(schema.recommendations);
  await db.delete(schema.analyses);
  await db.delete(schema.analysisImages);
  await db.delete(schema.subscriptions);
  await db.delete(schema.hives);
  await db.delete(schema.aiModels);
  await db.delete(schema.users);
}

// skipIf가 훅까지 막도록 beforeAll/afterAll은 describe 블록 안에 둔다.
describe.skipIf(!RUN)('DB integration (real PostgreSQL)', () => {
  beforeAll(async () => {
    await clean();
    await db.insert(schema.users).values([
      { id: U1, email: 'u1@itest.local', name: 'U1', role: 'user', passwordHash: 'x', emailVerifiedAt: new Date() },
      { id: U2, email: 'u2@itest.local', name: 'U2', role: 'user', passwordHash: 'x' },
    ]);
    await db.insert(schema.hives).values({ id: HIVE, userId: U1, name: 'H1' });
    await db.insert(schema.aiModels).values([
      { provider: 'openai', name: 'gpt-4o-mini', version: '2024-07-18' },
      { provider: 'yolo', name: 'helpbee-yolov11s', version: '0.1.0' },
    ]);
    await db.insert(schema.analysisImages).values({
      id: IMG,
      hiveId: HIVE,
      uploadedBy: U1,
      storageUrl: 'images/u1/2026/06/x.jpg',
      mimeType: 'image/jpeg',
    });
    yoloModelId = (await queries.models.resolveActiveModel(db, 'yolo'))!.id;
    openaiModelId = (await queries.models.resolveActiveModel(db, 'openai'))!.id;
  });

  afterAll(async () => {
    // postgres-js 연결 종료 (열린 핸들로 vitest 미종료 방지)
    await (db as unknown as { $client?: { end?: () => Promise<void> } }).$client?.end?.();
  });

  it('resolveActiveModel: provider별 활성 모델', () => {
    expect(yoloModelId).toBeTruthy();
    expect(openaiModelId).toBeTruthy();
  });

  it('getAnalysisImageByIdForUser: 소유권 강제(IDOR)', async () => {
    expect(await queries.images.getAnalysisImageByIdForUser(db, IMG, U1)).toBeTruthy();
    expect(await queries.images.getAnalysisImageByIdForUser(db, IMG, U2)).toBeUndefined();
  });

  it('createSingleAnalysis: analysis 1행 + recommendations N행 실제 저장', async () => {
    const row = (await queries.analyses.createSingleAnalysis(db, {
      hiveId: HIVE,
      imageId: IMG,
      modelId: yoloModelId,
      analysis: {
        status: 'success',
        varroaInfectionRisk: 35,
        overallHealth: 'warning',
        analyzedAt: new Date(),
      },
      recommendations: [
        { order: 0, content: '처치 검토', severity: 'warn' },
        { order: 1, content: '재촬영', severity: 'info' },
      ],
    })) as { id: string; status: string };

    expect(row.status).toBe('success');
    const fromDb = await db.select().from(schema.analyses).where(eq(schema.analyses.id, row.id));
    expect(fromDb).toHaveLength(1);
    expect(fromDb[0]!.varroaInfectionRisk).toBe(35);
    const recs = await db
      .select()
      .from(schema.recommendations)
      .where(eq(schema.recommendations.analysisId, row.id));
    expect(recs).toHaveLength(2);
  });

  it('createSingleAnalysis: 멱등 — 같은 (image,model) 재호출 시 미덮어쓰기', async () => {
    await queries.analyses.createSingleAnalysis(db, {
      hiveId: HIVE,
      imageId: IMG,
      modelId: yoloModelId,
      analysis: { status: 'success', varroaInfectionRisk: 99, analyzedAt: new Date() },
      recommendations: [{ order: 0, content: 'dup', severity: 'info' }],
    });
    const yoloRows = (
      await db.select().from(schema.analyses).where(eq(schema.analyses.imageId, IMG))
    ).filter((a) => a.modelId === yoloModelId);
    expect(yoloRows).toHaveLength(1); // 중복 행 없음
    expect(yoloRows[0]!.varroaInfectionRisk).toBe(35); // 99로 안 덮어씀
  });

  it('dual-engine: 같은 image + 다른 model = 2행 (UNIQUE 허용)', async () => {
    await queries.analyses.createSingleAnalysis(db, {
      hiveId: HIVE,
      imageId: IMG,
      modelId: openaiModelId,
      analysis: { status: 'success', varroaInfectionRisk: 40, analyzedAt: new Date() },
      recommendations: [],
    });
    const all = await db.select().from(schema.analyses).where(eq(schema.analyses.imageId, IMG));
    expect(all).toHaveLength(2);
  });

  it('listAnalysesByHiveForUser: 소유권 강제(IDOR)', async () => {
    expect((await queries.analyses.listAnalysesByHiveForUser(db, HIVE, U1)).length).toBeGreaterThan(0);
    expect(await queries.analyses.listAnalysesByHiveForUser(db, HIVE, U2)).toHaveLength(0);
  });

  it('getAnalysisByIdForUser / findSuccessAnalysisByImage: 소유권', async () => {
    const [an] = await db.select().from(schema.analyses).where(eq(schema.analyses.imageId, IMG)).limit(1);
    expect(await queries.analyses.getAnalysisByIdForUser(db, an!.id, U1)).toBeTruthy();
    expect(await queries.analyses.getAnalysisByIdForUser(db, an!.id, U2)).toBeUndefined();
    expect(await queries.analyses.findSuccessAnalysisByImage(db, IMG, U1)).toBeTruthy();
    expect(await queries.analyses.findSuccessAnalysisByImage(db, IMG, U2)).toBeUndefined();
  });

  it('getHiveTrend: 소유자만 집계', async () => {
    const from = new Date(Date.now() - 86_400_000);
    const to = new Date(Date.now() + 86_400_000);
    expect((await queries.hives.getHiveTrend(db, HIVE, U1, from, to)).length).toBeGreaterThan(0);
    expect(await queries.hives.getHiveTrend(db, HIVE, U2, from, to)).toHaveLength(0);
  });
});
