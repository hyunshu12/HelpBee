import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/widgets/trend_chart.dart';

import 'test_surface.dart';

void main() {
  testWidgets('점이 없어도 1개여도 예외 없이 그린다', (tester) async {
    await useBoothSurface(tester);
    for (final scores in [
      <int>[],
      [50],
      [12, 28, 21, 45, 90],
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 300,
              child: TrendChart(scores: scores, seedCount: 4),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('예시 기록 표기가 붙는다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 300,
            child: TrendChart(scores: [12, 28, 21, 45], seedCount: 4),
          ),
        ),
      ),
    );
    expect(find.text('예시 기록'), findsOneWidget);
  });
}
