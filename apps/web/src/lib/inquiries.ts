export type InquiryInput = {
  name: string;
  email: string;
  type: string;
  message: string;
  agree: boolean;
  locale?: string;
};

export type InquiryResult =
  | { ok: true; id: string }
  | { ok: false; reason: 'RATE_LIMITED' | 'VALIDATION_FAILED' | 'NETWORK' | 'MISCONFIGURED' };

/**
 * 문의 폼 제출 → apps/api POST /v1/inquiries (익명 공개 라우트).
 * - NEXT_PUBLIC_API_URL 미설정 시 MISCONFIGURED(빌드/프리뷰 방어).
 * - 백엔드는 message만 검증·저장. `type`/`agree`는 UI 전용이라 message에 접두로 합쳐 보냄
 *   (백엔드 스키마는 name/email/message/locale만 받음 — .strict).
 * - problem+json의 code로 실패 분기(RATE_LIMITED 등).
 */
export async function submitInquiry(input: InquiryInput): Promise<InquiryResult> {
  const base = process.env.NEXT_PUBLIC_API_URL;
  if (!base) return { ok: false, reason: 'MISCONFIGURED' };

  const message = `[${input.type}] ${input.message}`;

  let res: Response;
  try {
    res = await fetch(`${base}/v1/inquiries`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        name: input.name,
        email: input.email,
        message,
        ...(input.locale ? { locale: input.locale } : {}),
      }),
    });
  } catch {
    return { ok: false, reason: 'NETWORK' };
  }

  if (res.ok) {
    const body = (await res.json().catch(() => null)) as { data?: { id?: string } } | null;
    return { ok: true, id: body?.data?.id ?? '' };
  }

  if (res.status === 429) return { ok: false, reason: 'RATE_LIMITED' };
  if (res.status === 400) return { ok: false, reason: 'VALIDATION_FAILED' };
  return { ok: false, reason: 'NETWORK' };
}
