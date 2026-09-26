/**
 * analyses 라우트 (backend-design §2 동기 오케스트레이션).
 * POST /v1/analyses: 소유권 → 멱등 short-circuit → 무료(이메일검증·quota reserve) →
 *   plan별 engine → presigned GET → ai-client → engine_used→model_id → 저장 →
 *   성공 created(201) / 실패 graceful(200, refund). GET list/:id.
 *
 * 의존성 주입(DI)으로 외부(DB·AI·quota·S3)와 분리 → 목으로 오케스트레이션 단위 검증.
 * app.ts가 실제 구현(@helpbee/database queries, services/*)을 주입.
 */
import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { created, ok } from '../lib/envelope';
import { problem } from '../lib/problem';
import {
  aggregateQuerySchema,
  createAnalysisSchema,
  listAnalysesQuerySchema,
  trendQuerySchema,
} from '../schemas/analyses';

import type { AiAggregateResult, AiAnalysisResult, BeeCount, Tier } from '../services/ai-client';

/**
 * 라우트가 받는 AI 결과. ai-client 계약(AiAnalysisResult)을 따르되 DI 경계에서 관용적으로:
 * tier는 미지의 값도 허용(→ overall_health null, severity info), model_version은 선택.
 */
export type AiResult = Omit<AiAnalysisResult, 'tier' | 'model_version'> & {
  tier: Tier | (string & {});
  model_version?: string;
};

/** 결과를 낸 파이프라인 — model_versions 유무로 판별 → ai_models 행 선택 (스펙 §8-1). */
export type ModelPipeline = 'two-stage' | 'v1';

export type StoreAnalysisInput = {
  hiveId: string;
  imageId: string;
  modelId: string;
  analysis: Record<string, unknown>;
  recommendations: { order: number; content: string; severity: string }[];
};

export type AnalysesDeps = {
  getImageForUser(
    imageId: string,
    userId: string,
  ): Promise<{ id: string; hiveId: string; storageUrl: string } | undefined>;
  findSuccessByImage(imageId: string, userId: string): Promise<unknown | undefined>;
  /** 재시도 후보: 해당 이미지의 failed 분석(있으면 제자리 UPDATE 대상). */
  findFailedByImage(imageId: string, userId: string): Promise<{ id: string } | undefined>;
  getEmailVerifiedAt(userId: string): Promise<Date | null | undefined>;
  getPlan(userId: string): Promise<'free' | 'basic' | 'pro'>;
  reserveQuota(userId: string): Promise<void>; // 초과 시 AppError('QUOTA_EXCEEDED') throw
  refundQuota(userId: string): Promise<void>;
  presignGet(objectKey: string): Promise<string>;
  resolveModelId(provider: 'yolo' | 'openai', pipeline?: ModelPipeline): Promise<string | undefined>;
  analyze(input: { imageUrl: string; engine: 'auto' | 'yolo'; requestId: string }): Promise<AiResult>;
  storeAnalysis(input: StoreAnalysisInput): Promise<unknown>;
  /** failed 행 제자리 재실행: id 보존, 결과/권장조치 갱신. CAS(WHERE status='failed'). */
  retryAnalysis(input: {
    analysisId: string;
    modelId: string;
    analysis: Record<string, unknown>;
    recommendations: { order: number; content: string; severity: string }[];
  }): Promise<unknown>;
  /** hiveId=undefined → 내 모든 벌통의 이력(진단 이력 탭). 지정 시 해당 벌통만. */
  listForUser(
    hiveId: string | undefined,
    userId: string,
    opts: { limit: number; offset: number },
  ): Promise<unknown[]>;
  getByIdForUser(id: string, userId: string): Promise<unknown | undefined>;
  getRecommendations(
    analysisId: string,
  ): Promise<{ order: number; content: string; severity: string }[]>;
  getTrend(hiveId: string, userId: string, from: Date, to: Date): Promise<unknown[]>;
  /** N장 합산 원천: 내 소유 + status=success 분석의 원시 카운트(구 row는 null). 비소유/미존재 id는 빠진다. */
  countsByIds(
    ids: string[],
    userId: string,
  ): Promise<
    { id: string; beeInfested: number | null; beeTotal: number | null; tier?: string | null }[]
  >;
  /** AI POST /aggregate — 수식(합산·보정·CI·tier)의 단일 소스. 재시도 없음. */
  aggregate(counts: BeeCount[], requestId: string): Promise<AiAggregateResult>;
};

const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

