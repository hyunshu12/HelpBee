import 'dart:math';

import 'booth_case.dart';
import 'case_kind.dart';
import 'risk_tier.dart';

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

/// 풀에서 3장을 뽑아 **난이도 계단** 순서로 배정한다 (설계 §2).
///
///   R1 쉬움      눈에 보이는 병       → 대개 맞힘. 자신감이 붙는다
///   R2 어려움    응애 위험 | 정상      → 대개 틀림. "어? 뭐가 문제였지"
///   R3 더 어려움  응애 주의 | 정상      → 더 미세하거나, 의심병을 찌르는 함정
///
/// 순서가 이야기다. R1 의 성공이 있어야 R2 의 실패가 대비로 살고, R3 에 뭐가
/// 나올지 모르므로 마지막까지 진지하게 본다.
///
/// **2026-09-14: R2 에도 정상을 섞었다.** 그전에는 R1·R2 가 둘 다 확정으로 병든
/// 벌통이라, 관람객이 사진을 보지 않고 "문제 있음"만 세 번 눌러도 최소 2장을
/// 맞혔다(실측 피드백 "생각보다 맞추기 쉬운데"). 눈이 아니라 확률로 맞히는
/// 체험은 이 부스가 하려는 말과 정반대다. 이제 같은 전략의 기대값은 3장 중
/// 2.0장으로 내려가고, "건강함"만 누르는 전략도 1.0장에 그친다.
///
/// 후보가 빈 군이 있으면 그 군은 풀 전체에서 아무거나 채운다 — 부스가 데이터
/// 사고로 멈추는 것보다는 순서가 틀리는 게 낫다. 이미 뽑힌 사진은 제외해
/// 한 세션에 같은 사진이 두 번 나오지 않게 한다.
List<BoothCase> assignRounds(List<BoothCase> pool, Random rng) {
  final taken = <String>{};

  BoothCase pick(bool Function(BoothCase) where) {
    final fresh = pool
        .where((c) => !taken.contains(c.id))
        .toList(growable: false);
    final candidates = fresh.where(where).toList(growable: false);
    final from = candidates.isNotEmpty
        ? candidates
        : (fresh.isNotEmpty ? fresh : pool);
    final chosen = from[rng.nextInt(from.length)];
    taken.add(chosen.id);
    return chosen;
  }

  bool healthy(BoothCase c) => c.kind == CaseKind.healthy;

  final r1 = pick((c) => c.kind == CaseKind.visible);
  // 동전 던지기로 병/정상을 고른다 — 관람객이 라운드 번호만 보고 답을 추론할 수
  // 없어야 한다.
  final r2 = rng.nextBool()
      ? pick((c) => c.kind == CaseKind.varroa && c.tier == RiskTier.danger)
      : pick(healthy);
  final r3 = rng.nextBool()
      ? pick((c) => c.kind == CaseKind.varroa && c.tier == RiskTier.watch)
      : pick(healthy);
  return [r1, r2, r3];
}
