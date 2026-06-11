/**
 * Admin 쿼리 헬퍼 (backend-design §12). 직접 SQL/스프레드 금지, 파라미터 바인딩(Drizzle).
 * - status는 파생(deleted_at/blocked_at). users에 status 컬럼 없음(§12.5).
 * - patchUser: self-demote 가드(FOR UPDATE count) + 변경 시 audit를 동일 트랜잭션(§12.7, §12.8).
 * - audit_log.id(bigint)는 문자열 직렬화(2^53 초과 안전, §12.4).
 */
import { and, count, desc, eq, gte, ilike, isNotNull, isNull, lt, lte, or } from 'drizzle-orm';

import type { Database } from '../client';
import { aiModels } from '../schema/aiModels';
import { analyses } from '../schema/analyses';
import { auditLog } from '../schema/auditLog';
import { hives } from '../schema/hives';
import { subscriptions } from '../schema/subscriptions';
import { users } from '../schema/users';
import { insertAuditLog } from './auditLog';

/** 마지막 admin 강등 차단 신호 — 라우트가 ADMIN_SELF_DEMOTE_FORBIDDEN으로 매핑. */
export class SelfDemoteError extends Error {
  constructor() {
    super('cannot remove last admin');
    this.name = 'SelfDemoteError';
  }
}

type DerivedStatus = 'active' | 'blocked' | 'deleted';
function deriveStatus(u: { deletedAt: Date | null; blockedAt: Date | null }): DerivedStatus {
  if (u.deletedAt) return 'deleted';
  if (u.blockedAt) return 'blocked';
  return 'active';
}

export type AdminUserRow = {
  id: string;
  email: string;
  name: string;
  role: string;
  status: DerivedStatus;
  emailVerifiedAt: string | null;
  createdAt: string;
  plan: string | null;
};

export async function listUsers(
  db: Database,
  opts: {
    page: number;
    pageSize: number;
    search?: string;
    role?: 'user' | 'admin';
    status?: DerivedStatus;
  },
): Promise<{ rows: AdminUserRow[]; total: number }> {
  const conds = [];
  if (opts.role) conds.push(eq(users.role, opts.role));
  if (opts.status === 'deleted') conds.push(isNotNull(users.deletedAt));
  else if (opts.status === 'blocked')
    conds.push(and(isNotNull(users.blockedAt), isNull(users.deletedAt)));
  else if (opts.status === 'active')
    conds.push(and(isNull(users.blockedAt), isNull(users.deletedAt)));
  if (opts.search) {
    const like = `%${opts.search}%`;
    conds.push(or(ilike(users.email, like), ilike(users.name, like)));
  }
  const where = conds.length ? and(...conds) : undefined;

  const rows = await db
    .select({
      id: users.id,
      email: users.email,
      name: users.name,
      role: users.role,
      deletedAt: users.deletedAt,
      blockedAt: users.blockedAt,
      emailVerifiedAt: users.emailVerifiedAt,
      createdAt: users.createdAt,
      plan: subscriptions.plan,
    })
    .from(users)
    .leftJoin(subscriptions, eq(subscriptions.userId, users.id))
    .where(where)
    .orderBy(desc(users.createdAt))
    .limit(opts.pageSize)
    .offset((opts.page - 1) * opts.pageSize);

  const [totalRow] = await db.select({ total: count() }).from(users).where(where);

  return {
    rows: rows.map((r) => ({
      id: r.id,
      email: r.email,
      name: r.name,
      role: r.role,
      status: deriveStatus(r),
      emailVerifiedAt: r.emailVerifiedAt?.toISOString() ?? null,
      createdAt: r.createdAt.toISOString(),
      plan: r.plan ?? null,
    })),
    total: Number(totalRow?.total ?? 0),
  };
}

export type AdminUserDetail = AdminUserRow & {
  updatedAt: string;
  deletedAt: string | null;
  subscriptionStatus: string | null;
  analysisCount: number;
};

