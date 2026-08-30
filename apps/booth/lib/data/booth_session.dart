import 'package:flutter/foundation.dart';

import 'booth_case.dart';

/// 관람객 한 명의 체험 상태. 앱이 초기화되면 history 만 비우고
/// 예시 4점은 그대로 둔다 (설계 §3 [5-a]).
class BoothSession extends ChangeNotifier {
  /// 그래프가 1점짜리로 밋밋해지지 않도록 미리 심어두는 과거 4주치.
  /// 실제 데이터가 아니므로 화면에 "예시 기록"이라고 표기한다.
  static const List<int> seedScores = [12, 28, 21, 45];

  final List<BoothCase> _history = [];

  List<BoothCase> get history => List.unmodifiable(_history);

  List<int> get chartScores => [
    ...seedScores,
    ..._history.map((c) => c.riskScore),
  ];

  void record(BoothCase c) {
    _history.add(c);
    notifyListeners();
  }

  void reset() {
    _history.clear();
    notifyListeners();
  }
}
