/**
 * getClientIp 신뢰 모드 검증 (plans/2026-07-07 PR-5).
 * - cloudflare: CF-Connecting-IP 만 신뢰, 부재 시 'untrusted-direct'(위조 헤더 무시)
 * - xff(기본): 기존 동작 — XFF 첫 홉 / x-real-ip / 'unknown'
 */
import { Hono } from 'hono';
import { afterEach, describe, expect, it } from 'vitest';

import { configureTrustedProxy, getClientIp } from './client-ip';

function appEchoingIp() {
  const app = new Hono();
  app.get('/ip', (c) => c.text(getClientIp(c)));
  return app;
}

async function ipFor(headers: Record<string, string>): Promise<string> {
  const res = await appEchoingIp().request('/ip', { headers });
  return res.text();
}

afterEach(() => {
  configureTrustedProxy('xff'); // 모듈 상태 원복 (다른 테스트 오염 방지)
});

describe('getClientIp — xff 모드 (기본, 로컬/테스트 전용)', () => {
  it('XFF 첫 홉을 반환한다', async () => {
    expect(await ipFor({ 'x-forwarded-for': '203.0.113.7, 10.0.0.1' })).toBe('203.0.113.7');
  });

  it('XFF 없으면 x-real-ip, 둘 다 없으면 unknown', async () => {
    expect(await ipFor({ 'x-real-ip': '198.51.100.2' })).toBe('198.51.100.2');
    expect(await ipFor({})).toBe('unknown');
  });
});

describe('getClientIp — cloudflare 모드 (beta 실배포)', () => {
  it('CF-Connecting-IP 를 신뢰한다', async () => {
    configureTrustedProxy('cloudflare');
    expect(
      await ipFor({ 'cf-connecting-ip': '203.0.113.9', 'x-forwarded-for': '6.6.6.6' }),
    ).toBe('203.0.113.9');
  });

  it('CF 헤더 부재(오리진 직타) 시 위조 가능한 XFF/x-real-ip 를 무시하고 untrusted-direct', async () => {
    configureTrustedProxy('cloudflare');
    expect(
      await ipFor({ 'x-forwarded-for': '6.6.6.6', 'x-real-ip': '6.6.6.7' }),
    ).toBe('untrusted-direct');
  });

  it('공백뿐인 CF 헤더도 부재로 취급한다', async () => {
    configureTrustedProxy('cloudflare');
    expect(await ipFor({ 'cf-connecting-ip': '   ' })).toBe('untrusted-direct');
  });
});
