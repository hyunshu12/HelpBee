import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/screens/report_screen.dart';

import 'test_surface.dart';

// 실제 danger-100 케이스(assets/cases.json)의 recommendations 5개를 그대로 옮김 —
// 위험 티어의 실제 최악 케이스(처방 5개)로 오버플로 유무를 검증하기 위함.
BoothCase _danger() => const BoothCase(
  id: 'danger-90',
  photo: 'photos/danger-90.jpg',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 90,
  tier: RiskTier.danger,
  beeTotal: 6,
  varroaCount: 1,
  recommendations: [
    '응애 감염률이 위험 범위(10% 이상)입니다. 즉시 처치가 필요합니다.',
    '우선 alcohol wash 또는 sugar roll로 정확한 mite-per-100-bees를 측정하세요.',
    '수의사 또는 양봉 전문가 자문 후 처치제(개미산/옥살산/Apivar)를 적용하세요.',
    '주변 벌통도 함께 검사하세요 — 응애는 봉간 전파됩니다.',
    'AI 추정치는 참고용입니다. 정확한 감염 정도는 실측 검사(가루설탕/알코올워시)를 병행하세요.',
  ],
  boxes: [BoothBox(x: 519, y: 71, w: 811, h: 636, cls: 'varroa')],
);

BoothCase _safe() => const BoothCase(
  id: 'safe-0',
  photo: 'photos/safe-0.jpg',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 0,
  tier: RiskTier.safe,
  beeTotal: 6,
  varroaCount: 0,
  recommendations: ['응애 감염률이 안전 범위(3% 미만)입니다. 정기 모니터링을 유지하세요.'],
  boxes: [BoothBox(x: 100, y: 100, w: 200, h: 200, cls: 'normal')],
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('위험도 점수와 티어를 보여준다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      _wrap(ReportScreen(case_: _danger(), guess: null, onRestart: () {})),
    );
    expect(find.text('90'), findsOneWidget);
    expect(find.text('위험'), findsOneWidget);
  });

  testWidgets('처방은 첫 줄만 보이고 나머지는 접혀 있다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      _wrap(ReportScreen(case_: _danger(), guess: null, onRestart: () {})),
    );
    expect(find.textContaining('즉시 처치가 필요합니다'), findsOneWidget);
    expect(find.textContaining('alcohol wash'), findsNothing);

    await tester.tap(find.text('처방 더 보기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('alcohol wash'), findsOneWidget);
  });

  testWidgets('틀린 추측은 내 답과 함께 위로하는 문구를 보여준다', (tester) async {
    await useBoothSurface(tester);
    // 위험 벌통을 '건강함' 이라고 답한 경우
    await tester.pumpWidget(
      _wrap(ReportScreen(case_: _danger(), guess: true, onRestart: () {})),
    );
    expect(find.text('당신: 건강함'), findsOneWidget);
    expect(find.textContaining('전문가도 어렵습니다'), findsOneWidget);
  });

  testWidgets('맞힌 추측은 정확하다고 알려준다', (tester) async {
    await useBoothSurface(tester);
    // 정상 벌통을 '건강함' 이라고 답한 경우
    await tester.pumpWidget(
      _wrap(ReportScreen(case_: _safe(), guess: true, onRestart: () {})),
    );
    expect(find.text('당신: 건강함'), findsOneWidget);
    expect(find.textContaining('정확합니다'), findsOneWidget);
  });

  testWidgets('문제 있음 이라고 답하면 그대로 표시된다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      _wrap(ReportScreen(case_: _danger(), guess: false, onRestart: () {})),
    );
    expect(find.text('당신: 문제 있음'), findsOneWidget);
    expect(find.textContaining('정확합니다'), findsOneWidget);
  });

  testWidgets('추측을 건너뛰면 대조 줄이 아예 없다', (tester) async {
    await useBoothSurface(tester);
    // 위 세 테스트가 '당신:' 이 정상적으로는 렌더된다는 걸 증명하므로
    // 이 findsNothing 은 공허하지 않다.
    await tester.pumpWidget(
      _wrap(ReportScreen(case_: _danger(), guess: null, onRestart: () {})),
    );
    expect(find.textContaining('당신'), findsNothing);
    expect(find.textContaining('전문가도 어렵습니다'), findsNothing);
    expect(find.textContaining('정확합니다'), findsNothing);
  });

  testWidgets('위험 케이스 처방을 전부 펼쳐도 오버플로가 없다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      _wrap(ReportScreen(case_: _danger(), guess: false, onRestart: () {})),
    );
    await tester.tap(find.text('처방 더 보기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
