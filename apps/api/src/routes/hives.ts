/**
 * Hives 라우트 (backend-design §9). 양봉가 벌통 CRUD.
 * - 모든 라우트 requireAuth(app.ts protectedMount) + 소유권 IDOR 차단(비소유→404, 존재 누설 X).
 * - DI로 외부(DB·Redis) 분리. DB 접근은 queries.hives.* 만(라우트는 deps 경유).
 * - GET 목록만 best-effort 캐싱(기본 페이지). write 시 즉시 invalidate.
 */
import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { getClientIp } from '../lib/client-ip';
import { created, ok } from '../lib/envelope';
import { problem } from '../lib/problem';
import {
  createHiveSchema,
  hiveIdParam,
  listHivesQuery,
  updateHiveSchema,
} from '../schemas/hives';

const CACHE_DEFAULT_LIMIT = 50; // 기본 페이지(offset 0)만 캐시 — 단일 키 invalidate(§9.6)

export type HivesDeps = {
  list(userId: string, opts: { limit: number; offset: number }): Promise<unknown[]>;
  create(
    userId: string,
    input: {
      name: string;
      note?: string;
      latitude?: number;
      longitude?: number;
      address?: string;
      installedAt?: Date;
    },
  ): Promise<unknown>;
  getById(hiveId: string, userId: string): Promise<unknown | undefined>;
  update(
    hiveId: string,
    userId: string,
    patch: Record<string, unknown>,
  ): Promise<unknown | undefined>;
  softDelete(
    hiveId: string,
    userId: string,
  ): Promise<{ id: string; deletedAt: Date | null } | undefined>;
  // best-effort 캐시 (Redis 장애 시 null/no-op — 가용성 우선)
  cacheGet(userId: string): Promise<unknown[] | null>;
  cacheSet(userId: string, rows: unknown[]): Promise<void>;
  cacheInvalidate(userId: string): Promise<void>;
  // soft delete만 감사(선택)
  audit(entry: {
    actorId: string;
    action: string;
    entity: string;
    entityId: string;
    ip: string | null;
    userAgent: string | null;
  }): Promise<void>;
};

export function hivesRoutes(deps: HivesDeps) {
  const app = new Hono();

  // GET /v1/hives — 목록 (기본 페이지는 캐시 hit/set)
  app.get('/', zValidator('query', listHivesQuery), async (c) => {
    const userId = c.get('userId') as string;
    const { limit, offset } = c.req.valid('query');
    const isDefaultPage = offset === 0 && limit === CACHE_DEFAULT_LIMIT;

    if (isDefaultPage) {
      const cached = await deps.cacheGet(userId);
      if (cached) {
        return ok(c, cached, { pagination: { limit, offset, total: cached.length } });
      }
    }
    const rows = await deps.list(userId, { limit, offset });
    if (isDefaultPage) await deps.cacheSet(userId, rows);
    return ok(c, rows, { pagination: { limit, offset, total: rows.length } });
  });

  // POST /v1/hives — 생성
  app.post('/', zValidator('json', createHiveSchema), async (c) => {
    const userId = c.get('userId') as string;
    const body = c.req.valid('json');
    const hive = await deps.create(userId, body);
    await deps.cacheInvalidate(userId);
    return created(c, hive);
  });

  // GET /v1/hives/:id — 단일 (소유 검증, 비소유 404)
  app.get('/:id', zValidator('param', hiveIdParam), async (c) => {
    const userId = c.get('userId') as string;
    const { id } = c.req.valid('param');
    const hive = await deps.getById(id, userId);
    if (!hive) return problem(c, 'NOT_FOUND');
    return ok(c, hive);
  });

  // PATCH /v1/hives/:id — 부분 수정 (소유 검증, 비소유 404)
  app.patch('/:id', zValidator('param', hiveIdParam), zValidator('json', updateHiveSchema), async (c) => {
    const userId = c.get('userId') as string;
    const { id } = c.req.valid('param');
    const patch = c.req.valid('json');
    const hive = await deps.update(id, userId, patch);
    if (!hive) return problem(c, 'NOT_FOUND');
    await deps.cacheInvalidate(userId);
    return ok(c, hive);
  });

  // DELETE /v1/hives/:id — soft delete (소유 검증, 비소유 404)
  app.delete('/:id', zValidator('param', hiveIdParam), async (c) => {
    const userId = c.get('userId') as string;
    const { id } = c.req.valid('param');
    const result = await deps.softDelete(id, userId);
    if (!result) return problem(c, 'NOT_FOUND');
    await deps.cacheInvalidate(userId);
    await deps.audit({
      actorId: userId,
      action: 'hive.deleted',
      entity: 'hive',
      entityId: id,
      ip: getClientIp(c),
      userAgent: c.req.header('user-agent') ?? null,
    });
    return ok(c, { id: result.id, deletedAt: result.deletedAt });
  });

  return app;
}