export async function getUserDetail(
  db: Database,
  userId: string,
): Promise<AdminUserDetail | undefined> {
  const [u] = await db
    .select({
      id: users.id,
      email: users.email,
      name: users.name,
      role: users.role,
      deletedAt: users.deletedAt,
      blockedAt: users.blockedAt,
      emailVerifiedAt: users.emailVerifiedAt,
      createdAt: users.createdAt,
      updatedAt: users.updatedAt,
      plan: subscriptions.plan,
      subscriptionStatus: subscriptions.status,
    })
    .from(users)
    .leftJoin(subscriptions, eq(subscriptions.userId, users.id))
    .where(eq(users.id, userId))
    .limit(1);
  if (!u) return undefined;

  const [cnt] = await db
    .select({ c: count() })
    .from(analyses)
    .innerJoin(hives, eq(hives.id, analyses.hiveId))
    .where(eq(hives.userId, userId));

  return {
    id: u.id,
    email: u.email,
    name: u.name,
    role: u.role,
    status: deriveStatus(u),
    emailVerifiedAt: u.emailVerifiedAt?.toISOString() ?? null,
    createdAt: u.createdAt.toISOString(),
    updatedAt: u.updatedAt.toISOString(),
    deletedAt: u.deletedAt?.toISOString() ?? null,
    plan: u.plan ?? null,
    subscriptionStatus: u.subscriptionStatus ?? null,
    analysisCount: Number(cnt?.c ?? 0),
  };
}

/**
 * role/status 변경 (§12.5/§12.7/§12.8). 미존재/삭제됨 → undefined(라우트 404).
 * 강등 시 self-demote 가드(FOR UPDATE count, 1 미만 되면 SelfDemoteError). 변경 시 audit 동일 tx.
 * 반환 blockedNow=true면 라우트가 sessions 마커 bump + refresh 일괄 폐기.
 */
export async function patchUser(
  db: Database,
  input: {
    userId: string;
    role?: 'user' | 'admin';
    status?: 'active' | 'blocked';
    actorId: string;
    ip: string | null;
    userAgent: string | null;
  },
): Promise<{ detail: AdminUserDetail; blockedNow: boolean } | undefined> {
  const blockedNow = await db.transaction(async (tx) => {
    const [current] = await tx.select().from(users).where(eq(users.id, input.userId)).limit(1);
    if (!current || current.deletedAt) return null;

    const before = { role: current.role, status: deriveStatus(current) };

    if (input.role === 'user' && current.role === 'admin') {
      // count(*) + FOR UPDATE는 PG에서 불가(집계+잠금). admin 행 자체를 잠가 동시 강등을 직렬화.
      const admins = await tx
        .select({ id: users.id })
        .from(users)
        .where(and(eq(users.role, 'admin'), isNull(users.deletedAt)))
        .for('update');
      if (admins.length <= 1) throw new SelfDemoteError();
    }

    const set: Record<string, unknown> = {};
    if (input.role !== undefined) set.role = input.role;
    let didBlock = false;
    if (input.status === 'blocked') {
      set.blockedAt = new Date();
      didBlock = true;
    } else if (input.status === 'active') {
      set.blockedAt = null;
    }
    if (Object.keys(set).length > 0) {
      await tx.update(users).set(set).where(eq(users.id, input.userId));
    }

    const [updated] = await tx.select().from(users).where(eq(users.id, input.userId)).limit(1);
    const after = { role: updated!.role, status: deriveStatus(updated!) };

    if (input.role !== undefined && before.role !== after.role) {
      await insertAuditLog(tx, {
        actorId: input.actorId,
        action: 'admin.user.role_change',
        entity: 'user',
        entityId: input.userId,
        metadata: { before: before.role, after: after.role },
        ip: input.ip,
        userAgent: input.userAgent,
      });
    }
    if (input.status !== undefined && before.status !== after.status) {
      await insertAuditLog(tx, {
        actorId: input.actorId,
        action: 'admin.user.status_change',
        entity: 'user',
        entityId: input.userId,
        metadata: { before: before.status, after: after.status },
        ip: input.ip,
        userAgent: input.userAgent,
      });
    }
    return didBlock;
  });

  if (blockedNow === null) return undefined;
  const detail = await getUserDetail(db, input.userId);
  return detail ? { detail, blockedNow } : undefined;
}

