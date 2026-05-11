import { timestamp } from 'drizzle-orm/pg-core';

/**
 * 모든 비-audit 테이블에 적용되는 timestamps mixin.
 * - created_at: insert 시 자동 설정
 * - updated_at: insert 시 defaultNow. UPDATE 시에는 SQL 트리거(0001_init.sql 보강)
 *   또는 호출자가 명시적으로 `updatedAt: new Date()`를 set한다.
 *   ※ drizzle-orm 0.29.5는 `.$onUpdate` 헬퍼를 지원하지 않음 — 0.30+ 마이그레이션 시 추가 가능.
 * 시간은 timestamptz (UTC). 클라이언트에서 KST 변환.
 */
export const timestamps = {
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
};

/**
 * users / hives에만 적용되는 soft delete mixin.
 * analyses / analysis_images / audit_log 등 분석/감사 데이터는 hard 보존.
 * 사용처 쿼리에서는 deleted_at IS NULL 필터 적용 의무.
 */
export const softDelete = {
  deletedAt: timestamp('deleted_at', { withTimezone: true }),
};
