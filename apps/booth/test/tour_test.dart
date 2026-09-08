import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/case_kind.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/data/tour.dart';

BoothCase _c(String id, CaseKind kind, RiskTier tier) => BoothCase(
  id: id,
  photo: 'photos/$id.jpg',
  kind: kind,
  disease: kind == CaseKind.healthy ? null : 'x',
  diseaseLabel: kind == CaseKind.healthy ? null : '병',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 0,
  tier: tier,
  beeTotal: 10,
  sickCount: kind == CaseKind.healthy ? 0 : 2,
  recommendations: const [],
  boxes: const [],
);

/// 실제 풀과 같은 구성 (visible 3 · varroa danger 3 · varroa watch 2 · healthy 2).
List<BoothCase> _pool() => [
  _c('chalk-1', CaseKind.visible, RiskTier.safe),
  _c('chalk-2', CaseKind.visible, RiskTier.safe),
  _c('dwv-1', CaseKind.visible, RiskTier.safe),
  _c('danger-100', CaseKind.varroa, RiskTier.danger),
  _c('danger-90', CaseKind.varroa, RiskTier.danger),
  _c('danger-2', CaseKind.varroa, RiskTier.danger),
  _c('watch-50', CaseKind.varroa, RiskTier.watch),
  _c('watch-2', CaseKind.varroa, RiskTier.watch),
  _c('safe-0', CaseKind.healthy, RiskTier.safe),
  _c('safe-2', CaseKind.healthy, RiskTier.safe),
];

void main() {
  test('난이도 계단대로 배정한다 — 쉬움 → 어려움 → 더 어려움', () {
    for (var seed = 0; seed < 50; seed++) {
      final r = assignRounds(_pool(), Random(seed));
      expect(r, hasLength(3));
      expect(r[0].kind, CaseKind.visible, reason: 'R1 은 눈에 보이는 병 (seed $seed)');
      expect(r[1].kind, CaseKind.varroa, reason: 'R2 는 응애 (seed $seed)');
      expect(r[1].tier, RiskTier.danger, reason: 'R2 는 위험 등급 (seed $seed)');
      expect(
        r[2].kind == CaseKind.healthy ||
            (r[2].kind == CaseKind.varroa && r[2].tier == RiskTier.watch),
        isTrue,
        reason: 'R3 는 응애 주의 또는 정상(함정) (seed $seed)',
      );
      expect(
        r.map((c) => c.id).toSet(),
        hasLength(3),
        reason: '같은 사진이 두 번 나왔다 (seed $seed)',
      );
    }
  });

  test('세션마다 조합이 달라진다', () {
    final combos = <String>{};
    for (var seed = 0; seed < 40; seed++) {
      combos.add(assignRounds(_pool(), Random(seed)).map((c) => c.id).join(','));
    }
    expect(
      combos.length,
      greaterThan(5),
      reason: '매번 같은 3장이면 반복 관람객이 지루하다',
    );
  });

  test('R3 의 함정(정상)이 가끔 나온다', () {
    var healthy = 0;
    for (var seed = 0; seed < 200; seed++) {
      if (assignRounds(_pool(), Random(seed))[2].kind == CaseKind.healthy) {
        healthy++;
      }
    }
    expect(healthy, greaterThan(50), reason: '정상이 거의 안 나오면 함정이 성립 안 한다');
    expect(healthy, lessThan(150), reason: '정상만 나오면 응애 주의를 못 본다');
  });

  test('후보군이 비어도 멈추지 않는다', () {
    // 데이터 사고로 visible 이 하나도 없어도 부스는 돌아야 한다.
    final poolWithoutVisible = _pool()
        .where((c) => c.kind != CaseKind.visible)
        .toList();
    final r = assignRounds(poolWithoutVisible, Random(0));
    expect(r, hasLength(3));
  });

  group('TourResult.correct', () {
    test('맞음 판정은 kind 기준이다', () {
      final visible = TourResult(
        case_: _c('dwv-1', CaseKind.visible, RiskTier.safe),
        guess: false,
      );
      expect(visible.correct, isTrue, reason: '병든 벌통에 "문제 있음" 은 정답');

      final visibleWrong = TourResult(
        case_: _c('dwv-1', CaseKind.visible, RiskTier.safe),
        guess: true,
      );
      expect(visibleWrong.correct, isFalse);
    });

    test('건강한 벌통에 "문제 있음" 은 오답 — R3 함정', () {
      final healthy = TourResult(
        case_: _c('safe-0', CaseKind.healthy, RiskTier.safe),
        guess: false,
      );
      expect(healthy.correct, isFalse);

      final healthyRight = TourResult(
        case_: _c('safe-0', CaseKind.healthy, RiskTier.safe),
        guess: true,
      );
      expect(healthyRight.correct, isTrue);
    });

    test('건너뛴 라운드는 맞힌 것으로 세지 않는다', () {
      final skipped = TourResult(
        case_: _c('safe-0', CaseKind.healthy, RiskTier.safe),
        guess: null,
      );
      expect(skipped.correct, isFalse);
    });
  });
}
