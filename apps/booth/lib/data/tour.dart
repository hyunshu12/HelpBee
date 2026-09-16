import 'dart:math';

import 'booth_case.dart';
import 'case_kind.dart';

/// 1라운드 선택지 — (id, 화면 문구). id 는 [BoothCase.disease] 값과 맞춘다
/// (정상은 disease 가 null 이라 'healthy' 로 둔다).
///
/// 응애는 여기 없다. 1라운드는 "응애 말고도 병이 있고, 그건 찾으면 보인다"를
/// 배우는 자리고, 응애는 2·3라운드에서 "그런데 이건 안 보인다"로 온다.
const List<({String id, String label})> kRound1Choices = [
  (id: 'healthy', label: '정상'),
  (id: 'dwv', label: '날개불구'),
  (id: 'foulbrood', label: '부저병'),
];

/// 케이스의 1라운드 정답 id.
String round1AnswerOf(BoothCase c) => c.disease ?? 'healthy';

/// 라운드 하나의 결과 — 어떤 사진에 관람객이 뭐라고 답했는가.
///
/// 두 종류의 답이 있다. 1라운드는 병명 택1([diseaseGuess]), 2·3라운드와 자유
/// 선택은 건강/문제 2택([guess]). 한 결과에 둘 다 채워지는 일은 없다.
class TourResult {
  const TourResult({required this.case_, this.guess, this.diseaseGuess});

  final BoothCase case_;

  /// true=건강함 · false=문제 있음 · null=답 안 함
  final bool? guess;

  /// [kRound1Choices] 의 id. null=답 안 함.
  final String? diseaseGuess;

  bool get skipped => guess == null && diseaseGuess == null;

  /// 건너뛴 라운드는 맞힌 것으로 세지 않는다 — 요약의 "N장 맞힘"이 부풀면
  /// "HelpBee 는 3장 모두 정확히 판정했습니다" 대비가 약해진다.
  bool get correct {
    if (diseaseGuess != null) return diseaseGuess == round1AnswerOf(case_);
    return guess != null && guess == case_.isHealthy;
  }
}

/// 풀에서 3장을 뽑는다.
///
///   R1  응애를 뺀 나머지 — 정상 | 날개불구 | 부저병. 관람객이 셋 중 하나를 고른다.
///   R2  병든 벌통 (응애·다른 병 아무거나). 건강/문제 2택.
///   R3  병든 벌통. 건강/문제 2택.
///
/// 2026-09-16 확정. 1라운드가 3택이라 찍으면 33%, 2·3라운드는 항상 병든
/// 벌통이지만 "무엇이 문제였는지"를 결과 화면이 보여주는 게 요점이다.
///
/// 한 세션에 같은 사진이 두 번 나오지 않게 뽑힌 것은 제외하고, 후보가 비면
/// 아직 안 나온 아무 사진으로 채운다 — 부스가 데이터 사고로 서는 것보다는
/// 배정이 틀리는 게 낫다.
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

  final round1Ids = {for (final c in kRound1Choices) c.id};
  bool round1(BoothCase c) => round1Ids.contains(round1AnswerOf(c));
  bool sick(BoothCase c) => c.kind != CaseKind.healthy;

  return [pick(round1), pick(sick), pick(sick)];
}
