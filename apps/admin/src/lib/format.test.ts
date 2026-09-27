/**
 * formatVdi (I2) — 실행: `../api/node_modules/.bin/tsx --test src/lib/format.test.ts`
 * (admin 에는 테스트 러너가 없어 node:test + tsx 로 돌린다.)
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { formatVdi } from './format';

const base = { vdiCiLow: null, vdiCiHigh: null };

test('vdi_display 를 그대로 표시 — numeric 재반올림(9.950→9.9)으로 tier 와 모순되지 않는다', () => {
  assert.equal(formatVdi({ ...base, vdi: 9.95, rawResponse: { vdi_display: '10.0', tier: 'high' } }), '10.0%');
  assert.equal(formatVdi({ ...base, vdi: 2.95, rawResponse: { vdi_display: '2.9', tier: 'low' } }), '2.9%');
});

test('vdi_display 없으면 숫자 폴백, 둘 다 없으면 -', () => {
  assert.equal(formatVdi({ ...base, vdi: 4.2, rawResponse: { tier: 'elevated' } }), '4.2%');
  assert.equal(formatVdi({ ...base, vdi: null, rawResponse: null }), '-');
});

test('CI 는 함께 표시', () => {
  assert.equal(
    formatVdi({ vdi: 10.04, vdiCiLow: 6.5, vdiCiHigh: 14.2, rawResponse: { vdi_display: '10.0' } }),
    '10.0% (6.5–14.2%)',
  );
});
