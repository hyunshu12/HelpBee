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
  createAnalysisSchema,
  listAnalysesQuerySchema,
  trendQuerySchema,
} from '../schemas/analyses';

type Tier = 'safe' | 'watch' | 'danger';

export type AiResult = {
  risk_score: number | null;
  tier: string;
  estimated_count?: number | null;
  recommendations: string[];
  engine_used: string | null;
  latency_ms?: number;
  cost_estimate_usd?: number | null;
  raw_payload?: Record<string, unknown>;
};

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
  getEmailVerifiedAt(userId: string): Promise<Date | null | undefined>;
  getPlan(userId: string): Promise<'free' | 'basic' | 'pro'>;
  reserveQuota(userId: string): Promise<void>; // 초과 시 AppError('QUOTA_EXCEEDED') throw
  refundQuota(userId: string): Promise<void>;
  presignGet(objectKey: string): Promise<string>;
  resolveModelId(provider: 'yolo' | 'openai'): Promise<string | undefined>;
  analyze(input: { imageUrl: string; engine: 'auto' | 'yolo'; requestId: string }): Promise<AiResult>;
  storeAnalysis(input: StoreAnalysisInput): Promise<unknown>;
  listForUser(
    hiveId: string,
    userId: string,
    opts: { limit: number; offset: number },
  ): Promise<unknown[]>;
  getByIdForUser(id: string, userId: string): Promise<unknown | undefined>;
  getTrend(hiveId: string, userId: string, from: Date, to: Date): Promise<unknown[]>;
};

const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

const HEALTH: Record<Tier, string> = { safe: 'healthy', watch: 'warning', danger: 'critical' };
const SEVERITY: Record<Tier, string> = { safe: 'info', watch: 'warn', danger: 'danger' };

function toRecommendations(tier: Tier, list: string[]) {
  return list.slice(0, 5).map((content, i) => ({ order: i, content, severity: SEVERITY[tier] }));
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
    if (existing) return ok(c, existing);

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
    const failed = !result || result.engine_used === null || result.risk_score === null;

    // ⑤-a 실패: 무료면 환불, status=failed 저장, graceful 200(비차단)
    if (failed) {
      if (isFree) await deps.refundQuota(userId);
      const modelId = (await deps.resolveModelId('yolo')) ?? '';
      const row = await deps.storeAnalysis({
        hiveId,
        imageId,
        modelId,
        analysis: {
          status: 'failed',
          varroaInfectionRisk: null,
          estimatedVarroaCount: null,
          overallHealth: null,
          rawResponse: result?.raw_payload ?? { error_reason: 'ai_unavailable' },
          latencyMs: result?.latency_ms ?? null,
          error: 'ai_unavailable',
          analyzedAt,
        },
        recommendations: [],
      });
      return ok(c, row);
    }

    // ⑤-b 성공: engine_used→model_id, 1행 저장, created(201)
    const tier = result!.tier as Tier;
    const provider = result!.engine_used as 'yolo' | 'openai';
    const modelId = await deps.resolveModelId(provider);
    if (!modelId) return problem(c, 'AI_UNAVAILABLE'); // 모델 메타 없음(seed/매핑 오류)
    const row = await deps.storeAnalysis({
      hiveId,
      imageId,
      modelId,
      analysis: {
        status: 'success',
        varroaInfectionRisk: result!.risk_score,
        estimatedVarroaCount: result!.estimated_count ?? null,
        overallHealth: HEALTH[tier] ?? null,
        rawResponse: result!.raw_payload ?? null,
        latencyMs: result!.latency_ms ?? null,
        error: null,
        analyzedAt,
      },
      recommendations: toRecommendations(tier, result!.recommendations ?? []),
    });
    return created(c, row);
  });

  app.get('/', zValidator('query', listAnalysesQuerySchema), async (c) => {
    const userId = c.get('userId') as string;
    const { hiveId, limit, offset } = c.req.valid('query');
    const rows = await deps.listForUser(hiveId, userId, { limit, offset });
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

  app.get('/:id', async (c) => {
    const userId = c.get('userId') as string;
    const row = await deps.getByIdForUser(c.req.param('id'), userId);
    if (!row) return problem(c, 'NOT_FOUND');
    return ok(c, row);
  });

  return app;
}
