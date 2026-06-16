// Widget smoke tests for HiveCard (no platform plugins / network).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/shared/widgets/hive_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('HiveCard shows name + subtitle and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(
      HiveCard(name: '양봉장 1호', subtitle: '경기도 양평군', onTap: () => taps++),
    ));

    expect(find.text('양봉장 1호'), findsOneWidget);
    expect(find.text('경기도 양평군'), findsOneWidget);

    await tester.tap(find.byType(HiveCard));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('HiveCard renders without a subtitle', (tester) async {
    await tester.pumpWidget(_wrap(const HiveCard(name: '벌통')));
    expect(find.text('벌통'), findsOneWidget);
  });
}
