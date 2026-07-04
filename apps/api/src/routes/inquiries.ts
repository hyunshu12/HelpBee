/**
 * Inquiries 라우트 — 문의 접수 (apps/web 문의 폼).
 * - POST /v1/inquiries 🔓 익명. 인증 없음(비로그인 방문자 제출).
 * - 레이트리밋(5/시간/IP)은 app.ts에서 마운트 시 앞단 미들웨어로 적용.
 * - 허니팟(website) 채워지면 조용히 드롭(201 위장, DB 미저장).
 * - 응답은 { id }만 — message 등 입력 echo 금지(반사 방지).
 * - audit_log 미기록(익명·비민감), 이메일 알림 미구현(후속).
 */
import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';
import { randomUUID } from 'node:crypto';

import { created } from '../lib/envelope';
import { createInquirySchema } from '../schemas/inquiries';

export type InquiriesDeps = {
  create(input: {
    name: string;
    email: string;
    message: string;
    locale?: string | null;
  }): Promise<{ id: string }>;
};

export function inquiriesRoutes(deps: InquiriesDeps) {
  const app = new Hono();

  // POST /v1/inquiries — 문의 접수
  app.post('/', zValidator('json', createInquirySchema), async (c) => {
    const body = c.req.valid('json');

    // 허니팟: 봇으로 간주 — 저장하지 않고 성공처럼 응답(탐지 은폐).
    if (body.website && body.website.length > 0) {
      return created(c, { id: randomUUID() });
    }

    const row = await deps.create({
      name: body.name,
      email: body.email,
      message: body.message,
      locale: body.locale ?? null,
    });
    return created(c, { id: row.id });
  });

  return app;
}
