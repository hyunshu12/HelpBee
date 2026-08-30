import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/operator_gesture.dart';

void main() {
  final t0 = DateTime(2026, 9, 15, 10);

  test('3초 안에 5번 누르면 발동한다', () {
    final g = OperatorGesture();
    for (var i = 0; i < 4; i++) {
      expect(g.tap(t0.add(Duration(milliseconds: 200 * i))), isFalse);
    }
    expect(g.tap(t0.add(const Duration(milliseconds: 800))), isTrue);
  });

  test('창을 넘긴 탭은 세지 않는다', () {
    final g = OperatorGesture();
    for (var i = 0; i < 4; i++) {
      g.tap(t0.add(Duration(milliseconds: 200 * i)));
    }
    // 4초 뒤 한 번 더 — 앞의 4번은 만료됐으므로 발동하면 안 된다.
    expect(g.tap(t0.add(const Duration(seconds: 4))), isFalse);
    expect(g.pendingTaps, 1);
  });

  test('발동 후 기록이 비워져 연속 발동하지 않는다', () {
    final g = OperatorGesture();
    for (var i = 0; i < 5; i++) {
      g.tap(t0.add(Duration(milliseconds: 100 * i)));
    }
    expect(g.tap(t0.add(const Duration(milliseconds: 600))), isFalse);
  });
}
