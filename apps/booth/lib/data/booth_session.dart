import 'dart:math';

import 'package:flutter/foundation.dart';

import 'booth_case.dart';
import 'tour.dart';

/// 관람객 한 명의 투어 상태 (설계 §2).
///
/// 2026-09-08: 추이 그래프(seedScores/chartScores)는 제거됐다 — 요약 화면이
/// "이번 체험 3장"을 보여주므로 역할이 겹쳤다.
class BoothSession extends ChangeNotifier {
  static const int roundCount = 3;

  List<BoothCase> _rounds = const [];
  final List<TourResult> _results = [];

  List<BoothCase> get rounds => List.unmodifiable(_rounds);
  List<TourResult> get results => List.unmodifiable(_results);

  /// 지금 몇 번째 라운드인가 (0-based). 아직 답하지 않은 라운드를 가리킨다.
  int get roundIndex => _results.length;

  /// 마지막 라운드인가. 발표 시연은 2장짜리라(2026-09-17) [roundCount] 가 아니라
  /// **실제 배정된 장수**를 본다.
  bool get isLastRound => roundIndex == _rounds.length - 1;

  BoothCase? get currentCase =>
      roundIndex < _rounds.length ? _rounds[roundIndex] : null;

  int get correctCount => _results.where((r) => r.correct).length;

  /// 새 투어를 시작한다 — **항상** [kShowcaseIds] 고정 세트(가장 어려운 3장).
  ///
  /// 2026-09-16 부스 당일 결정: 누가 오든 같은 3장. 랜덤([assignRounds])은 풀에
  /// 고정 세트 사진이 없을 때(데이터 교체 등)의 폴백으로만 남는다.
  /// [showcase] 는 이제 무시된다 — 호출부 호환용.
  /// [rounds] 는 몇 장만 쓸지 (발표 시연 = 2). 기본은 [roundCount].
  void startTour(
    List<BoothCase> pool, {
    Random? rng,
    bool showcase = true,
    int rounds = roundCount,
  }) {
    final full = showcaseRounds(pool) ?? assignRounds(pool, rng ?? Random());
    // 발표 시연은 앞 2장만 쓴다 — 청중 앞에서 3장은 길다. 앞에서 자르므로
    // 순서(정상 함정 → 응애)는 그대로 살아 있다.
    _rounds = full.take(rounds).toList(growable: false);
    _results.clear();
    notifyListeners();
  }

  /// 지금 라운드가 병명 택1(1라운드)인가.
  bool get isDiseaseRound => roundIndex == 0;

  /// 현재 라운드에 대한 건강/문제 추측을 기록한다 (2·3라운드).
  /// 3장이 끝난 뒤 더 부르면 아무 일도 하지 않는다.
  void recordGuess(bool? guess) {
    final c = currentCase;
    if (c == null) return;
    _results.add(TourResult(case_: c, guess: guess));
    notifyListeners();
  }

  /// 현재 라운드에 대한 병명 추측을 기록한다 (1라운드). null=건너뜀.
  void recordDiseaseGuess(String? diseaseId) {
    final c = currentCase;
    if (c == null) return;
    _results.add(TourResult(case_: c, diseaseGuess: diseaseId));
    notifyListeners();
  }

  void reset() {
    _rounds = const [];
    _results.clear();
    notifyListeners();
  }
}
