// Unit tests for Analysis DTO + tier derivation (locks the review fix where
// overallHealth must map even when varroaInfectionRisk is null).

import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/core/risk/risk_tier.dart';
import 'package:helpbee/features/analyses/data/analysis_dto.dart';

Analysis _a({String status = 'success', int? risk, String? health}) => Analysis(
      id: 'a',
      hiveId: 'h',
      imageId: 'i',
      status: status,
      varroaInfectionRisk: risk,
      overallHealth: health,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('Analysis.tier', () {
    test('overallHealth maps even when risk is null', () {
      expect(_a(health: 'critical', risk: null).tier, RiskTier.danger);
      expect(_a(health: 'healthy', risk: null).tier, RiskTier.safe);
      expect(_a(health: 'warning', risk: null).tier, RiskTier.watch);
    });

    test('falls back to risk bands when overallHealth is absent', () {
      expect(_a(risk: 12).tier, RiskTier.safe);
      expect(_a(risk: 45).tier, RiskTier.watch);
      expect(_a(risk: 84).tier, RiskTier.danger);
    });

    test('non-success or no signal -> unknown', () {
      expect(_a(status: 'failed', risk: 84).tier, RiskTier.unknown);
      expect(_a(risk: null).tier, RiskTier.unknown);
    });
  });

  test('fromJson parses fields + derives tier', () {
    final a = Analysis.fromJson({
      'id': 'x',
      'hiveId': 'h',
      'imageId': 'i',
      'status': 'success',
      'varroaInfectionRisk': 84,
      'overallHealth': 'critical',
      'createdAt': '2026-06-16T00:00:00Z',
      'updatedAt': '2026-06-16T00:00:00Z',
    });
    expect(a.varroaInfectionRisk, 84);
    expect(a.isSuccess, isTrue);
    expect(a.tier, RiskTier.danger);
  });

  group('recommendations parsing', () {
    test('parses recommendations[] with order/content/severity', () {
      final a = Analysis.fromJson({
        'id': 'x',
        'hiveId': 'h',
        'imageId': 'i',
        'status': 'success',
        'createdAt': '2026-06-16T00:00:00Z',
        'updatedAt': '2026-06-16T00:00:00Z',
        'recommendations': [
          {'order': 0, 'content': '즉시 처치가 필요합니다', 'severity': 'danger'},
          {'order': 1, 'content': '주변 벌통도 검사하세요', 'severity': 'warn'},
        ],
      });
      expect(a.recommendations.length, 2);
      expect(a.recommendations.first.content, '즉시 처치가 필요합니다');
      expect(a.recommendations.first.severity, 'danger');
      expect(a.recommendations[1].order, 1);
    });

    test('missing recommendations -> empty (list endpoint omits them)', () {
      expect(_a().recommendations, isEmpty);
    });

    test('drops malformed / empty-content items', () {
      final a = Analysis.fromJson({
        'id': 'x',
        'hiveId': 'h',
        'imageId': 'i',
        'status': 'success',
        'createdAt': '2026-06-16T00:00:00Z',
        'updatedAt': '2026-06-16T00:00:00Z',
        'recommendations': [
          {'order': 0, 'content': '유효', 'severity': 'info'},
          {'order': 1, 'severity': 'warn'}, // no content -> dropped
        ],
      });
      expect(a.recommendations.length, 1);
      expect(a.recommendations.first.severity, 'info');
    });
  });
}
