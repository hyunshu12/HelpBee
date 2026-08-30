import 'package:flutter/foundation.dart';

/// 좌상단 연타로 발동하는 운영자 강제 초기화 제스처.
///
/// 관람객이 우연히 누르는 것과 구분하려고 **3초 안에 5번**을 요구한다.
/// `DateTime.now()` 를 안에서 부르지 않고 주입받아 테스트 가능하게 둔다.
class OperatorGesture {
  OperatorGesture({
    this.requiredTaps = 5,
    this.window = const Duration(seconds: 3),
  });

  final int requiredTaps;
  final Duration window;
  final List<DateTime> _taps = [];

  /// 탭 1회를 기록한다. 발동 조건을 채우면 true 를 돌려주고 기록을 비운다.
  bool tap(DateTime now) {
    _taps.add(now);
    _taps.removeWhere((t) => now.difference(t) > window);
    if (_taps.length >= requiredTaps) {
      _taps.clear();
      return true;
    }
    return false;
  }

  @visibleForTesting
  int get pendingTaps => _taps.length;
}
