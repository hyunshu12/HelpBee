import 'dart:math';

import 'booth_case.dart';
import 'case_kind.dart';

/// 라운드 하나의 결과 — 어떤 사진에 관람객이 뭐라고 답했는가.
class TourResult {
  const TourResult({required this.case_, required this.guess});

  final BoothCase case_;

  /// true=건강함 · false=문제 있음 · null=건너뜀
  final bool? guess;

  /// 건너뛴 라운드는 맞힌 것으로 세지 않는다 — 요약의 "N장 맞힘"이 부풀면
  /// "HelpBee 는 3장 모두 정확히 판정했습니다" 대비가 약해진다.
  bool get correct => guess != null && guess == case_.isHealthy;
}

/// 풀에서 3장을 뽑는다 — **세 라운드 모두 독립 동전던지기 (병 | 정상)**.
///
/// 2026-09-16 까지는 난이도 계단(보이는 병 → 응애 위험 → 응애 주의)이었다.
/// 계단은 이야기로는 좋았지만 두 가지가 문제였다: (1) R1 이 확정으로 병든
/// 벌통이라 "문제 있음"만 눌러도 평균 2장이 맞았고, (2) 계단을 만들려고 눈에
/// 확 띄는 사진(부저병 12/12 같은)을 써야 해서 1라운드가 퀴즈가 아니라 관찰이
/// 됐다. "이거 너무 쉬운데" — 실측 피드백.
///
/// 이제 라운드마다 병/정상을 동전으로 정하고, 병일 때는 응애든 다른 병이든
/// 풀에서 아무거나 뽑는다. 풀 자체가 "눈으로 구분하기 힘든 사진만"으로 짜여
/// 있다(make_booth_cases.py). 어느 한쪽으로만 찍으면 기대값은 정확히 1.5장
/// — 사진을 실제로 봐야만 그 위로 올라간다.
///
/// 한 세션에 같은 사진이 두 번 나오지 않게 뽑힌 것은 제외하고, 한쪽 후보가
/// 다 떨어지면 반대쪽으로 채운다. 풀이 비어 있어도 멈추지 않는다 — 부스가
/// 데이터 사고로 서는 것보다는 배정이 틀리는 게 낫다.
List<BoothCase> assignRounds(List<BoothCase> pool, Random rng) {
  final taken = <String>{};

  BoothCase pick(
    bool Function(BoothCase) where, {
    required bool Function(BoothCase) orElse,
  }) {
    final fresh = pool
        .where((c) => !taken.contains(c.id))
        .toList(growable: false);
    var candidates = fresh.where(where).toList(growable: false);
    if (candidates.isEmpty) {
      candidates = fresh.where(orElse).toList(growable: false);
    }
    final from = candidates.isNotEmpty
        ? candidates
        : (fresh.isNotEmpty ? fresh : pool);
    final chosen = from[rng.nextInt(from.length)];
    taken.add(chosen.id);
    return chosen;
  }

  bool healthy(BoothCase c) => c.kind == CaseKind.healthy;
  bool sick(BoothCase c) => c.kind != CaseKind.healthy;

  BoothCase flip() => rng.nextBool()
      ? pick(sick, orElse: healthy)
      : pick(healthy, orElse: sick);

  return [flip(), flip(), flip()];
}
