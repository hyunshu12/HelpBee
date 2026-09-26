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
const IMG2 = '00000000-0000-4000-8000-0000000000b2';
const HIVE2 = '00000000-0000-4000-8000-0000000000a2';
const IMG3 = '00000000-0000-4000-8000-0000000000b3';
const IMG4 = '00000000-0000-4000-8000-0000000000b4';
const IMG5 = '00000000-0000-4000-8000-0000000000b5';
const IMG6 = '00000000-0000-4000-8000-0000000000b6';

let yoloModelId: string;
let openaiModelId: string;
let twoStageModelId: string;

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
      { provider: 'yolo', name: 'helpbee-two-stage', version: '0.2.0' },
    ]);
    await db.insert(schema.analysisImages).values({
      id: IMG,
      hiveId: HIVE,
      uploadedBy: U1,
      storageUrl: 'images/u1/2026/06/x.jpg',
      mimeType: 'image/jpeg',
    });
    await db.insert(schema.analysisImages).values({
      id: IMG2,
      hiveId: HIVE,
      uploadedBy: U1,
      storageUrl: 'images/u1/2026/06/y.jpg',
      mimeType: 'image/jpeg',
    });
    yoloModelId = (await queries.models.resolveActiveModel(db, 'yolo'))!.id;
    openaiModelId = (await queries.models.resolveActiveModel(db, 'openai'))!.id;
    twoStageModelId = (await queries.models.resolveActiveModel(db, 'yolo', 'two-stage'))!.id;
  });

  afterAll(async () => {
    // 연결은 vitest 워커 종료 시 정리(여러 통합 스위트가 공유 싱글톤을 쓰므로 개별 end() 금지).
  });

  it('resolveActiveModel: provider별 활성 모델', () => {
    expect(yoloModelId).toBeTruthy();
    expect(openaiModelId).toBeTruthy();
  });

  it('resolveActiveModel: 같은 yolo provider에서 v1 ↔ two-stage 행을 pipeline으로 구분', async () => {
    expect(twoStageModelId).toBeTruthy();
    expect(twoStageModelId).not.toBe(yoloModelId);
    const v1 = await queries.models.resolveActiveModel(db, 'yolo', 'v1');
    const ts = await queries.models.resolveActiveModel(db, 'yolo', 'two-stage');
    expect(v1!.name).toBe('helpbee-yolov11s');
    expect(ts!.name).toBe('helpbee-two-stage');
    expect(ts!.version).toBe('0.2.0');
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

  it('two-stage 컬럼 저장 + getHiveTrend 시리즈 분리(avgRisk=구 row만, avgVdi=two-stage만)', async () => {
    // 이중 출력 기간: two-stage row에도 risk_score(점수 단위 70)가 채워지지만 avgRisk에 섞이면 안 된다.
    await queries.analyses.createSingleAnalysis(db, {
      hiveId: HIVE,
      imageId: IMG2,
      modelId: twoStageModelId,
      analysis: {
        status: 'success',
        varroaInfectionRisk: 70,
        overallHealth: 'critical',
        vdi: 10.04 as never,
        vdiCiLow: 6.5 as never,
        vdiCiHigh: 14.2 as never,
        beeTotal: 250,
        beeInfested: 26,
        analyzedAt: new Date(),
      },
      recommendations: [],
    });
    const [row] = await db.select().from(schema.analyses).where(eq(schema.analyses.imageId, IMG2));
    expect(Number(row!.vdi)).toBeCloseTo(10.04, 3);
    expect(row!.beeTotal).toBe(250);
    expect(row!.beeInfested).toBe(26);

    const from = new Date(Date.now() - 86_400_000);
    const to = new Date(Date.now() + 86_400_000);
    const trend = await queries.hives.getHiveTrend(db, HIVE, U1, from, to);
    expect(trend).toHaveLength(1);
    // 구 row: yolo 35 + openai 40 → 37.5 (two-stage의 70 제외)
    expect(trend[0]!.avgRisk).toBeCloseTo(37.5, 5);
    expect(trend[0]!.avgVdi).toBeCloseTo(10.04, 3);
    expect(trend[0]!.analysisCount).toBe(3);
  });
  it('getCountsByIdsForUser: 소유·success만, 구 row는 null 카운트', async () => {
    const rows = await db.select().from(schema.analyses);
    const ts = rows.find((r) => r.imageId === IMG2)!;
    const legacy = rows.find((r) => r.imageId === IMG && r.modelId === yoloModelId)!;
    const got = await queries.analyses.getCountsByIdsForUser(db, [ts.id, legacy.id], U1);
    expect(got).toHaveLength(2);
    expect(got.find((g) => g.id === ts.id)).toMatchObject({ beeInfested: 26, beeTotal: 250 });
    expect(got.find((g) => g.id === ts.id)!.tier).toBeNull(); // raw_response 없음 → null
    expect(got.find((g) => g.id === legacy.id)).toMatchObject({ beeInfested: null, beeTotal: null });
    expect(await queries.analyses.getCountsByIdsForUser(db, [ts.id], U2)).toHaveLength(0);
    expect(await queries.analyses.getCountsByIdsForUser(db, [], U1)).toEqual([]);
  });

  it('retryFailedAnalysis: failed → two-stage 성공 재시도 시 vdi/CI/bee 카운트 영속 (C1)', async () => {
    await db.insert(schema.hives).values({ id: HIVE2, userId: U1, name: 'H2' });
    for (const id of [IMG3, IMG4, IMG5, IMG6]) {
      await db.insert(schema.analysisImages).values({
        id,
        hiveId: HIVE2,
        uploadedBy: U1,
        storageUrl: `images/u1/2026/09/${id}.jpg`,
        mimeType: 'image/jpeg',
      });
    }
    const failed = await queries.analyses.createSingleAnalysis(db, {
      hiveId: HIVE2,
      imageId: IMG3,
      modelId: twoStageModelId,
      analysis: { status: 'failed', error: 'ai_unavailable', analyzedAt: new Date() },
      recommendations: [],
    });
    const row = await queries.analyses.retryFailedAnalysis(db, {
      analysisId: failed.id,
      modelId: twoStageModelId,
      analysis: {
        status: 'success',
        varroaInfectionRisk: 70,
        estimatedVarroaCount: null,
        overallHealth: 'critical',
        vdi: '10.04',
        vdiCiLow: '6.5',
        vdiCiHigh: '14.2',
        beeTotal: 250,
        beeInfested: 26,
        rawResponse: { tier: 'high', vdi_display: '10.0', corrected: true },
        latencyMs: 900,
        error: null,
        analyzedAt: new Date(),
      },
      recommendations: [{ order: 0, content: '방제 검토', severity: 'danger' }],
    });
    expect(row.id).toBe(failed.id);
    expect(row.status).toBe('success');
    const [stored] = await db.select().from(schema.analyses).where(eq(schema.analyses.id, failed.id));
    expect(Number(stored!.vdi)).toBeCloseTo(10.04, 3);
    expect(Number(stored!.vdiCiLow)).toBeCloseTo(6.5, 3);
    expect(Number(stored!.vdiCiHigh)).toBeCloseTo(14.2, 3);
    expect(stored!.beeTotal).toBe(250);
    expect(stored!.beeInfested).toBe(26);
    expect(stored!.error).toBeNull();
  });

  it('getHiveTrend.avgVdi: insufficient 행과 OpenAI shim 행 제외 (M1)', async () => {
    // HIVE2: 위 C1 행(vdi 10.04, high) + insufficient(vdi 50) + shim(vdi 20, bee_total null, corrected false)
    const mk = (imageId: string, vdi: string, beeTotal: number | null, raw: Record<string, unknown>) =>
      queries.analyses.createSingleAnalysis(db, {
        hiveId: HIVE2,
        imageId,
        modelId: imageId === IMG5 ? openaiModelId : twoStageModelId,
        analysis: {
          status: 'success',
          vdi,
          beeTotal,
          beeInfested: beeTotal === null ? null : 0,
          rawResponse: raw,
          analyzedAt: new Date(),
        },
        recommendations: [],
      });
    const insuff = await mk(IMG4, '50', 12, { tier: 'insufficient', corrected: true });
    // raw_response 는 드라이버가 JSON 문자열로 이중 인코딩 — tier 를 풀어서 읽어야 aggregate 가 제외할 수 있다.
    const [c] = await queries.analyses.getCountsByIdsForUser(db, [insuff.id], U1);
    expect(c!.tier).toBe('insufficient');
    await mk(IMG5, '20', null, { tier: 'high', corrected: false });
    await mk(IMG6, '4', 300, { tier: 'elevated', corrected: true });
    const from = new Date(Date.now() - 86_400_000);
    const to = new Date(Date.now() + 86_400_000);
    const trend = await queries.hives.getHiveTrend(db, HIVE2, U1, from, to);
    expect(trend).toHaveLength(1);
    expect(trend[0]!.avgVdi).toBeCloseTo((10.04 + 4) / 2, 3);
    expect(trend[0]!.analysisCount).toBe(4);
  });
});
