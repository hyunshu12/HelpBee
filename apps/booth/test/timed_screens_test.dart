import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/screens/intro_screen.dart';
import 'package:helpbee_booth/screens/outro_screen.dart';

import 'test_surface.dart';

void main() {
  testWidgets('인트로는 3초 뒤 자동 진행한다', (tester) async {
    await useBoothSurface(tester);
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IntroScreen(onDone: () => done = true)),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(done, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(done, isTrue);
  });

  testWidgets('인트로는 터치하면 즉시 넘어간다', (tester) async {
    await useBoothSurface(tester);
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IntroScreen(onDone: () => done = true)),
      ),
    );
    await tester.tap(find.byType(IntroScreen));
    expect(done, isTrue);
    await tester.pump(const Duration(seconds: 4)); // 타이머 정리
  });

  testWidgets('마무리는 15초 뒤 초기화한다', (tester) async {
    await useBoothSurface(tester);
    var reset = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OutroScreen(onRestart: () => reset = true)),
      ),
    );
    await tester.pump(const Duration(seconds: 14));
    expect(reset, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(reset, isTrue);
  });
}
