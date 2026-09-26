import { Hono } from 'hono';
import { describe, expect, it, vi } from 'vitest';

import { AppError } from '../lib/error-codes';
import { errorHandler } from '../middleware/error-handler';
import type { EvidenceItem } from '../services/ai-client';
import { analysesRoutes, type AnalysesDeps } from './analyses';

const HIVE = '11111111-1111-1111-1111-111111111111';
const IMAGE = '22222222-2222-2222-2222-222222222222';

function baseDeps(over: Partial<AnalysesDeps> = {}): AnalysesDeps {
  return {
    getImageForUser: async () => ({ id: IMAGE, hiveId: HIVE, storageUrl: 'images/u1/2026/06/x.jpg' }),
    findSuccessByImage: async () => undefined,
    findFailedByImage: async () => undefined,
    retryAnalysis: async (input) => ({
      id: 'an-failed',
      modelId: input.modelId,
      recommendations: input.recommendations,
      ...input.analysis,
    }),
    getEmailVerifiedAt: async () => new Date(),
    getPlan: async () => 'free',
    reserveQuota: async () => {},
    refundQuota: async () => {},
    presignGet: async (k) => `https://s3/${k}?sig=1`,
    resolveModelId: async () => 'model-yolo',
    analyze: async () => ({
      risk_score: 35,
      tier: 'watch',
      engine_used: 'yolo',
      recommendations: ['처치 검토', '재촬영'],
      latency_ms: 220,
    }),
    storeAnalysis: async (input) => ({
      id: 'an1',
      modelId: input.modelId,
      recommendations: input.recommendations,
      ...input.analysis,
    }),
    listForUser: async () => [{ id: 'an1' }, { id: 'an2' }],
    getByIdForUser: async () => ({ id: 'an1' }),
    getRecommendations: async () => [{ order: 0, content: '처치 검토', severity: 'warn' }],
    getTrend: async () => [{ bucket: '2026-06-10', avgRisk: 35, analysisCount: 2 }],
    countsByIds: async (ids) => ids.map((id) => ({ id, beeInfested: 1, beeTotal: 40 })),
    aggregate: async () => ({
      vdi: 1.59,
      vdi_display: '1.6',
      vdi_raw: 1.06,
      tier: 'low',
      bee_total: 940,
      bee_infested: 10,
      sampling_ci95: [0.5, 1.9],
      corrected: true,
    }),
    ...over,
  };
}

function makeApp(deps: AnalysesDeps, opts: { userId?: string } = {}) {
  const app = new Hono();
  app.onError(errorHandler);
  app.use('*', async (c, next) => {
    c.set('userId', opts.userId ?? 'u1');
    c.set('requestId', 'req-1');
    await next();
  });
  app.route('/v1/analyses', analysesRoutes(deps));
  return app;
}

