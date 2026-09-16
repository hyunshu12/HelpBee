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

/// 실제 풀과 같은 구성 (varroa 5 · visible 5 · healthy 5).
List<BoothCase> _pool() => [
  for (var i = 1; i <= 5; i++) _c('varroa-$i', CaseKind.varroa, RiskTier.watch),
  for (var i = 1; i <= 5; i++) _c('other-$i', CaseKind.visible, RiskTier.safe),
  for (var i = 1; i <= 5; i++)
    _c('healthy-$i', CaseKind.healthy, RiskTier.safe),
];

void main() {
  test('3장을 뽑고 같은 사진은 두 번 나오지 않는다', () {
    for (var seed = 0; seed < 50; seed++) {
      final r = assignRounds(_pool(), Random(seed));
      expect(r, hasLength(3));
      expect(
        r.map((c) => c.id).toSet(),
        hasLength(3),
        reason: '같은 사진이 두 번 나왔다 (seed $seed)',
      );
    }
  });

  test('라운드 번호로 답을 추론할 수 없다 — 셋 다 병/정상이 반반이다', () {
    // 2026-09-16: 난이도 계단을 없앴다. 어느 라운드든 정상이 절반쯤 나와야
    // "N 라운드는 항상 병" 같은 요령이 안 통한다.
    const seeds = 400;
    final healthyAt = [0, 0, 0];
    for (var seed = 0; seed < seeds; seed++) {
      final r = assignRounds(_pool(), Random(seed));
      for (var i = 0; i < 3; i++) {
        if (r[i].isHealthy) healthyAt[i]++;
      }
    }
    for (var i = 0; i < 3; i++) {
      final ratio = healthyAt[i] / seeds;
      expect(
        ratio,
        inInclusiveRange(0.38, 0.62),
        reason: '${i + 1}라운드 정상 비율 ${ratio.toStringAsFixed(2)} — 한쪽으로 쏠렸다',
      );
    }
  });

  test('병 라운드에는 응애와 다른 병이 섞여 나온다', () {
    final kinds = <CaseKind>{};
    for (var seed = 0; seed < 100; seed++) {
      for (final c in assignRounds(_pool(), Random(seed))) {
        kinds.add(c.kind);
      }
    }
    expect(
      kinds,
      containsAll([CaseKind.varroa, CaseKind.visible, CaseKind.healthy]),
    );
  });

  test('세션마다 조합이 달라진다', () {
    final combos = <String>{};
    for (var seed = 0; seed < 40; seed++) {
      combos.add(
        assignRounds(_pool(), Random(seed)).map((c) => c.id).join(','),
      );
    }
    expect(combos.length, greaterThan(5), reason: '매번 같은 3장이면 반복 관람객이 지루하다');
  });

  test('사진을 안 보고 한쪽으로만 찍으면 다 맞힐 수 없다', () {
    // 2026-09-14 실측 피드백: R1·R2 가 둘 다 확정으로 병든 벌통이라 "문제 있음"만
    // 세 번 눌러도 최소 2장을 맞혔다. 눈이 아니라 확률로 맞히는 체험은 이 부스가
    // 하려는 말과 정반대다.
    var alwaysSick = 0; // "문제 있음"만 누르는 관람객의 총 정답 수
    var alwaysHealthy = 0;
    const seeds = 200;
    for (var seed = 0; seed < seeds; seed++) {
      for (final c in assignRounds(_pool(), Random(seed))) {
        if (c.isHealthy) {
          alwaysHealthy++;
        } else {
          alwaysSick++;
        }
      }
    }
    final sickAvg = alwaysSick / seeds;
    // 2026-09-16: 세 라운드 다 동전 던지기 — 한쪽으로만 찍으면 기대값 1.5장.
    // 여유 0.3 은 200 시드의 표본 흔들림 몫이다.
    expect(
      sickAvg,
      lessThan(1.8),
      reason: '"문제 있음"만 눌러 평균 ${sickAvg.toStringAsFixed(2)}장 — 찍기가 통한다',
    );
    expect(
      alwaysHealthy / seeds,
      lessThan(1.8),
      reason: '"건강함"만 눌러도 다 맞으면 반대쪽으로 찍기가 통한다',
    );
  });

  test('후보군이 비어도 멈추지 않는다', () {
    // 데이터 사고로 정상 사진이 하나도 없어도 부스는 돌아야 한다.
    final poolWithoutHealthy = _pool()
        .where((c) => c.kind != CaseKind.healthy)
        .toList();
    for (var seed = 0; seed < 20; seed++) {
      expect(assignRounds(poolWithoutHealthy, Random(seed)), hasLength(3));
    }
    // 반대로 병 사진이 없어도.
    final onlyHealthy = _pool().where((c) => c.isHealthy).toList();
    expect(assignRounds(onlyHealthy, Random(0)), hasLength(3));
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
        case_: _c('healthy-1', CaseKind.healthy, RiskTier.safe),
        guess: false,
      );
      expect(healthy.correct, isFalse);

      final healthyRight = TourResult(
        case_: _c('healthy-1', CaseKind.healthy, RiskTier.safe),
        guess: true,
      );
      expect(healthyRight.correct, isTrue);
    });

    test('건너뛴 라운드는 맞힌 것으로 세지 않는다', () {
      final skipped = TourResult(
        case_: _c('healthy-1', CaseKind.healthy, RiskTier.safe),
        guess: null,
      );
      expect(skipped.correct, isFalse);
    });
  });
}
