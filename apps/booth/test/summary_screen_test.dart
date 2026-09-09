import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/booth_session.dart';
import 'package:helpbee_booth/data/case_kind.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/screens/summary_screen.dart';
import 'package:helpbee_booth/theme/app_theme.dart';

import 'test_surface.dart';

BoothCase _c(String id, CaseKind kind, RiskTier tier) => BoothCase(
  id: id,
  photo: 'photos/$id.jpg',
  kind: kind,
  disease: kind == CaseKind.healthy ? null : 'x',
  diseaseLabel: kind == CaseKind.visible ? '날개불구 바이러스' : null,
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 0,
  tier: tier,
  beeTotal: 10,
  sickCount: kind == CaseKind.healthy ? 0 : 2,
  recommendations: const [],
  boxes: const [],
);

/// R1 visible / R2 varroa / R3 healthy 로 고정된 세션을 만든다.
BoothSession _session(List<bool?> guesses) {
  final s = BoothSession()
    ..startTour([
      _c('dwv-1', CaseKind.visible, RiskTier.safe),
      _c('danger-100', CaseKind.varroa, RiskTier.danger),
      _c('safe-0', CaseKind.healthy, RiskTier.safe),
    ], rng: Random(0));
  for (final g in guesses) {
    s.recordGuess(g);
  }
  return s;
}

Widget _wrap(BoothSession s) => MaterialApp(
  theme: boothTheme(),
  home: Scaffold(
    body: SummaryScreen(session: s, onMore: () {}, onFinish: () {}),
  ),
);

void main() {
  group('summaryHeadline', () {
    test('맞힌 수에 따라 첫 줄이 달라진다', () {
      expect(summaryHeadline(0, 3), contains('한 장도'));
      expect(summaryHeadline(1, 3), contains('1장'));
      expect(summaryHeadline(3, 3), contains('눈이 좋으시네요'));
    });

    test('0장과 3장은 서로 다른 문구다', () {
      // 같으면 관람객이 자기가 몇 장 맞혔는지 알 수 없다.
      expect(summaryHeadline(0, 3), isNot(summaryHeadline(3, 3)));
      expect(summaryHeadline(0, 3), isNot(summaryHeadline(1, 3)));
    });

    test('0장을 탓하지 않는다 — 못 찾는 게 정상이라는 게 메시지다', () {
      expect(summaryHeadline(0, 3), contains('정상'));
    });
  });

  test('라운드 성격 캡션이 종류마다 다르다', () {
    expect(roundCaption(CaseKind.visible), '보이는 병');
    expect(roundCaption(CaseKind.varroa), '안 보이는 병');
    expect(roundCaption(CaseKind.healthy), '함정');
    final all = {
      roundCaption(CaseKind.visible),
      roundCaption(CaseKind.varroa),
      roundCaption(CaseKind.healthy),
    };
    expect(all, hasLength(3), reason: '캡션이 겹치면 세 라운드가 구분되지 않는다');
  });

  testWidgets('세 라운드 결과를 정오답과 함께 보여준다', (tester) async {
    await useBoothSurface(tester);
    // R1 정답(병든 벌통에 '문제 있음') / R2 오답('건강함') / R3 정답('건강함')
    await tester.pumpWidget(_wrap(_session([false, true, true])));

    expect(find.textContaining('2장'), findsWidgets);
    expect(find.text('보이는 병'), findsOneWidget);
    expect(find.text('안 보이는 병'), findsOneWidget);
    expect(find.text('함정'), findsOneWidget);
    expect(find.text('✓'), findsNWidgets(2));
    expect(find.text('✗'), findsOneWidget);
    expect(find.textContaining('HelpBee 는 3장 다 찾았습니다'), findsOneWidget);
  });

  testWidgets('건너뛴 라운드는 — 로 표시한다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(_wrap(_session([false, null, null])));
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('✓'), findsOneWidget);
  });

  testWidgets('사진 3장을 그린다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(_wrap(_session([false, false, false])));
    expect(find.byType(Image), findsNWidgets(3));
  });

  testWidgets('두 버튼이 각각 콜백을 부른다', (tester) async {
    await useBoothSurface(tester);
    var more = 0;
    var finish = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: boothTheme(),
        home: Scaffold(
          body: SummaryScreen(
            session: _session([false, false, false]),
            onMore: () => more++,
            onFinish: () => finish++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('더 해보기'));
    await tester.tap(find.text('QR 받기 →'));
    expect(more, 1);
    expect(finish, 1);
  });
}