// 구 계약(safe/watch/danger) + two-stage 계약(low/elevated/high/insufficient) 양립 (스펙 §3·§8-1).
// insufficient(벌 0마리·판독 불가)는 건강 판정 불가 → overall_health null, severity info.
const HEALTH: Record<Tier, string | null> = {
  safe: 'healthy',
  watch: 'warning',
  danger: 'critical',
  low: 'healthy',
  elevated: 'warning',
  high: 'critical',
  insufficient: null,
};
const SEVERITY: Record<Tier, string> = {
  safe: 'info',
  watch: 'warn',
  danger: 'danger',
  low: 'info',
  elevated: 'warn',
  high: 'danger',
  insufficient: 'info',
};

function healthFor(tier: string): string | null {
  return Object.prototype.hasOwnProperty.call(HEALTH, tier) ? HEALTH[tier as Tier] : null;
}
function severityFor(tier: string): string {
  return Object.prototype.hasOwnProperty.call(SEVERITY, tier) ? SEVERITY[tier as Tier] : 'info';
}

type Recommendation = { order: number; content: string; severity: string };

function toRecommendations(tier: string, list: string[]): Recommendation[] {
  const severity = severityFor(tier);
  return list.slice(0, 5).map((content, i) => ({ order: i, content, severity }));
}

// numeric(6,3) 컬럼은 드라이버가 문자열로 반환 → 응답에선 number로 직렬화(클라이언트 파싱 부담 제거).
// 값 자체는 AI가 준 그대로 — 재반올림하지 않는다(표시값은 AI의 vdi_display가 단일 소스).
const NUMERIC_KEYS = ['vdi', 'vdiCiLow', 'vdiCiHigh'] as const;

function toNum(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const n = typeof v === 'string' ? Number(v) : (v as number);
  return typeof n === 'number' && Number.isFinite(n) ? n : null;
}

/**
 * raw_response가 이 라우트가 저장한 "AI 정규화 결과"인지 판별.
 * 구 row의 raw_response는 AI raw_payload(engine_used 키 없음)라 새 필드로 오인하지 않는다.
 */
function normalizedResult(raw: unknown): Record<string, unknown> | null {
  return raw && typeof raw === 'object' && !Array.isArray(raw) && 'engine_used' in raw
    ? (raw as Record<string, unknown>)
    : null;
}

/**
 * 응답 row 정규화 + two-stage 표시 필드 투영 (스펙 §3; 구 row는 전부 null).
 * - 숫자(vdi·beeTotal·beeInfested·samplingCi95)는 컬럼에서,
 * - AI 문자열/객체(vdiDisplay·tier·corrected·quality·modelVersions)는 raw_response에서 읽는다.
 */
function normalizeRow(row: unknown): Record<string, unknown> {
  const r = { ...(row as Record<string, unknown>) };
  for (const k of NUMERIC_KEYS) {
    if (typeof r[k] === 'string') r[k] = Number(r[k]);
  }
  const raw = normalizedResult(r.rawResponse);
  const ciLow = toNum(r.vdiCiLow);
  const ciHigh = toNum(r.vdiCiHigh);
  return {
    ...r,
    vdi: toNum(r.vdi),
    vdiDisplay: (raw?.vdi_display as string | null | undefined) ?? null,
    tier: (raw?.tier as string | undefined) ?? null,
    corrected: (raw?.corrected as boolean | undefined) ?? null,
    beeTotal: toNum(r.beeTotal),
    beeInfested: toNum(r.beeInfested),
    samplingCi95: ciLow !== null && ciHigh !== null ? [ciLow, ciHigh] : null,
    quality: (raw?.quality as Record<string, unknown> | undefined) ?? null,
    modelVersions: (raw?.model_versions as Record<string, unknown> | undefined) ?? null,
  };
}

/** 분석 row에 recommendations 배열을 실어 응답 페이로드로 만든다(계약: §4). */
function withRecs(row: unknown, recs: Recommendation[]) {
  return { ...normalizeRow(row), recommendations: recs };
}

