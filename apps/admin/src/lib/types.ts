/**
 * 백엔드(apps/api) 응답 타입 미러. packages/types가 비어 있어(§8) 여기서 직접 정의.
 * 진실의 원천은 packages/database 추론 타입 + docs/01-development/frontend-api-integration.md §6.
 */

export type AdminRole = 'user' | 'admin';
export type AdminUserStatus = 'active' | 'blocked' | 'deleted';

export interface PublicUser {
  id: string;
  email: string;
  name: string;
  role: AdminRole;
  emailVerified: boolean;
  createdAt: string;
}

export interface AdminUserRow {
  id: string;
  email: string;
  name: string;
  role: string;
  status: AdminUserStatus;
  emailVerifiedAt: string | null;
  createdAt: string;
  plan: string | null;
}

export interface AdminUserDetail extends AdminUserRow {
  updatedAt: string;
  deletedAt: string | null;
  subscriptionStatus: string | null;
  analysisCount: number;
}

export interface AuditLogRow {
  id: string;
  actorId: string | null;
  action: string;
  entity: string;
  entityId: string | null;
  metadata: Record<string, unknown> | null;
  ip: string | null;
  userAgent: string | null;
  createdAt: string;
}

export interface AuditLogPage {
  items: AuditLogRow[];
  nextCursor: string | null;
}

export interface AdminMetrics {
  users: { total: number };
  analysesByStatus: { status: string; count: number }[];
  analysesByProvider: { provider: string; count: number }[];
  subscriptionsByPlan: { plan: string; count: number }[];
}

export interface DualEngineRow {
  provider: string;
  modelName: string;
  modelVersion: string;
  status: string;
  varroaInfectionRisk: number | null;
  overallHealth: string | null;
  rawResponse: Record<string, unknown> | null;
}

export interface DualComparison {
  primary: DualEngineRow;
  secondary: DualEngineRow | null;
  agreement: { healthMatch: boolean; riskDiff: number | null } | null;
}

/** 성공 봉투 {data, meta} */
export interface Meta {
  requestId: string;
  timestamp: string;
  pagination?: { limit: number; offset: number; total: number };
}
export interface Envelope<T> {
  data: T;
  meta: Meta;
}
