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

  bool get isLastRound => roundIndex == roundCount - 1;

  BoothCase? get currentCase =>
      roundIndex < _rounds.length ? _rounds[roundIndex] : null;

  int get correctCount => _results.where((r) => r.correct).length;

  /// 풀에서 3장을 뽑아 새 투어를 시작한다.
  void startTour(List<BoothCase> pool, {Random? rng}) {
    _rounds = assignRounds(pool, rng ?? Random());
    _results.clear();
    notifyListeners();
  }

  /// 현재 라운드에 대한 관람객 추측을 기록한다.
  /// 3장이 끝난 뒤 더 부르면 아무 일도 하지 않는다.
  void recordGuess(bool? guess) {
    final c = currentCase;
    if (c == null) return;
    _results.add(TourResult(case_: c, guess: guess));
    notifyListeners();
  }

  void reset() {
    _rounds = const [];
    _results.clear();
    notifyListeners();
  }
}
