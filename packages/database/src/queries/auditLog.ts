/**
 * 감사 로그 쓰기 헬퍼 (backend-design §8.6, §14.3).
 * - 허용 키 화이트리스트 metadata만(임의 jsonb 직접 insert 금지, §13 SHOULD).
 * - auth 등 best-effort 기록은 appendAuditLog(내부 try/catch — insert 실패가 본요청을 깨지 않음).
 * - admin mutation의 트랜잭션 원자 기록은 insertAuditLog를 tx와 함께 사용(§12.7).
 * ⚠️ metadata에 PII/비번/토큰/좌표 평문 금지(호출부가 redact 후 전달).
 */
import type { Database } from '../client';
import { auditLog } from '../schema/auditLog';

export type AuditEntry = {
  actorId?: string | null;
  action: string;
  entity: string;
  entityId?: string | null;
  metadata?: Record<string, unknown> | null;
  ip?: string | null;
  userAgent?: string | null;
};

/** 트랜잭션/원자 기록용 raw insert(admin mutation은 tx로 호출). 실패 시 throw. */
export async function insertAuditLog(db: Database, entry: AuditEntry): Promise<void> {
  await db.insert(auditLog).values({
    actorId: entry.actorId ?? null,
    action: entry.action,
    entity: entry.entity,
    entityId: entry.entityId ?? null,
    metadata: entry.metadata ?? null,
    ip: entry.ip ?? null,
    userAgent: entry.userAgent ?? null,
  });
}

/** best-effort 기록(auth 등). insert 실패는 ERROR 로그만 남기고 삼킴(본요청 비차단, §14.3). */
export async function appendAuditLog(db: Database, entry: AuditEntry): Promise<void> {
  try {
    await insertAuditLog(db, entry);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error(
      JSON.stringify({ level: 'error', msg: 'audit_log_insert_failed', action: entry.action }),
      err,
    );
  }
}