async function post(app: Hono, body: unknown) {
  return app.request('/v1/analyses', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
}

describe('POST /v1/analyses', () => {
  it('free + YOLO success → 201 completed resource', async () => {
    const deps = baseDeps();
    const res = await post(makeApp(deps), { hiveId: HIVE, imageId: IMAGE });
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.data.status).toBe('success');
    expect(body.data.varroaInfectionRisk).toBe(35);
    expect(body.data.overallHealth).toBe('warning'); // watch → warning
    expect(body.meta.requestId).toBe('req-1');
    // recommendations (§4): tier에서 파생, watch → severity 'warn'
    expect(body.data.recommendations).toEqual([
      { order: 0, content: '처치 검토', severity: 'warn' },
      { order: 1, content: '재촬영', severity: 'warn' },
    ]);
  });

  it('free engine is yolo (no fallback)', async () => {
    const analyze = vi.fn(baseDeps().analyze);
    await post(makeApp(baseDeps({ analyze })), { hiveId: HIVE, imageId: IMAGE });
    expect(analyze.mock.calls[0][0].engine).toBe('yolo');
  });

  it('paid plan uses engine auto', async () => {
    const analyze = vi.fn(baseDeps().analyze);
    await post(makeApp(baseDeps({ getPlan: async () => 'pro', analyze })), {
      hiveId: HIVE,
      imageId: IMAGE,
    });
    expect(analyze.mock.calls[0][0].engine).toBe('auto');
  });

  it('idempotent: existing success short-circuits (no analyze, 200)', async () => {
    const analyze = vi.fn(baseDeps().analyze);
    const res = await post(
      makeApp(baseDeps({ findSuccessByImage: async () => ({ id: 'prev' }), analyze })),
      { hiveId: HIVE, imageId: IMAGE },
    );
    expect(res.status).toBe(200);
    expect((await res.json()).data.id).toBe('prev');
    expect(analyze).not.toHaveBeenCalled();
  });

  it('404 when image not owned', async () => {
    const res = await post(makeApp(baseDeps({ getImageForUser: async () => undefined })), {
      hiveId: HIVE,
      imageId: IMAGE,
    });
    expect(res.status).toBe(404);
    expect((await res.json()).code).toBe('NOT_FOUND');
  });

  it('404 when image hiveId mismatches body', async () => {
    const res = await post(
      makeApp(
        baseDeps({
          getImageForUser: async () => ({ id: IMAGE, hiveId: 'other', storageUrl: 'k' }),
        }),
      ),
      { hiveId: HIVE, imageId: IMAGE },
    );
    expect(res.status).toBe(404);
  });

  it('403 when free user email not verified', async () => {
    const res = await post(makeApp(baseDeps({ getEmailVerifiedAt: async () => null })), {
      hiveId: HIVE,
      imageId: IMAGE,
    });
    expect(res.status).toBe(403);
    expect((await res.json()).code).toBe('AUTH_EMAIL_NOT_VERIFIED');
  });

  it('402 when quota exceeded', async () => {
    const res = await post(
      makeApp(
        baseDeps({
          reserveQuota: async () => {
            throw new AppError('QUOTA_EXCEEDED');
          },
        }),
      ),
      { hiveId: HIVE, imageId: IMAGE },
    );
    expect(res.status).toBe(402);
    expect((await res.json()).code).toBe('QUOTA_EXCEEDED');
  });

  it('ai unavailable → graceful 200 (status failed) + free quota refunded', async () => {
    const refundQuota = vi.fn(async () => {});
    const res = await post(
      makeApp(
        baseDeps({
          refundQuota,
          analyze: async () => {
            throw new AppError('AI_UNAVAILABLE');
          },
        }),
      ),
      { hiveId: HIVE, imageId: IMAGE },
    );
    expect(res.status).toBe(200);
    const failedBody = await res.json();
    expect(failedBody.data.status).toBe('failed');
    expect(failedBody.data.recommendations).toEqual([]); // 실패는 빈 배열
    expect(refundQuota).toHaveBeenCalledOnce();
  });

  it('ai graceful (engine_used null) → 200 failed + refund', async () => {
    const refundQuota = vi.fn(async () => {});
    const res = await post(
      makeApp(
        baseDeps({
          refundQuota,
          analyze: async () => ({
            risk_score: null,
            tier: 'watch',
            engine_used: null,
            recommendations: ['AI 분석 실패'],
          }),
        }),
      ),
      { hiveId: HIVE, imageId: IMAGE },
    );
    expect(res.status).toBe(200);
    expect((await res.json()).data.status).toBe('failed');
    expect(refundQuota).toHaveBeenCalledOnce();
  });

  it('retry: existing failed row → re-run → success UPDATES same id (200, not 201)', async () => {
    const storeAnalysis = vi.fn(baseDeps().storeAnalysis);
    const retryAnalysis = vi.fn(async (input: { analysisId: string; recommendations: unknown }) => ({
      id: input.analysisId,
      status: 'success',
      varroaInfectionRisk: 35,
      overallHealth: 'warning',
    }));
    const res = await post(
      makeApp(
        baseDeps({
          findFailedByImage: async () => ({ id: 'an-failed' }),
          storeAnalysis,
          retryAnalysis,
          getRecommendations: async () => [
            { order: 0, content: '처치 검토', severity: 'warn' },
            { order: 1, content: '재촬영', severity: 'warn' },
          ],
        }),
      ),
      { hiveId: HIVE, imageId: IMAGE },
    );
    expect(res.status).toBe(200); // 재시도는 갱신이므로 201 아님
    const body = await res.json();
    expect(body.data.id).toBe('an-failed'); // 같은 row id 보존
    expect(body.data.status).toBe('success');
    expect(retryAnalysis).toHaveBeenCalledOnce();
    expect(storeAnalysis).not.toHaveBeenCalled(); // insert 경로 안 탐
    // 재시도가 실어 보낸 recommendations는 tier(watch)에서 파생 → 2개
    expect(retryAnalysis.mock.calls[0][0].recommendations).toEqual([
      { order: 0, content: '처치 검토', severity: 'warn' },
      { order: 1, content: '재촬영', severity: 'warn' },
    ]);
    expect(body.data.recommendations.length).toBe(2);
  });

  it('retry: fail again → same id stays failed with fresh error (200, recs [])', async () => {
    const retryAnalysis = vi.fn(async (input: { analysisId: string; recommendations: unknown }) => ({
      id: input.analysisId,
      status: 'failed',
      varroaInfectionRisk: null,
      error: 'ai_unavailable',
    }));
    const refundQuota = vi.fn(async () => {});
    const res = await post(
      makeApp(
        baseDeps({
          findFailedByImage: async () => ({ id: 'an-failed' }),
          retryAnalysis,
          refundQuota,
          getRecommendations: async () => [], // failed 행은 recommendations 없음
          analyze: async () => {
            throw new AppError('AI_UNAVAILABLE');
          },
        }),
      ),
      { hiveId: HIVE, imageId: IMAGE },
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.id).toBe('an-failed'); // 여전히 같은 row
    expect(body.data.status).toBe('failed');
    expect(body.data.recommendations).toEqual([]);
    expect(refundQuota).toHaveBeenCalledOnce(); // 실패 재시도도 quota 환불
    expect(retryAnalysis).toHaveBeenCalledOnce();
    expect(retryAnalysis.mock.calls[0][0].recommendations).toEqual([]);
  });

  it('retry: existing success short-circuits BEFORE checking failed row', async () => {
    const findFailedByImage = vi.fn(async () => undefined);
    const retryAnalysis = vi.fn(baseDeps().retryAnalysis);
    const res = await post(
      makeApp(
        baseDeps({
          findSuccessByImage: async () => ({ id: 'prev-success' }),
          findFailedByImage,
          retryAnalysis,
        }),
      ),
      { hiveId: HIVE, imageId: IMAGE },
    );
    expect(res.status).toBe(200);
    expect((await res.json()).data.id).toBe('prev-success');
    expect(findFailedByImage).not.toHaveBeenCalled(); // success면 재시도 판정 자체를 안 함
    expect(retryAnalysis).not.toHaveBeenCalled();
  });

  // ── two-stage 계약 관용화 (스펙 §3·§8-1) ──
  it('stores success when risk_score is missing but engine_used is set (new contract)', async () => {
    const storeAnalysis = vi.fn(baseDeps().storeAnalysis);
    const resolveModelId = vi.fn(async (_p: 'yolo' | 'openai', pipeline?: 'two-stage' | 'v1') =>
      pipeline === 'two-stage' ? 'model-two-stage' : 'model-yolo',
    );
    const deps = baseDeps({
      storeAnalysis,
      resolveModelId,
      analyze: async () => ({
        engine_used: 'yolo',
        tier: 'elevated',
        vdi: 4.2,
        vdi_display: '4.2',
        bee_total: 310,
        bee_infested: 14,
        sampling_ci95: [2.4, 6.9],
        recommendations: ['가루설탕법으로 확인하세요'],
        model_version: 'two-stage-v0.2.0',
        model_versions: { stage1: 's1-0.2.0', stage2: 's2-0.2.0', vdi_config: 'vdi-0.2.0' },
        risk_score: null,
      }),
    });
    const res = await post(makeApp(deps), { hiveId: HIVE, imageId: IMAGE });
    expect(res.status).toBe(201);
    const input = storeAnalysis.mock.calls[0][0];
    const stored = input.analysis;
    expect(stored.status).toBe('success');
    expect(stored.overallHealth).toBe('warning');
    expect(stored.varroaInfectionRisk).toBeNull();
    expect(stored.vdi).toBe(4.2);
    expect(stored.vdiCiLow).toBe(2.4);
    expect(stored.vdiCiHigh).toBe(6.9);
    expect(stored.beeTotal).toBe(310);
    expect(stored.beeInfested).toBe(14);
    expect(input.recommendations[0].severity).toBe('warn');
    // model_versions 존재 → two-stage 모델 row
    expect(resolveModelId).toHaveBeenCalledWith('yolo', 'two-stage');
    expect(input.modelId).toBe('model-two-stage');
  });

  it('stores insufficient tier with zero bees without error', async () => {
    const storeAnalysis = vi.fn(baseDeps().storeAnalysis);
    const refundQuota = vi.fn(async () => {});
    const deps = baseDeps({
      storeAnalysis,
      refundQuota,
      analyze: async () => ({
        engine_used: 'yolo',
        tier: 'insufficient',
        vdi: null,
        vdi_display: null,
        bee_total: 0,
        bee_infested: 0,
        recommendations: ['벌이 보이도록 다시 촬영해 주세요'],
        model_version: 'two-stage-v0.2.0',
        risk_score: null,
      }),
    });
    const res = await post(makeApp(deps), { hiveId: HIVE, imageId: IMAGE });
    expect(res.status).toBe(201);
    const input = storeAnalysis.mock.calls[0][0];
    expect(input.analysis.status).toBe('success');
    expect(input.analysis.overallHealth).toBeNull();
    expect(input.analysis.vdi).toBeNull();
    expect(input.analysis.beeTotal).toBe(0);
    expect(input.recommendations[0].severity).toBe('info');
    expect(refundQuota).not.toHaveBeenCalled(); // insufficient는 실패가 아님
  });

  it.each([
    ['low', 'healthy', 'info'],
    ['elevated', 'warning', 'warn'],
    ['high', 'critical', 'danger'],
    ['insufficient', null, 'info'],
    ['safe', 'healthy', 'info'],
    ['watch', 'warning', 'warn'],
    ['danger', 'critical', 'danger'],
  ])('tier %s → overall_health %s, severity %s', async (tier, health, severity) => {
    const storeAnalysis = vi.fn(baseDeps().storeAnalysis);
    const deps = baseDeps({
      storeAnalysis,
      analyze: async () => ({
        engine_used: 'yolo',
        tier: tier as never,
        risk_score: 40,
        recommendations: ['x'],
        model_version: 'm',
      }),
    });
    await post(makeApp(deps), { hiveId: HIVE, imageId: IMAGE });
    const input = storeAnalysis.mock.calls[0][0];
    expect(input.analysis.overallHealth).toBe(health);
    expect(input.recommendations[0].severity).toBe(severity);
  });

  it('dual output: stores AI risk_score as-is (score units, no re-rounding of vdi)', async () => {
    const storeAnalysis = vi.fn(baseDeps().storeAnalysis);
    const deps = baseDeps({
      storeAnalysis,
      analyze: async () => ({
        engine_used: 'yolo',
        tier: 'high',
        tier_legacy: 'danger',
        risk_score: 70,
        vdi: 10.04,
        vdi_display: '10.0',
        bee_total: 250,
        bee_infested: 26,
        recommendations: [],
        model_version: 'two-stage-v0.2.0',
        model_versions: { stage1: 'a', stage2: 'b', vdi_config: 'c' },
      }),
    });
    await post(makeApp(deps), { hiveId: HIVE, imageId: IMAGE });
    const stored = storeAnalysis.mock.calls[0][0].analysis;
    expect(stored.varroaInfectionRisk).toBe(70);
    expect(stored.vdi).toBe(10.04);
    expect(stored.overallHealth).toBe('critical');
  });

  it('unknown tier from AI → overall_health null, severity info (no crash)', async () => {
    const storeAnalysis = vi.fn(baseDeps().storeAnalysis);
    const deps = baseDeps({
      storeAnalysis,
      analyze: async () => ({
        engine_used: 'yolo',
        tier: 'mystery' as never,
        risk_score: 10,
        recommendations: ['x'],
        model_version: 'm',
      }),
    });
    const res = await post(makeApp(deps), { hiveId: HIVE, imageId: IMAGE });
    expect(res.status).toBe(201);
    const input = storeAnalysis.mock.calls[0][0];
    expect(input.analysis.overallHealth).toBeNull();
    expect(input.recommendations[0].severity).toBe('info');
  });

  it('still accepts the legacy contract (risk_score + safe/watch/danger) → v1 model row', async () => {
    const storeAnalysis = vi.fn(baseDeps().storeAnalysis);
    const resolveModelId = vi.fn(async () => 'model-yolo');
    const deps = baseDeps({
      storeAnalysis,
      resolveModelId,
      analyze: async () => ({
        engine_used: 'yolo',
        tier: 'watch',
        risk_score: 55,
        recommendations: [],
        model_version: 'v0.1.0',
      }),
    });
    const res = await post(makeApp(deps), { hiveId: HIVE, imageId: IMAGE });
    expect(res.status).toBe(201);
    const stored = storeAnalysis.mock.calls[0][0].analysis;
    expect(stored.overallHealth).toBe('warning');
    expect(stored.varroaInfectionRisk).toBe(55);
    expect(stored.vdi).toBeNull();
    expect(stored.beeTotal).toBeNull();
    expect(resolveModelId).toHaveBeenCalledWith('yolo', 'v1');
  });

  it('serializes numeric (string) vdi columns from DB rows as numbers in the response', async () => {
    const res = await makeApp(
      baseDeps({
        getByIdForUser: async () => ({ id: 'an1', vdi: '4.200', vdiCiLow: '2.400', vdiCiHigh: null }),
      }),
    ).request('/v1/analyses/an1');
    const body = await res.json();
    expect(body.data.vdi).toBe(4.2);
    expect(body.data.vdiCiLow).toBe(2.4);
    expect(body.data.vdiCiHigh).toBeNull();
  });

  // ── fix round 1: AI 정규화 결과를 raw_response에 보존 → 재조회 시 tier/vdiDisplay 복원 ──
  it('round-trip: elevated result POST → stored raw_response → GET returns tier/vdiDisplay', async () => {
    const db = new Map<string, Record<string, unknown>>();
    const aiResult = {
      engine_used: 'yolo',
      tier: 'elevated',
      tier_legacy: 'watch' as const,
      vdi: 4.2,
      vdi_display: '4.2',
      vdi_raw: 3.1,
      corrected: true,
      bee_total: 310,
      bee_infested: 14,
      sampling_ci95: [2.4, 6.9] as [number, number],
      quality: { ok: true, blur_score: 210, exposure_mean: 120, px_per_mm_est: 4.1 },
      bees: [{ box: [1, 2, 3, 4] as [number, number, number, number], p_infested: 0.9, infested: true }],
      evidence: [
        {
          index: 0,
          box: [1, 2, 3, 4] as [number, number, number, number],
          crop_region: [0, 0, 5, 6] as [number, number, number, number],
          p_infested: 0.9,
          cam: [[0.1]],
        },
      ],
      recommendations: ['가루설탕법으로 확인하세요'],
      model_version: 'two-stage-v0.2.0',
      model_versions: { stage1: 's1', stage2: 's2', vdi_config: 'v' },
      risk_score: 45,
      raw_payload: { crops_sampled: false },
    };
    // 실제 DB 왕복 흉내: jsonb는 JSON 직렬화, numeric은 문자열로 되돌아온다.
    const storeAnalysis = vi.fn(async (input: Parameters<AnalysesDeps['storeAnalysis']>[0]) => {
      const a = input.analysis as Record<string, unknown>;
      const row = {
        id: 'an-rt',
        ...a,
        rawResponse: JSON.parse(JSON.stringify(a.rawResponse)),
        vdi: a.vdi == null ? null : Number(a.vdi).toFixed(3),
        vdiCiLow: a.vdiCiLow == null ? null : Number(a.vdiCiLow).toFixed(3),
        vdiCiHigh: a.vdiCiHigh == null ? null : Number(a.vdiCiHigh).toFixed(3),
      };
      db.set('an-rt', row);
      return row;
    });
    const deps = baseDeps({
      storeAnalysis,
      analyze: async () => aiResult,
      getByIdForUser: async (id) => db.get(id),
      listForUser: async () => [...db.values()],
      getRecommendations: async () => [{ order: 0, content: '가루설탕법으로 확인하세요', severity: 'warn' }],
    });
    const app = makeApp(deps);
    const postRes = await post(app, { hiveId: HIVE, imageId: IMAGE });
    expect(postRes.status).toBe(201);

    const stored = storeAnalysis.mock.calls[0][0].analysis as Record<string, any>;
    expect(stored.rawResponse.tier).toBe('elevated');
    expect(stored.rawResponse.vdi_display).toBe('4.2');
    expect(stored.rawResponse.raw_payload).toEqual({ crops_sampled: false });
    expect(JSON.parse(JSON.stringify(stored.rawResponse))).not.toHaveProperty('bees');
    expect(JSON.parse(JSON.stringify(stored.rawResponse))).not.toHaveProperty('evidence');

    for (const body of [
      (await (await app.request('/v1/analyses/an-rt')).json()).data,
      (await (await app.request('/v1/analyses')).json()).data[0],
      (await postRes.json()).data,
    ]) {
      expect(body.tier).toBe('elevated');
      expect(body.vdiDisplay).toBe('4.2');
      expect(body.vdi).toBe(4.2);
      expect(body.corrected).toBe(true);
      expect(body.beeTotal).toBe(310);
      expect(body.beeInfested).toBe(14);
      expect(body.samplingCi95).toEqual([2.4, 6.9]);
      expect(body.quality).toEqual({ ok: true, blur_score: 210, exposure_mean: 120, px_per_mm_est: 4.1 });
      expect(body.modelVersions).toEqual({ stage1: 's1', stage2: 's2', vdi_config: 'v' });
      expect(body.overallHealth).toBe('warning');
      expect(body.varroaInfectionRisk).toBe(45);
    }
  });

  it('legacy row (pre-two-stage, raw_response = old raw_payload) keeps old fields, new ones null', async () => {
    const legacy = {
      id: 'an-old',
      status: 'success',
      varroaInfectionRisk: 35,
      overallHealth: 'warning',
      rawResponse: { engine: 'yolo', boxes: [], tier: 'watch-ish' }, // 구 raw_payload — 새 필드로 오인 금지
      vdi: null,
      vdiCiLow: null,
      vdiCiHigh: null,
      beeTotal: null,
      beeInfested: null,
    };
    const res = await makeApp(baseDeps({ getByIdForUser: async () => legacy })).request('/v1/analyses/an-old');
    const body = (await res.json()).data;
    expect(body.varroaInfectionRisk).toBe(35);
    expect(body.overallHealth).toBe('warning');
    expect(body.rawResponse).toEqual(legacy.rawResponse);
    for (const k of ['vdi', 'vdiDisplay', 'tier', 'corrected', 'beeTotal', 'beeInfested', 'samplingCi95', 'quality', 'modelVersions']) {
      expect(body[k]).toBeNull();
    }
  });

  it('failure path still stores the error raw_response unchanged', async () => {
    const storeAnalysis = vi.fn(baseDeps().storeAnalysis);
    await post(
      makeApp(baseDeps({ storeAnalysis, analyze: async () => { throw new AppError('AI_UNAVAILABLE'); } })),
      { hiveId: HIVE, imageId: IMAGE },
    );
    expect(storeAnalysis.mock.calls[0][0].analysis.rawResponse).toEqual({ error_reason: 'ai_unavailable' });
  });

  it('rejects unknown body keys (.strict, mass assignment)', async () => {
    const res = await post(makeApp(baseDeps()), {
      hiveId: HIVE,
      imageId: IMAGE,
      role: 'admin',
    });
    expect(res.status).toBe(400);
  });
});

