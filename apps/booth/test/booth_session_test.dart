import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/booth_session.dart';
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
  _c('danger-100', CaseKind.varroa, RiskTier.danger),
  _c('watch-50', CaseKind.varroa, RiskTier.watch),
  _c('safe-0', CaseKind.healthy, RiskTier.safe),
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
    s.recordGuess(false); // R1 visible(병듦) 에 '문제 있음' → 정답
    s.recordGuess(true); // R2 varroa(병듦) 에 '건강함' → 오답
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
}
