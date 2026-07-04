export type InquiryInput = {
  name: string;
  email: string;
  type: string;
  message: string;
  agree: boolean;
};

export type InquiryResult = { ok: boolean; reason?: 'NOT_IMPLEMENTED' };

/**
 * 백엔드 POST /v1/inquiries 미구현(spec §10) — 현재 제출 비활성.
 * 엔드포인트가 생기면 이 함수 본문만 fetch(`${NEXT_PUBLIC_API_URL}/v1/inquiries`)로
 * 교체하면 됨 (단일 스왑 포인트).
 */
export async function submitInquiry(_input: InquiryInput): Promise<InquiryResult> {
  return { ok: false, reason: 'NOT_IMPLEMENTED' };
}