describe('GET /v1/analyses', () => {
  it('lists with pagination meta', async () => {
    const res = await makeApp(baseDeps()).request(`/v1/analyses?hiveId=${HIVE}`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.length).toBe(2);
    expect(body.meta.pagination.limit).toBe(50);
  });

  it('without hiveId lists across all of the user\'s hives (진단 이력 탭)', async () => {
    const listForUser = vi.fn(async () => [{ id: 'an1' }, { id: 'an2' }]);
    const res = await makeApp(baseDeps({ listForUser })).request('/v1/analyses');
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.length).toBe(2);
    // hiveId=undefined가 그대로 내려가야 app.ts가 전체-벌통 쿼리로 분기한다
    expect(listForUser).toHaveBeenCalledWith(undefined, 'u1', { limit: 50, offset: 0 });
  });

  it('passes hiveId through when given (per-hive branch)', async () => {
    const listForUser = vi.fn(async () => [{ id: 'an1' }]);
    const res = await makeApp(baseDeps({ listForUser })).request(
      `/v1/analyses?hiveId=${HIVE}&limit=10&offset=20`,
    );
    expect(res.status).toBe(200);
    expect(listForUser).toHaveBeenCalledWith(HIVE, 'u1', { limit: 10, offset: 20 });
  });

  it('still rejects a malformed hiveId (optional ≠ anything goes)', async () => {
    const res = await makeApp(baseDeps()).request('/v1/analyses?hiveId=not-a-uuid');
    expect(res.status).toBe(400);
  });

  it('GET /:id returns 404 when not found', async () => {
    const res = await makeApp(baseDeps({ getByIdForUser: async () => undefined })).request(
      '/v1/analyses/an-x',
    );
    expect(res.status).toBe(404);
  });

  it('GET /:id joins recommendations into the payload', async () => {
    const res = await makeApp(baseDeps()).request('/v1/analyses/an1');
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.id).toBe('an1');
    expect(body.data.recommendations).toEqual([
      { order: 0, content: '처치 검토', severity: 'warn' },
    ]);
  });

  it('GET /trend returns trend buckets (not caught by /:id)', async () => {
    const res = await makeApp(baseDeps()).request(`/v1/analyses/trend?hiveId=${HIVE}`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data[0].bucket).toBe('2026-06-10');
  });
});

