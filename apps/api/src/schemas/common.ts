/**
 * 공통 입력 스키마 + 정규화 유틸 (backend-design §6.4).
 * - uuid(): zod v4 .uuid() API 변동 회피용 정규식 검증 (Part 1 schemas와 동일).
 * - paginationSchema: 모든 list (limit 1~100 default 50, offset 0~10000 default 0).
 * - idParamSchema: 모든 :id path param.
 * - normalizeEmail: trim→NFKC→toLowerCase 단일 유틸 (§8.2, §13 SHOULD — homoglyph/카운터 우회 차단).
 */
import { z } from 'zod';

export const uuid = z
  .string()
  .regex(
    /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/,
    'invalid uuid',
  );

export const paginationSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(50),
  offset: z.coerce.number().int().min(0).max(10000).default(0),
});

export const idParamSchema = z.object({ id: uuid }).strict();

/** signup/login/실패카운터/조회가 모두 경유하는 단일 정규화(§13 SHOULD). */
export function normalizeEmail(raw: string): string {
  return raw.trim().normalize('NFKC').toLowerCase();
}
