import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/booth_session.dart';
import 'package:helpbee_booth/data/tour.dart';
import 'package:helpbee_booth/data/case_kind.dart';
import 'package:helpbee_booth/data/risk_tier.dart';

BoothCase _c(String id, CaseKind kind, RiskTier tier) => BoothCase(
  id: id,
  photo: 'photos/$id.jpg',
  kind: kind,
  disease: null,
  diseaseLabel: null,
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 0,
  tier: tier,
  beeTotal: 10,
  sickCount: kind == CaseKind.healthy ? 0 : 2,
  recommendations: const [],
  boxes: const [],
);

List<BoothCase> _pool() => [
  _c('dwv-1', CaseKind.visible, RiskTier.safe),
  _c('varroa-1', CaseKind.varroa, RiskTier.danger),
  _c('varroa-3', CaseKind.varroa, RiskTier.watch),
  _c('healthy-1', CaseKind.healthy, RiskTier.safe),
];

void main() {
  test('투어를 시작하면 3라운드가 잡힌다', () {
    final s = BoothSession()..startTour(_pool(), rng: Random(1));
    expect(s.rounds, hasLength(3));
    expect(s.roundIndex, 0);
    expect(s.isLastRound, isFalse);
    expect(s.currentCase, isNotNull);
  });

  test('답할 때마다 라운드가 넘어가고 마지막에서 멈춘다', () {
    final s = BoothSession()..startTour(_pool(), rng: Random(1));
    s.recordGuess(false);
    expect(s.roundIndex, 1);
    s.recordGuess(false);
    expect(s.roundIndex, 2);
    expect(s.isLastRound, isTrue);
    s.recordGuess(false);
    expect(s.roundIndex, 3);
    expect(s.currentCase, isNull, reason: '3장이 끝나면 현재 케이스가 없다');
    // 끝난 뒤 더 눌러도 결과가 늘지 않아야 한다 — 안 그러면 요약의 분모가 깨진다.
    s.recordGuess(true);
    expect(s.results, hasLength(3));
  });

  test('맞힌 수를 센다 — 건너뛴 라운드는 세지 않는다', () {
    final s = BoothSession()..startTour(_pool(), rng: Random(1));
    // R1 정답으로 답한다 (2026-09-16 부터 R1 도 병/정상 반반이라 시드에 기대지 않는다).
    s.recordGuess(s.currentCase!.isHealthy);
    // R2 는 시드에 따라 응애일 수도 정상일 수도 있으므로(2026-09-14 찍기 방지),
    // **정답의 반대**로 답해 확실히 틀린다. 시드 번호에 기대는 단언은 배정
    // 규칙을 바꿀 때마다 조용히 깨진다.
    s.recordGuess(!s.currentCase!.isHealthy);
    s.recordGuess(null); // R3 건너뜀 → 오답 처리
    expect(s.correctCount, 1);
  });

  test('리셋하면 라운드와 결과가 모두 비워진다', () {
    final s = BoothSession()..startTour(_pool(), rng: Random(1));
    s.recordGuess(false);
    s.reset();
    expect(s.rounds, isEmpty);
    expect(s.results, isEmpty);
    expect(s.correctCount, 0);
    expect(s.currentCase, isNull);
  });

  test('결과 목록은 밖에서 못 바꾼다', () {
    final s = BoothSession()..startTour(_pool(), rng: Random(1));
    expect(() => s.results.clear(), throwsUnsupportedError);
    expect(() => s.rounds.clear(), throwsUnsupportedError);
  });

  test('1라운드만 병명 라운드다', () {
    final s = BoothSession()..startTour(_pool(), rng: Random(1));
    expect(s.isDiseaseRound, isTrue);
    s.recordDiseaseGuess('healthy');
    expect(s.isDiseaseRound, isFalse);
    expect(s.results.single.diseaseGuess, 'healthy');
    expect(s.results.single.guess, isNull);
  });

  test('showcase 로 시작하면 고정 세트, 아니면 랜덤', () {
    final pool = [
      ..._pool(),
      _c('healthy-4', CaseKind.healthy, RiskTier.safe),
      _c('varroa-1', CaseKind.varroa, RiskTier.watch),
      _c('varroa-5', CaseKind.varroa, RiskTier.danger),
    ];
    final s = BoothSession()..startTour(pool, showcase: true);
    expect(s.rounds.map((c) => c.id), kShowcaseIds);
    s.startTour(pool, rng: Random(3));
    expect(s.rounds.map((c) => c.id), isNot(kShowcaseIds));
  });
}