export type AuditLogRow = {
  id: string;
  actorId: string | null;
  action: string;
  entity: string;
  entityId: string | null;
  metadata: Record<string, unknown> | null;
  ip: string | null;
  userAgent: string | null;
  createdAt: string;
};

export async function listAuditLogs(
  db: Database,
  opts: {
    cursor?: bigint;
    limit: number;
    entity?: string;
    action?: string;
    actorId?: string;
    from?: Date;
    to?: Date;
  },
): Promise<{ rows: AuditLogRow[]; nextCursor: string | null }> {
  const conds = [];
  if (opts.cursor != null) conds.push(lt(auditLog.id, opts.cursor));
  if (opts.entity) conds.push(eq(auditLog.entity, opts.entity));
  if (opts.action) conds.push(eq(auditLog.action, opts.action));
  if (opts.actorId) conds.push(eq(auditLog.actorId, opts.actorId));
  if (opts.from) conds.push(gte(auditLog.createdAt, opts.from));
  if (opts.to) conds.push(lte(auditLog.createdAt, opts.to));
  const where = conds.length ? and(...conds) : undefined;

  const rows = await db
    .select()
    .from(auditLog)
    .where(where)
    .orderBy(desc(auditLog.id))
    .limit(opts.limit);

  return {
    rows: rows.map((r) => ({
      id: String(r.id),
      actorId: r.actorId,
      action: r.action,
      entity: r.entity,
      entityId: r.entityId,
      metadata: (r.metadata as Record<string, unknown> | null) ?? null,
      ip: r.ip,
      userAgent: r.userAgent,
      createdAt: r.createdAt.toISOString(),
    })),
    nextCursor: rows.length === opts.limit ? String(rows[rows.length - 1]!.id) : null,
  };
}

export async function metrics(db: Database): Promise<{
  users: { total: number };
  analysesByStatus: { status: string; count: number }[];
  analysesByProvider: { provider: string; count: number }[];
  subscriptionsByPlan: { plan: string; count: number }[];
}> {
  const [u] = await db.select({ c: count() }).from(users).where(isNull(users.deletedAt));
  const byStatus = await db
    .select({ status: analyses.status, c: count() })
    .from(analyses)
    .groupBy(analyses.status);
  const byProvider = await db
    .select({ provider: aiModels.provider, c: count() })
    .from(analyses)
    .innerJoin(aiModels, eq(aiModels.id, analyses.modelId))
    .where(eq(analyses.status, 'success'))
    .groupBy(aiModels.provider);
  const byPlan = await db
    .select({ plan: subscriptions.plan, c: count() })
    .from(subscriptions)
    .groupBy(subscriptions.plan);

  return {
    users: { total: Number(u?.c ?? 0) },
    analysesByStatus: byStatus.map((r) => ({ status: r.status, count: Number(r.c) })),
    analysesByProvider: byProvider.map((r) => ({ provider: r.provider, count: Number(r.c) })),
    subscriptionsByPlan: byPlan.map((r) => ({ plan: r.plan, count: Number(r.c) })),
  };
}

export type DualEngineRow = {
  provider: string;
  modelName: string;
  modelVersion: string;
  status: string;
  varroaInfectionRisk: number | null;
  overallHealth: string | null;
  rawResponse: Record<string, unknown> | null;
};

export async function getDualByImage(db: Database, imageId: string): Promise<DualEngineRow[]> {
  const rows = await db
    .select({
      provider: aiModels.provider,
      modelName: aiModels.name,
      modelVersion: aiModels.version,
      status: analyses.status,
      varroaInfectionRisk: analyses.varroaInfectionRisk,
      overallHealth: analyses.overallHealth,
      rawResponse: analyses.rawResponse,
    })
    .from(analyses)
    .innerJoin(aiModels, eq(aiModels.id, analyses.modelId))
    .where(eq(analyses.imageId, imageId));

  return rows.map((r) => ({
    provider: r.provider,
    modelName: r.modelName,
    modelVersion: r.modelVersion,
    status: r.status,
    varroaInfectionRisk: r.varroaInfectionRisk,
    overallHealth: r.overallHealth,
    rawResponse: (r.rawResponse as Record<string, unknown> | null) ?? null,
  }));
}
