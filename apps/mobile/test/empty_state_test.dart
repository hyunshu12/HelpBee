// Regression tests: SecondaryButton / EmptyState must actually RENDER.
// Previously nothing rendered SecondaryButton, hiding a Material assertion
// (`shape` + `borderRadius` set together) that crashed the empty home screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/shared/widgets/empty_state.dart';
import 'package:helpbee/shared/widgets/secondary_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('SecondaryButton renders without throwing and fires onPressed',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(SecondaryButton(label: '등록', onPressed: () => taps++)),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('등록'), findsOneWidget);
    await tester.tap(find.byType(SecondaryButton));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('EmptyState with an action button renders (no assertion crash)',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_wrap(
      EmptyState(
        icon: Icons.hive_outlined,
        title: '등록된 양봉장이 없어요',
        message: '아래 버튼으로 첫 양봉장을 등록해 보세요',
        actionLabel: '양봉장 등록',
        onAction: () => tapped++,
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('등록된 양봉장이 없어요'), findsOneWidget);
    expect(find.text('양봉장 등록'), findsOneWidget);
    await tester.tap(find.text('양봉장 등록'));
    await tester.pump();
    expect(tapped, 1);
  });
}
