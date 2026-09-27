// v0.2.0 two-stage 계약 파싱 (spec v2.2 §3): tier 는 서버 문자열이 단일 소스,
// vdi 로 재계산하지 않는다. 레거시 행은 새 필드가 모두 null.

import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/core/risk/risk_tier.dart';
import 'package:helpbee/features/analyses/data/analysis_dto.dart';

Map<String, dynamic> _base() => {
  'id': 'a1',
  'hiveId': 'h1',
  'imageId': 'i1',
  'status': 'success',
  'createdAt': '2026-09-26T00:00:00Z',
  'updatedAt': '2026-09-26T00:00:00Z',
};

void main() {
  test('two-stage payload: tier from server string, vdi fields, evidence', () {
    final a = Analysis.fromJson({
      ..._base(),
      'varroaInfectionRisk': 71, // 이중 출력 점수 단위 — tier 와 무관해야 한다
      'overallHealth': 'warning',
      'vdi': 4.2,
      'vdiDisplay': '4.2',
      'tier': 'elevated',
      'corrected': true,
      'samplingCi95': [2.4, 6.9],
      'beeTotal': 310,
      'beeInfested': 14,
      'quality': {'ok': true, 'blur_score': 240.5},
      'evidence': [
        {
          'index': 3,
          'box': [10, 20, 110, 120],
          'crop_region': [0, 10, 120, 130],
          'p_infested': 0.91,
          'cam': [
            [0.1, 0.2],
            [0.3, 0.4],
          ],
        },
        {
          'index': 9,
          'box': [1, 2],
          'p_infested': 0.5,
        }, // 불완전 → 버림
      ],
    });
    expect(
      a.tier,
      RiskTier.watch,
    ); // elevated → watch-equivalent, not danger(71)
    expect(a.vdiDisplay, '4.2');
    expect(a.vdi, 4.2);
    expect(a.vdiCiLow, 2.4);
    expect(a.vdiCiHigh, 6.9);
    expect(a.beeTotal, 310);
    expect(a.beeInfested, 14);
    expect(a.corrected, isTrue);
    expect(a.isTwoStage, isTrue);
    expect(a.quality?['ok'], isTrue);
    expect(a.evidence.length, 1);
    expect(a.evidence.first.cropRegion, [0, 10, 120, 130]);
    expect(a.evidence.first.pInfested, 0.91);
  });

  test('insufficient payload: tier insufficient, vdi null, no evidence', () {
    final a = Analysis.fromJson({
      ..._base(),
      'overallHealth': null,
      'vdi': null,
      'vdiDisplay': null,
      'tier': 'insufficient',
      'beeTotal': 0,
      'beeInfested': 0,
      'quality': {
        'ok': false,
        'reasons': ['blur'],
      },
    });
    expect(a.tier, RiskTier.insufficient);
    expect(a.vdi, isNull);
    expect(a.beeTotal, 0);
    expect(a.evidence, isEmpty);
  });

  test('legacy payload: new fields null, tier from overallHealth/risk', () {
    final a = Analysis.fromJson({
      ..._base(),
      'varroaInfectionRisk': 84,
      'overallHealth': 'critical',
    });
    expect(a.tier, RiskTier.danger);
    expect(a.vdiDisplay, isNull);
    expect(a.beeTotal, isNull);
    expect(a.tierRaw, isNull);
    expect(a.isTwoStage, isFalse);
    expect(a.evidence, isEmpty);
  });

  test('unknown tier string falls back to overallHealth', () {
    final a = Analysis.fromJson({
      ..._base(),
      'overallHealth': 'healthy',
      'tier': 'brand-new-tier',
      'vdiDisplay': '0.3',
    });
    expect(a.tier, RiskTier.safe);
  });

  test('riskTierFromServer mapping table', () {
    expect(riskTierFromServer('low'), RiskTier.safe);
    expect(riskTierFromServer('safe'), RiskTier.safe);
    expect(riskTierFromServer('elevated'), RiskTier.watch);
    expect(riskTierFromServer('watch'), RiskTier.watch);
    expect(riskTierFromServer('high'), RiskTier.danger);
    expect(riskTierFromServer('danger'), RiskTier.danger);
    expect(riskTierFromServer('insufficient'), RiskTier.insufficient);
    expect(riskTierFromServer(null, overallHealth: 'warning'), RiskTier.watch);
    expect(riskTierFromServer('??', overallHealth: null), RiskTier.unknown);
  });
}
