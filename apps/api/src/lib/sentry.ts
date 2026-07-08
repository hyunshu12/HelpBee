/**
 * Sentry 래퍼 (plans/2026-07-07 PR-7 — 관측성 최소셋).
 * SENTRY_DSN 미설정(로컬/테스트) 시 완전 no-op — 코드 경로에 조건 분기가 새지 않게
 * 이 모듈만 Sentry 를 알고, 소비자는 initSentry/captureException 만 쓴다.
 * 트레이싱은 베타 범위 밖(tracesSampleRate 0) — 에러 가시성만 확보.
 */
import * as Sentry from '@sentry/node';

let enabled = false;

export function initSentry(dsn: string | undefined, environment: string): void {
  if (!dsn) return;
  Sentry.init({ dsn, environment, tracesSampleRate: 0 });
  enabled = true;
}

export function captureException(err: unknown, extra?: Record<string, unknown>): void {
  if (!enabled) return;
  Sentry.captureException(err, extra ? { extra } : undefined);
}
