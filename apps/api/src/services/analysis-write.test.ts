import { describe, expect, it } from 'vitest';

import { toNewAnalysis } from './analysis-write';

describe('toNewAnalysis (C1 drift guard)', () => {
  it('maps every two-stage column; numeric → string, null stays null', () => {
    const at = new Date('2026-09-26T00:00:00Z');
    const row = toNewAnalysis({
      status: 'success',
      varroaInfectionRisk: 70,
      estimatedVarroaCount: null,
      overallHealth: 'critical',
      vdi: 10.04,
      vdiCiLow: 6.5,
      vdiCiHigh: null,
      beeTotal: 250,
      beeInfested: 26,
      rawResponse: { tier: 'high' },
      latencyMs: 900,
      error: null,
      analyzedAt: at,
    });
    expect(row).toEqual({
      status: 'success',
      varroaInfectionRisk: 70,
      estimatedVarroaCount: null,
      overallHealth: 'critical',
      vdi: '10.04',
      vdiCiLow: '6.5',
      vdiCiHigh: null,
      beeTotal: 250,
      beeInfested: 26,
      rawResponse: { tier: 'high' },
      latencyMs: 900,
      error: null,
      analyzedAt: at,
    });
  });
});