export function analysesRoutes(deps: AnalysesDeps) {
  const app = new Hono();

  app.post('/', zValidator('json', createAnalysisSchema), async (c) => {
    const userId = c.get('userId') as string;
    const requestId = (c.get('requestId') as string) ?? '';
    const { hiveId, imageId } = c.req.valid('json');

    // ① 소유권·일치 검증 (비소유는 NOT_FOUND로 존재 누설 차단)
    const image = await deps.getImageForUser(imageId, userId);
    if (!image || image.hiveId !== hiveId) return problem(c, 'NOT_FOUND');

    // ② 멱등 short-circuit (중복 제출 → 기존 success 반환, 재추론·재과금 X)
    const existing = await deps.findSuccessByImage(imageId, userId);
    if (existing) {
      const recs = await deps.getRecommendations((existing as { id: string }).id);
      return ok(c, withRecs(existing, recs));
    }

    // ②' 재시도: 같은 이미지의 failed 행이 있으면 새 row 대신 그 행을 제자리 갱신.
    //     (UNIQUE(image_id, model_id) + onConflictDoNothing이라 insert로는 절대 못 고침)
    //     quota/engine 흐름은 신규와 동일 — failed는 quota를 소비하지 않은 상태이므로
    //     재시도도 동일한 reserve/refund 경로를 탄다.
    const failedRow = await deps.findFailedByImage(imageId, userId);
    const isRetry = !!failedRow;

    // ③ 무료: 이메일 검증 게이트 + quota reserve(reserve-then-refund)
    const plan = await deps.getPlan(userId);
    const isFree = plan === 'free';
    if (isFree) {
      const emailVerifiedAt = await deps.getEmailVerifiedAt(userId);
      if (!emailVerifiedAt) return problem(c, 'AUTH_EMAIL_NOT_VERIFIED');
      await deps.reserveQuota(userId); // QUOTA_EXCEEDED → error-handler 402
    }

    // ④ plan별 engine (무료=YOLO 단독, 유료=auto 폴백) → presigned GET → ai 위임
    const engine: 'auto' | 'yolo' = isFree ? 'yolo' : 'auto';
    const imageUrl = await deps.presignGet(image.storageUrl);

    let result: AiResult | null = null;
    try {
      result = await deps.analyze({ imageUrl, engine, requestId });
    } catch {
      result = null; // AI_UNAVAILABLE (무재시도)
    }

    const analyzedAt = new Date();
    // 실패 = 결과 없음(AI_UNAVAILABLE) 또는 engine_used null(AI graceful 실패)뿐.
    // two-stage 계약은 risk_score가 null일 수 있으므로 risk_score 누락만으로는 실패가 아니다(스펙 §8-1).
    const failed = !result || result.engine_used === null;

    // ⑤-a 실패: 무료면 환불, status=failed 저장, graceful 200(비차단)
    if (failed) {
      if (isFree) await deps.refundQuota(userId);
      const modelId = (await deps.resolveModelId('yolo', 'v1')) ?? '';
      const analysis = {
        status: 'failed',
        varroaInfectionRisk: null,
        estimatedVarroaCount: null,
        overallHealth: null,
        vdi: null,
        vdiCiLow: null,
        vdiCiHigh: null,
        beeTotal: null,
        beeInfested: null,
        rawResponse: result?.raw_payload ?? { error_reason: 'ai_unavailable' },
        latencyMs: result?.latency_ms ?? null,
        error: 'ai_unavailable',
        analyzedAt,
      };
      // 재시도면 기존 failed 행을 제자리 갱신(id 보존, fresh error/analyzedAt), 신규면 insert.
      if (isRetry) {
        const row = await deps.retryAnalysis({
          analysisId: failedRow!.id,
          modelId,
          analysis,
          recommendations: [],
        });
        const recs = await deps.getRecommendations((row as { id: string }).id);
        return ok(c, withRecs(row, recs));
      }
      const row = await deps.storeAnalysis({ hiveId, imageId, modelId, analysis, recommendations: [] });
      return ok(c, withRecs(row, []));
    }

    // ⑤-b 성공: engine_used→model_id, 1행 저장(신규 201) 또는 failed 행 갱신(재시도 200)
    // tier는 AI가 vdi_display에서만 계산해 보낸 값 — API는 vdi로 재계산/재반올림하지 않는다.
    const res = result!;
    const tier = res.tier;
    const provider = res.engine_used as 'yolo' | 'openai';
    const pipeline: ModelPipeline = res.model_versions ? 'two-stage' : 'v1';
    const modelId = await deps.resolveModelId(provider, pipeline);
    if (!modelId) return problem(c, 'AI_UNAVAILABLE'); // 모델 메타 없음(seed/매핑 오류)
    const recs = toRecommendations(tier, res.recommendations ?? []);
    // 시각 증거(CAM top-k)는 응답으로만 전달 — 부피가 커서 raw_response에 저장하지 않는다(재조회 시 null).
    const evidence = res.evidence ?? null;
    const analysis = {
      status: 'success',
      // 이중 출력 기간: AI가 score_mapping(vdi)로 채운 점수 단위 그대로 저장(round(vdi) 금지).
      varroaInfectionRisk: res.risk_score ?? null,
      estimatedVarroaCount: res.estimated_count ?? null,
      overallHealth: healthFor(tier),
      vdi: res.vdi ?? null,
      vdiCiLow: res.sampling_ci95?.[0] ?? null,
      vdiCiHigh: res.sampling_ci95?.[1] ?? null,
      beeTotal: res.bee_total ?? null,
      beeInfested: res.bee_infested ?? null,
      // AI 정규화 결과 전체를 보존(tier·vdi_display·quality·model_versions 등 재조회용).
      // 부피 큰 벌 단위/CAM 배열(bees·evidence)만 제외 — evidence는 POST 응답 data.evidence로만 전달.
      rawResponse: { ...res, bees: undefined, evidence: undefined, raw_payload: res.raw_payload },
      latencyMs: res.latency_ms ?? null,
      error: null,
      analyzedAt,
    };
    if (isRetry) {
      // 재시도 성공: 같은 id를 success로 승격 + recommendations 교체 → 200(갱신).
      const row = await deps.retryAnalysis({
        analysisId: failedRow!.id,
        modelId,
        analysis,
        recommendations: recs,
      });
      const finalRecs = await deps.getRecommendations((row as { id: string }).id);
      return ok(c, { ...withRecs(row, finalRecs), evidence });
    }
    const row = await deps.storeAnalysis({ hiveId, imageId, modelId, analysis, recommendations: recs });
    return created(c, { ...withRecs(row, recs), evidence });
  });

  app.get('/', zValidator('query', listAnalysesQuerySchema), async (c) => {
    const userId = c.get('userId') as string;
    const { hiveId, limit, offset } = c.req.valid('query');
    const rows = (await deps.listForUser(hiveId, userId, { limit, offset })).map(normalizeRow);
    return ok(c, rows, { pagination: { limit, offset, total: rows.length } });
  });

  // /:id 보다 먼저 등록 (정적 경로 우선)
  app.get('/trend', zValidator('query', trendQuerySchema), async (c) => {
    const userId = c.get('userId') as string;
    const { hiveId, from, to } = c.req.valid('query');
    const toDate = to ? new Date(to) : new Date();
    const fromDate = from ? new Date(from) : new Date(toDate.getTime() - THIRTY_DAYS_MS);
    const trend = await deps.getTrend(hiveId, userId, fromDate, toDate);
    return ok(c, trend);
  });

  // N장 합산 (스펙 §8-1): 저장은 이미지당 row, 읽기 시 Σk/Σn 원시 카운트로 재계산.
  // 퍼센트 평균 금지(저장 vdi는 clip돼 역산 불가) — 수식은 AI /aggregate(vdi.aggregate)가 단일 소스.
  // tier·vdi_display는 AI 값 그대로(재반올림 X). 구 row·insufficient row는 제외하고 excluded{legacy,insufficient}로 보고.
  app.get('/aggregate', zValidator('query', aggregateQuerySchema), async (c) => {
    const userId = c.get('userId') as string;
    const requestId = (c.get('requestId') as string) ?? '';
    const ids = [...new Set(c.req.valid('query').ids)];
    const rows = await deps.countsByIds(ids, userId);
    // 비소유·미존재·비success가 하나라도 있으면 NOT_FOUND(존재 누설 차단, §13)
    if (rows.length !== ids.length) return problem(c, 'NOT_FOUND');
    // 제외 사유: legacy = 구 row(카운트 null) / insufficient = 품질 실패·벌 0(tier insufficient 또는 beeTotal 0).
    // 풀링 결과는 판독 가능한 프레임만으로 계산 → AI 호출은 quality_ok=true 유지.
    const excluded = { legacy: 0, insufficient: 0 };
    const usable: { id: string; beeInfested: number; beeTotal: number }[] = [];
    for (const r of rows) {
      if (r.beeTotal === null || r.beeInfested === null) excluded.legacy += 1;
      else if (r.tier === 'insufficient' || r.beeTotal === 0) excluded.insufficient += 1;
      else usable.push({ id: r.id, beeInfested: r.beeInfested, beeTotal: r.beeTotal });
    }
    if (usable.length === 0) {
      return problem(c, 'VALIDATION_FAILED', 'no usable two-stage analyses with bee counts among ids');
    }
    const byId = new Map(usable.map((r) => [r.id, r]));
    const ordered = ids.filter((id) => byId.has(id)).map((id) => byId.get(id)!);
    const result = await deps.aggregate(
      ordered.map((r) => ({ bee_infested: r.beeInfested, bee_total: r.beeTotal })),
      requestId,
    );
    return ok(c, {
      ...result,
      n_images: ordered.length,
      excluded,
      analysisIds: ordered.map((r) => r.id),
    });
  });

  app.get('/:id', async (c) => {
    const userId = c.get('userId') as string;
    const row = await deps.getByIdForUser(c.req.param('id'), userId);
    if (!row) return problem(c, 'NOT_FOUND');
    const recs = await deps.getRecommendations((row as { id: string }).id);
    return ok(c, withRecs(row, recs));
  });

  return app;
}
