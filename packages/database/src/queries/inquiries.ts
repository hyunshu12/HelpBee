import type { Database } from '../client';
import { inquiries, type Inquiry } from '../schema/inquiries';

export type CreateInquiryInput = {
  name: string;
  email: string;
  message: string;
  locale?: string | null;
};

/**
 * 문의 생성 — 명시 화이트리스트만 set(id/status/timestamps는 코드/기본값 결정, Mass Assignment 차단).
 * 익명 접수라 소유권/유저 FK 없음.
 */
export async function createInquiry(
  db: Database,
  input: CreateInquiryInput,
): Promise<Inquiry> {
  const [row] = await db
    .insert(inquiries)
    .values({
      name: input.name,
      email: input.email,
      message: input.message,
      locale: input.locale ?? null,
    })
    .returning();
  return row!;
}
