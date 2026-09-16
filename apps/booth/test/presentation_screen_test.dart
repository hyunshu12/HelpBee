import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/slide_deck.dart';
import 'package:helpbee_booth/screens/presentation_screen.dart';
import 'package:helpbee_booth/theme/app_theme.dart';

import 'test_surface.dart';

/// 존재하지 않는 에셋 경로 — 화면의 errorBuilder 가 대신 그리므로 이미지 없이도
/// 넘김 로직을 검증할 수 있다.
SlideDeck _deck({int? demo}) => SlideDeck([
  'assets/slides/99a.png',
  'assets/slides/99b.png',
  'assets/slides/99c.png',
], demoIndex: demo);

Widget _wrap(SlideDeck d, {VoidCallback? onDemo, VoidCallback? onExit}) =>
    MaterialApp(
      theme: boothTheme(),
      home: Scaffold(
        body: PresentationScreen(
          deck: d,
          onDemo: onDemo ?? () {},
          onExit: onExit ?? () {},
        ),
      ),
    );

void main() {
  testWidgets('오른쪽 절반 탭 = 다음, 왼쪽 절반 탭 = 이전, 카운터가 따라온다', (tester) async {
    await useBoothSurface(tester);
    final d = _deck();
    await tester.pumpWidget(_wrap(d));
    expect(find.text('1 / 3'), findsOneWidget);

    await tester.tapAt(const Offset(1000, 500));
    await tester.pump();
    expect(d.index, 1);
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.tapAt(const Offset(300, 500));
    await tester.pump();
    expect(d.index, 0);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('첫 장에서 왼쪽 탭은 무시된다', (tester) async {
    await useBoothSurface(tester);
    final d = _deck();
    var exits = 0;
    await tester.pumpWidget(_wrap(d, onExit: () => exits++));
    await tester.tapAt(const Offset(300, 500));
    await tester.pump();
    expect(d.index, 0);
    expect(exits, 0);
  });

  testWidgets('마지막 장에서 오른쪽 탭이면 onExit 한 번', (tester) async {
    await useBoothSurface(tester);
    final d = _deck()..index = 2;
    var exits = 0;
    await tester.pumpWidget(_wrap(d, onExit: () => exits++));
    await tester.tapAt(const Offset(1000, 500));
    await tester.pump();
    expect(exits, 1);
  });

  testWidgets('스와이프로도 넘긴다 — 왼쪽으로 = 다음, 오른쪽으로 = 이전', (tester) async {
    await useBoothSurface(tester);
    final d = _deck();
    await tester.pumpWidget(_wrap(d));
    await tester.fling(
      find.byType(PresentationScreen),
      const Offset(-400, 0),
      3000,
    );
    await tester.pump();
    expect(d.index, 1);
    await tester.fling(
      find.byType(PresentationScreen),
      const Offset(400, 0),
      3000,
    );
    await tester.pump();
    expect(d.index, 0);
  });

  testWidgets('키보드 → / PageDown / Space 는 다음, ← / PageUp 은 이전 (프레젠터 리모컨)', (
    tester,
  ) async {
    await useBoothSurface(tester);
    final d = _deck();
    await tester.pumpWidget(_wrap(d));
    await tester.pump(); // autofocus

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(d.index, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(d.index, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(d.index, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(d.index, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(d.index, 1);
  });

  testWidgets('"시연 시작 →" 은 시연 장에만 뜨고, 누르면 onDemo', (tester) async {
    await useBoothSurface(tester);
    final d = _deck(demo: 1);
    var demos = 0;
    await tester.pumpWidget(_wrap(d, onDemo: () => demos++));
    expect(find.text('시연 시작 →'), findsNothing);

    await tester.tapAt(const Offset(1000, 500));
    await tester.pump();
    expect(find.text('시연 시작 →'), findsOneWidget);

    await tester.tap(find.text('시연 시작 →'));
    await tester.pump();
    expect(demos, 1);
    expect(d.index, 1, reason: '버튼 탭이 화면 절반 탭으로 새어 넘어가면 안 된다');
  });

  testWidgets('이미지가 없어도 화면이 죽지 않는다 (errorBuilder)', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(_wrap(_deck()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(PresentationScreen), findsOneWidget);
  });
}
