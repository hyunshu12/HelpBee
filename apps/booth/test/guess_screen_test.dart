import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/screens/guess_screen.dart';
import 'package:helpbee_booth/widgets/bbox_overlay.dart';

import 'test_surface.dart';

const _c = BoothCase(
  id: 'watch-50',
  photo: 'photos/watch-50.jpg',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 50,
  tier: RiskTier.watch,
  beeTotal: 14,
  varroaCount: 1,
  recommendations: ['처치를 검토하세요.'],
  boxes: [BoothBox(x: 10, y: 10, w: 100, h: 100, cls: 'varroa')],
);

void main() {
  testWidgets('세 버튼이 각각 true/false/null을 돌려준다', (tester) async {
    await useBoothSurface(tester);
    final answers = <Object?>[];
    Widget app() => MaterialApp(
      home: Scaffold(
        body: GuessScreen(case_: _c, onAnswer: answers.add),
      ),
    );

    await tester.pumpWidget(app());
    await tester.tap(find.text('건강함'));
    await tester.pumpWidget(app());
    await tester.tap(find.text('문제 있음'));
    await tester.pumpWidget(app());
    await tester.tap(find.text('바로 결과 보기'));

    expect(answers, [true, false, null]);
  });

  testWidgets('추측 화면에는 박스를 그리지 않는다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuessScreen(case_: _c, onAnswer: (_) {}),
        ),
      ),
    );
    expect(find.text('이 벌통, 건강해 보이나요?'), findsOneWidget);
    // 정답(박스)을 미리 보여주면 추측이 무의미해진다. 질문 문구만 확인하면
    // 오버레이를 넣어도 통과하므로 부재를 직접 단언한다.
    expect(find.byType(BboxOverlay), findsNothing);
  });
}
