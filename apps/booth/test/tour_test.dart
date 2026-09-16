import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/case_kind.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/data/tour.dart';

BoothCase _c(String id, CaseKind kind, RiskTier tier, {String? disease}) =>
    BoothCase(
      id: id,
      photo: 'photos/$id.jpg',
      kind: kind,
      disease: kind == CaseKind.healthy
          ? null
          : (disease ?? (kind == CaseKind.varroa ? 'varroa' : 'x')),
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
  _c('dwv-1', CaseKind.visible, RiskTier.safe, disease: 'dwv'),
  _c('dwv-2', CaseKind.visible, RiskTier.safe, disease: 'dwv'),
  _c('foul-1', CaseKind.visible, RiskTier.safe, disease: 'foulbrood'),
  _c('foul-2', CaseKind.visible, RiskTier.safe, disease: 'foulbrood'),
  _c('chalk-1', CaseKind.visible, RiskTier.safe, disease: 'chalkbrood'),
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

  test('1라운드는 응애가 아니고, 2·3라운드는 병든 벌통이다', () {
    // 2026-09-16 확정: R1 = 정상 | 날개불구 | 부저병 (택1), R2·R3 = 병든 벌통 (2택).
    for (var seed = 0; seed < 100; seed++) {
      final r = assignRounds(_pool(), Random(seed));
      expect(r[0].kind, isNot(CaseKind.varroa), reason: 'R1 에 응애 (seed $seed)');
      expect(
        round1AnswerOf(r[0]),
        isIn([for (final c in kRound1Choices) c.id]),
        reason: 'R1 정답이 선택지에 없다 (seed $seed)',
      );
      expect(r[1].isHealthy, isFalse, reason: 'R2 가 정상 (seed $seed)');
      expect(r[2].isHealthy, isFalse, reason: 'R3 가 정상 (seed $seed)');
    }
  });

  test('1라운드에 정상·날개불구·부저병이 골고루 나온다', () {
    final seen = <String>{};
    for (var seed = 0; seed < 100; seed++) {
      seen.add(round1AnswerOf(assignRounds(_pool(), Random(seed))[0]));
    }
    expect(seen, containsAll(['healthy', 'dwv', 'foulbrood']));
  });

  test('석고병은 1라운드에 나오지 않는다 — 선택지에 없다', () {
    // 선택지에 없는 병이 나오면 관람객은 맞힐 방법이 없다.
    for (var seed = 0; seed < 100; seed++) {
      expect(
        assignRounds(_pool(), Random(seed))[0].disease,
        isNot('chalkbrood'),
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

    test('1라운드 병명 추측은 disease 와 비교한다', () {
      final foul = _c(
        'foul-1',
        CaseKind.visible,
        RiskTier.safe,
        disease: 'foulbrood',
      );
      expect(
        TourResult(case_: foul, diseaseGuess: 'foulbrood').correct,
        isTrue,
      );
      expect(TourResult(case_: foul, diseaseGuess: 'dwv').correct, isFalse);
      expect(TourResult(case_: foul, diseaseGuess: 'healthy').correct, isFalse);
      final healthy = _c('healthy-1', CaseKind.healthy, RiskTier.safe);
      expect(
        TourResult(case_: healthy, diseaseGuess: 'healthy').correct,
        isTrue,
      );
      expect(TourResult(case_: healthy, diseaseGuess: 'dwv').correct, isFalse);
      expect(TourResult(case_: healthy).skipped, isTrue);
      expect(TourResult(case_: healthy, diseaseGuess: 'dwv').skipped, isFalse);
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