const A = '33333333-3333-3333-3333-333333333333';
const B = '44444444-4444-4444-4444-444444444444';

describe('GET /v1/analyses/aggregate (N장 합산)', () => {
  it('aggregate returns pooled vdi for owned two-stage rows (counts summed, not averaged)', async () => {
    const aggregate = vi.fn(baseDeps().aggregate);
    const countsByIds = vi.fn(async () => [
      { id: A, beeInfested: 1, beeTotal: 40 },
      { id: B, beeInfested: 9, beeTotal: 900 },
    ]);
    const res = await makeApp(baseDeps({ countsByIds, aggregate })).request(
      `/v1/analyses/aggregate?ids=${A},${B}`,
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.bee_total).toBe(940);
    expect(body.data.tier).toBe('low');
    expect(body.data.vdi_display).toBe('1.6'); // AI 표시값 그대로(재반올림 X)
    expect(body.data.n_images).toBe(2);
    expect(body.data.excluded).toEqual({ legacy: 0, insufficient: 0 });
    expect(body.data.analysisIds).toEqual([A, B]);
    expect(countsByIds).toHaveBeenCalledWith([A, B], 'u1');
    // API는 원시 카운트만 넘긴다 — 수식은 AI vdi.aggregate 단일 소스
    expect(aggregate).toHaveBeenCalledWith(
      [
        { bee_infested: 1, bee_total: 40 },
        { bee_infested: 9, bee_total: 900 },
      ],
      'req-1',
    );
  });

  it('aggregate rejects legacy rows without bee counts (none usable → 400)', async () => {
    const aggregate = vi.fn(baseDeps().aggregate);
    const deps = baseDeps({
      countsByIds: async () => [{ id: A, beeInfested: null, beeTotal: null }],
      aggregate,
    });
    const res = await makeApp(deps).request(`/v1/analyses/aggregate?ids=${A}`);
    expect(res.status).toBe(400);
    expect((await res.json()).code).toBe('VALIDATION_FAILED');
    expect(aggregate).not.toHaveBeenCalled();
  });

  it('mixed legacy + two-stage rows: legacy excluded and counted', async () => {
    const aggregate = vi.fn(baseDeps().aggregate);
    const deps = baseDeps({
      countsByIds: async () => [
        { id: A, beeInfested: null, beeTotal: null },
        { id: B, beeInfested: 9, beeTotal: 900 },
      ],
      aggregate,
    });
    const res = await makeApp(deps).request(`/v1/analyses/aggregate?ids=${A},${B}`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.excluded).toEqual({ legacy: 1, insufficient: 0 });
    expect(body.data.n_images).toBe(1);
    expect(body.data.analysisIds).toEqual([B]);
    expect(aggregate.mock.calls[0][0]).toEqual([{ bee_infested: 9, bee_total: 900 }]);
  });

  it('insufficient rows (tier insufficient / bee_total 0) are excluded from pooled counts', async () => {
    const C = '66666666-6666-6666-6666-666666666666';
    const D = '77777777-7777-7777-7777-777777777777';
    const aggregate = vi.fn(baseDeps().aggregate);
    const deps = baseDeps({
      countsByIds: async () => [
        { id: A, beeInfested: 1, beeTotal: 40, tier: 'low' },
        { id: B, beeInfested: 9, beeTotal: 900, tier: 'low' },
        { id: C, beeInfested: 3, beeTotal: 12, tier: 'insufficient' },
        { id: D, beeInfested: 0, beeTotal: 0, tier: null },
      ],
      aggregate,
    });
    const res = await makeApp(deps).request(`/v1/analyses/aggregate?ids=${A},${B},${C},${D}`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.excluded).toEqual({ legacy: 0, insufficient: 2 });
    expect(body.data.n_images).toBe(2);
    expect(body.data.analysisIds).toEqual([A, B]);
    expect(aggregate.mock.calls[0][0]).toEqual([
      { bee_infested: 1, bee_total: 40 },
      { bee_infested: 9, bee_total: 900 },
    ]);
  });

  it('400 when only insufficient rows remain', async () => {
    const deps = baseDeps({
      countsByIds: async () => [{ id: A, beeInfested: 2, beeTotal: 10, tier: 'insufficient' }],
    });
    const res = await makeApp(deps).request(`/v1/analyses/aggregate?ids=${A}`);
    expect(res.status).toBe(400);
  });

  it('404 when any id is not mine / not success (no existence leak)', async () => {
    const deps = baseDeps({ countsByIds: async () => [{ id: A, beeInfested: 1, beeTotal: 40 }] });
    const res = await makeApp(deps).request(`/v1/analyses/aggregate?ids=${A},${B}`);
    expect(res.status).toBe(404);
  });

  it('dedupes ids', async () => {
    const countsByIds = vi.fn(baseDeps().countsByIds);
    const res = await makeApp(baseDeps({ countsByIds })).request(`/v1/analyses/aggregate?ids=${A},${A}`);
    expect(res.status).toBe(200);
    expect(countsByIds).toHaveBeenCalledWith([A], 'u1');
  });

  it('400 on missing / malformed / >10 ids', async () => {
    const app = makeApp(baseDeps());
    expect((await app.request('/v1/analyses/aggregate')).status).toBe(400);
    expect((await app.request('/v1/analyses/aggregate?ids=nope')).status).toBe(400);
    const eleven = Array.from({ length: 11 }, (_, i) => `55555555-5555-5555-5555-5555555555${String(i).padStart(2, '0')}`);
    expect((await app.request(`/v1/analyses/aggregate?ids=${eleven.join(',')}`)).status).toBe(400);
  });

  it('503 when the AI aggregate call fails', async () => {
    const deps = baseDeps({
      aggregate: async () => {
        throw new AppError('AI_UNAVAILABLE', 'down');
      },
    });
    const res = await makeApp(deps).request(`/v1/analyses/aggregate?ids=${A}`);
    expect(res.status).toBe(503);
  });
});

