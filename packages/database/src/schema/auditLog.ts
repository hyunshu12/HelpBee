import { bigserial, index, jsonb, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

import { users } from './users';

/**
 * 감사 로그.
 * - id: bigserial (시간 정렬 + 대량 삽입 비용 절감, uuid 예외)
 * - actor_id: nullable FK (시스템/익명 액션 가능). user 삭제 시 set null.
 * - hard 보존, soft delete 없음. 보존 기간 / 파티셔닝 정책은 1M row 도달 전 결정.
 *
 * 기록 대상 (apps/api 책임):
 * - 로그인/로그아웃/refresh 회전/재사용 감지
 * - 패스워드/이메일/role 변경
 * - 결제/구독 상태 변경
 * - admin 데이터 수정
 */
export const auditLog = pgTable(
  'audit_log',
  {
    id: bigserial('id', { mode: 'bigint' }).primaryKey(),
    actorId: uuid('actor_id').references(() => users.id, { onDelete: 'set null' }),
    action: text('action').notNull(),
    entity: text('entity').notNull(),
    entityId: uuid('entity_id'),
    metadata: jsonb('metadata'),
    ip: text('ip'),
    userAgent: text('user_agent'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    entityIdx: index('audit_log_entity_idx').on(t.entity, t.entityId),
    createdAtIdx: index('audit_log_created_at_idx').on(t.createdAt),
  }),
);

export type AuditLog = typeof auditLog.$inferSelect;
export type NewAuditLog = typeof auditLog.$inferInsert;
