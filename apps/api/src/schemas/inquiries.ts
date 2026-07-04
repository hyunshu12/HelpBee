/**
 * Inquiries zod 스키마 (문의 접수, apps/web 문의 폼 → POST /v1/inquiries).
 * - 익명 접수 — 인증/소유권 없음. `.strict()`로 미지정 필드 차단.
 * - `website`는 허니팟(honeypot): 실제 사용자는 비워둠. 봇이 채우면 라우트에서 조용히 드롭.
 * - message는 스팸/무의미 제출 방지를 위해 10자 이상 요구.
 */
import { z } from 'zod';

export const createInquirySchema = z
  .object({
    name: z.string().trim().min(1, '이름을 입력해주세요.').max(60),
    email: z.string().trim().min(1).max(255).email('올바른 이메일 형식이 아닙니다.'),
    message: z.string().trim().min(10, '문의 내용을 10자 이상 입력해주세요.').max(2000),
    locale: z.enum(['ko', 'en']).optional(),
    // 허니팟 — 정상 제출은 항상 빈 값/미포함. 값이 있으면 봇으로 간주하고 라우트에서
    // 조용히 드롭(400 대신 201 위장 — 탐지 사실을 봇에게 노출하지 않음).
    website: z.string().optional(),
  })
  .strict();

export type CreateInquiryInput = z.infer<typeof createInquirySchema>;
