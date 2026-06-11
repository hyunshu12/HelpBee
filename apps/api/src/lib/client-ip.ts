/**
 * 클라이언트 IP 추출 (backend-design §7.5).
 * MVP: XFF 첫 홉 / x-real-ip. CloudFront+ALB 신뢰 프록시 홉 인지 파서는 후속 강화(§13 SHOULD).
 */
import type { Context } from 'hono';

export function getClientIp(c: Context): string {
  const xff = c.req.header('x-forwarded-for');
  if (xff) {
    const first = xff.split(',')[0]?.trim();
    if (first) return first;
  }
  return c.req.header('x-real-ip') ?? 'unknown';
}
