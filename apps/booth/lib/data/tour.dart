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
  /// "HelpBee 는 3장 다 찾았습니다" 대비가 약해진다.
  bool get correct => guess != null && guess == case_.isHealthy;
}

/// 풀에서 3장을 뽑아 **난이도 계단** 순서로 배정한다 (설계 §2).
///
///   R1 쉬움      눈에 보이는 병      → 대개 맞힘. 자신감이 붙는다
///   R2 어려움    응애 위험           → 대개 틀림. "어? 뭐가 문제였지"
///   R3 더 어려움  응애 주의 | 정상     → 더 미세하거나, 의심병을 찌르는 함정
///
/// 순서가 이야기다. R1 의 성공이 있어야 R2 의 실패가 대비로 살고, R3 에 뭐가
/// 나올지 모르므로 마지막까지 진지하게 본다.
///
/// 세 후보군이 서로 겹치지 않아(R2 는 danger, R3 는 watch|healthy) 중복 걱정이
/// 없다. 후보가 빈 군이 있으면 그 군은 풀 전체에서 아무거나 채운다 — 부스가
/// 데이터 사고로 멈추는 것보다는 순서가 틀리는 게 낫다.
List<BoothCase> assignRounds(List<BoothCase> pool, Random rng) {
  BoothCase pick(bool Function(BoothCase) where) {
    final candidates = pool.where(where).toList(growable: false);
    final from = candidates.isEmpty ? pool : candidates;
    return from[rng.nextInt(from.length)];
  }

  final r1 = pick((c) => c.kind == CaseKind.visible);
  final r2 = pick(
    (c) => c.kind == CaseKind.varroa && c.tier == RiskTier.danger,
  );
  final r3 = pick(
    (c) =>
        c.kind == CaseKind.healthy ||
        (c.kind == CaseKind.varroa && c.tier == RiskTier.watch),
  );
  return [r1, r2, r3];
}
