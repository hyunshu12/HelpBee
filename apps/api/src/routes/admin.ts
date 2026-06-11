/**
 * Admin 라우트 (backend-design §12). app.ts에서 requireAuth + requireAdmin(role+audience)로 단일 마운트.
 * - 모든 mutation은 audit 동일 트랜잭션(쿼리 계층) + 차단 시 즉시 회수(sessions bump + refresh 폐기).
 * - dual 비교는 raw_response 화이트리스트 투영(bbox/score/tier만 — PII/URL/GPS 차단, §12.6/§13 API3).
 * - SelfDemoteError → ADMIN_SELF_DEMOTE_FORBIDDEN 매핑은 app.ts 어댑터에서.
 */
import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { getClientIp } from '../lib/client-ip';
import { ok } from '../lib/envelope';
import { problem } from '../lib/problem';
import { idParamSchema } from '../schemas/common';
import {
  adminUserListQuery,
  adminUserPatchBody,
  auditLogQuery,
  imageIdParam,
  metricsQuery,
} from '../schemas/admin';

const RAW_ALLOWLIST = new Set([
  'bbox',
  'boxes',
  'score',
  'risk_score',
  'tier',
  'count',
  'estimated_count',
  'confidence',
]);

/** raw_response 화이트리스트 투영 — URL/GPS/PII/base64 등은 drop(이중 방어, §12.6). */
function sanitizeRaw(raw: Record<string, unknown> | null): Record<string, unknown> | null {
  if (!raw) return null;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(raw)) {
    if (RAW_ALLOWLIST.has(k)) out[k] = v;
  }
  return out;
}

export type DualRow = {
  provider: string;
  modelName: string;
  modelVersion: string;
  status: string;
  varroaInfectionRisk: number | null;
  overallHealth: string | null;
  rawResponse: Record<string, unknown> | null;
};

export type AdminDeps = {
  listUsers(opts: {
    page: number;
    pageSize: number;
    search?: string;
    role?: 'user' | 'admin';
    status?: 'active' | 'blocked' | 'deleted';
  }): Promise<{ rows: unknown[]; total: number }>;
  patchUser(input: {
    userId: string;
    role?: 'user' | 'admin';
    status?: 'active' | 'blocked';
    actorId: string;
    ip: string | null;
    userAgent: string | null;
  }): Promise<{ detail: unknown; blockedNow: boolean } | undefined>; // SelfDemote → AppError(adapter)
  onBlocked(userId: string): Promise<void>; // sessions bump + refresh 일괄 폐기
  listAuditLogs(opts: {
    cursor?: bigint;
    limit: number;
    entity?: string;
    action?: string;
    actorId?: string;
    from?: Date;
    to?: Date;
  }): Promise<{ rows: unknown[]; nextCursor: string | null }>;
  metrics(): Promise<unknown>;
  getDualByImage(imageId: string): Promise<DualRow[]>;
};

export function adminRoutes(deps: AdminDeps) {
  const app = new Hono();

  // GET /v1/admin/users
  app.get('/users', zValidator('query', adminUserListQuery), async (c) => {
    const q = c.req.valid('query');
    const { rows, total } = await deps.listUsers(q);
    return ok(c, rows, { pagination: { limit: q.pageSize, offset: (q.page - 1) * q.pageSize, total } });
  });

  // PATCH /v1/admin/users/:id
  app.patch(
    '/users/:id',
    zValidator('param', idParamSchema),
    zValidator('json', adminUserPatchBody),
    async (c) => {
      const { id } = c.req.valid('param');
      const { role, status } = c.req.valid('json');
      const actorId = c.get('userId') as string;
      const result = await deps.patchUser({
        userId: id,
        role,
        status,
        actorId,
        ip: getClientIp(c),
        userAgent: c.req.header('user-agent') ?? null,
      });
      if (!result) return problem(c, 'NOT_FOUND');
      if (result.blockedNow) await deps.onBlocked(id);
      return ok(c, result.detail);
    },
  );

  // GET /v1/admin/audit-logs (cursor keyset)
  app.get('/audit-logs', zValidator('query', auditLogQuery), async (c) => {
    const q = c.req.valid('query');
    const { rows, nextCursor } = await deps.listAuditLogs(q);
    return ok(c, { items: rows, nextCursor });
  });

  // GET /v1/admin/metrics
  app.get('/metrics', zValidator('query', metricsQuery), async (c) => {
    return ok(c, await deps.metrics());
  });

  // GET /v1/admin/analyses/:imageId/dual
  app.get('/analyses/:imageId/dual', zValidator('param', imageIdParam), async (c) => {
    const { imageId } = c.req.valid('param');
    const rows = await deps.getDualByImage(imageId);
    if (rows.length === 0) return problem(c, 'NOT_FOUND');
    const projected = rows.map((r) => ({ ...r, rawResponse: sanitizeRaw(r.rawResponse) }));
    const primary = projected.find((r) => r.provider === 'yolo') ?? projected[0]!;
    const secondary = projected.find((r) => r !== primary) ?? null;
    const agreement = secondary
      ? {
          healthMatch: primary.overallHealth === secondary.overallHealth,
          riskDiff:
            primary.varroaInfectionRisk != null && secondary.varroaInfectionRisk != null
              ? Math.abs(primary.varroaInfectionRisk - secondary.varroaInfectionRisk)
              : null,
        }
      : null;
    return ok(c, { primary, secondary, agreement });
  });

  return app;
}
