/**
 * 클라이언트 IP 추출 (backend-design §7.5, 절감 모드 개정 — plans/2026-07-07 PR-5).
 *
 * IP는 레이트리밋 키·로그인 잠금 복합키·audit_log.ip 에 쓰이므로 위조되면
 * quota 우회/타인 잠금 유발이 가능하다. 신뢰 경계는 배포 토폴로지에 따라 다르다:
 *
 * - 'cloudflare' (beta 실배포): Cloudflare 프록시가 CF-Connecting-IP 를 항상
 *   설정/덮어쓰므로 이 헤더만 신뢰. 헤더가 없다 = Cloudflare 를 우회한 오리진
 *   직접 접속 — 어떤 헤더도 신뢰 불가라 'untrusted-direct' 단일 버킷으로 묶어
 *   레이트리밋을 공유시킨다(SG 를 Cloudflare 대역으로 좁히는 것이 근본 대책).
 * - 'xff' (로컬/테스트 기본): 기존 동작 유지 — XFF 첫 홉/x-real-ip.
 *   첫 홉은 클라이언트가 위조 가능하므로 실배포 사용 금지
 *   (production 에서 이 모드면 createApp 이 경고 로그를 남긴다).
 *
 * 모드는 env.TRUSTED_PROXY → createApp 의 configureTrustedProxy() 로 주입.
 * (getClientIp 는 rate-limit keyFn 등에서 Context 만으로 호출되는 시그니처를 유지.)
 *
 * ⚠️ 클라이언트 IP 는 반드시 이 모듈로만 추출한다 — 라우트에서 XFF 를 직접 파싱하면
 * 신뢰 모드를 우회한다 (리뷰에서 auth 로그인 잠금 우회 사례로 실증됨).
 */
import type { Context } from 'hono';

export type TrustedProxyMode = 'xff' | 'cloudflare';

let trustedProxy: TrustedProxyMode = 'xff';

export function configureTrustedProxy(mode: TrustedProxyMode): void {
  trustedProxy = mode;
}

export function getClientIp(c: Context): string {
  if (trustedProxy === 'cloudflare') {
    const cf = c.req.header('cf-connecting-ip')?.trim();
    if (cf) return cf;
    return 'untrusted-direct';
  }
  const xff = c.req.header('x-forwarded-for');
  if (xff) {
    const first = xff.split(',')[0]?.trim();
    if (first) return first;
  }
  return c.req.header('x-real-ip') ?? 'unknown';
}
