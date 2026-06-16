// Widget smoke tests for shared building blocks. These avoid platform plugins
// (secure storage / prefs / network) so they run deterministically in CI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/shared/widgets/brand_wordmark.dart';
import 'package:helpbee/shared/widgets/primary_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('BrandWordmark renders the HelpBee wordmark', (tester) async {
    await tester.pumpWidget(_wrap(const BrandWordmark()));
    expect(find.text('HelpBee'), findsOneWidget);
  });

  testWidgets('PrimaryButton shows its label and fires onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(PrimaryButton(label: '로그인하기', onPressed: () => taps++)),
    );

    expect(find.text('로그인하기'), findsOneWidget);
    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('PrimaryButton in loading state shows a spinner and ignores taps',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(PrimaryButton(label: '로그인하기', loading: true, onPressed: () => taps++)),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(PrimaryButton));
    await tester.pump();
    expect(taps, 0);
  });
}
