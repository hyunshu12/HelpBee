/**
 * AI 추론 서비스 클라이언트 (Hybrid C, backend-design §3.2 / §3.8 / D10).
 * - api=정책/저장, ai=추론. api는 presigned GET URL + engine을 전달(바이너리 프록시 X).
 * - 내부 인증: 단기 HMAC 서명 bearer(aud=ai, exp~5m, request_id 바인딩) — D10.
 * - 추론 호출(/analyze)은 **자동 재시도 없음**(중복 추론/과금 방지). 전송 실패→AI_UNAVAILABLE.
 *   (지수 백오프 재시도는 presign/confirm 같은 멱등 GET/HEAD에만 — 별도.)
 */
import { createHmac, timingSafeEqual } from 'node:crypto';

import { AppError } from '../lib/error-codes';

export type InternalPayload = { iss: string; aud: string; exp: number; request_id: string };

function b64url(input: string): string {
  return Buffer.from(input).toString('base64url');
}
function sign(secret: string, body: string): string {
  return createHmac('sha256', secret).update(body).digest('base64url');
}

export function signInternalBearer(
  secret: string,
  opts: { requestId: string; ttlSec?: number; audience?: string },
): string {
  const payload: InternalPayload = {
    iss: 'api',
    aud: opts.audience ?? 'ai',
    exp: Math.floor(Date.now() / 1000) + (opts.ttlSec ?? 300),
    request_id: opts.requestId,
  };
  const body = b64url(JSON.stringify(payload));
  return `${body}.${sign(secret, body)}`;
}

export function verifyInternalBearer(secret: string, token: string): InternalPayload {
  const [body, sig] = token.split('.');
  if (!body || !sig) {
    throw new AppError('AUTH_UNAUTHORIZED', 'malformed internal token');
  }
  const expected = sign(secret, body);
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    throw new AppError('AUTH_UNAUTHORIZED', 'bad internal signature');
  }
  const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')) as InternalPayload;
  if (typeof payload.exp !== 'number' || Date.now() / 1000 > payload.exp) {
    throw new AppError('AUTH_UNAUTHORIZED', 'internal token expired');
  }
  return payload;
}

export type AiEngine = 'auto' | 'yolo';

export type AiAnalysisResult = {
  risk_score: number | null;
  tier: string;
  estimated_count?: number | null;
  confidence?: number;
  recommendations: string[];
  model_version: string;
  prompt_version?: string | null;
  latency_ms?: number;
  cost_estimate_usd?: number | null;
  engine_used: string | null;
  fallback_reason?: string | null;
  raw_payload?: Record<string, unknown>;
};

export type HttpLike = {
  post: (url: string, body: unknown, config: Record<string, unknown>) => Promise<{ data: unknown }>;
};

export function createAiClient(cfg: {
  baseURL: string;
  hmacSecret: string;
  http: HttpLike;
  timeoutMs?: number;
}) {
  const timeout = cfg.timeoutMs ?? 30_000;
  return {
    async analyze(input: {
      imageUrl: string;
      engine: AiEngine;
      requestId: string;
    }): Promise<AiAnalysisResult> {
      const bearer = signInternalBearer(cfg.hmacSecret, { requestId: input.requestId });
      try {
        const res = await cfg.http.post(
          '/analyze',
          { image_url: input.imageUrl, engine: input.engine },
          {
            baseURL: cfg.baseURL,
            timeout,
            headers: {
              authorization: `Bearer ${bearer}`,
              'x-request-id': input.requestId,
            },
          },
        );
        return res.data as AiAnalysisResult;
      } catch {
        // 무재시도: 전송/5xx/타임아웃 모두 즉시 AI_UNAVAILABLE (라우트가 graceful 저장 처리)
        throw new AppError('AI_UNAVAILABLE', 'ai service request failed');
      }
    },
  };
}