describe('POST /v1/analyses evidence pass-through', () => {
  it('returns AI evidence in data.evidence but does not store it in raw_response', async () => {
    const storeAnalysis = vi.fn(baseDeps().storeAnalysis);
    const evidence: EvidenceItem[] = [
      { index: 3, box: [10, 20, 60, 80], crop_region: [0, 5, 70, 95], p_infested: 0.91, cam: [[0, 0.5], [1, 0.2]] },
    ];
    const deps = baseDeps({
      storeAnalysis,
      analyze: async () => ({
        engine_used: 'yolo',
        tier: 'elevated',
        vdi: 4.2,
        vdi_display: '4.2',
        bee_total: 310,
        bee_infested: 14,
        recommendations: [],
        model_versions: { stage1: 's1', stage2: 's2', vdi_config: 'v' },
        risk_score: 40,
        evidence,
      }),
    });
    const res = await post(makeApp(deps), { hiveId: HIVE, imageId: IMAGE });
    expect(res.status).toBe(201);
    expect((await res.json()).data.evidence).toEqual(evidence);
    const raw = storeAnalysis.mock.calls[0][0].analysis.rawResponse as Record<string, unknown>;
    expect(raw.evidence).toBeUndefined();
  });

  it('evidence is null when the AI sends none (legacy contract)', async () => {
    const res = await post(makeApp(baseDeps()), { hiveId: HIVE, imageId: IMAGE });
    expect((await res.json()).data.evidence).toBeNull();
  });
});
