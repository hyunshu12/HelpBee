import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/screens/guess_screen.dart';
import 'package:helpbee_booth/widgets/surfaces.dart';
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

  // 2026-08-31 회귀: 액자가 사진 비율을 따라가지 않으면 위아래(또는 좌우)에
  // 커다란 흰 띠가 남는다. 부스 기준 해상도(1366x1024)에서는 사진 자리가
  // 우연히 16:9 에 가까워 차이가 안 나므로, 차이가 실제로 드러나는 **세로가
  // 더 긴 캔버스**에서 잰다(웹 백업의 브라우저 창이 이 모양이다).
  testWidgets('세로가 긴 캔버스에서도 액자가 사진 비율(16:9)에 붙는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1366, 1150));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuessScreen(case_: _c, onAnswer: (_) {}),
        ),
      ),
    );

    // PhotoFrame 위젯 자체가 아니라 **실제로 보이는 액자 안쪽**을 잰다.
    // PhotoFrame 은 Center 로 감싸져 있어 위젯 크기는 늘 부모 크기이고,
    // 그걸 재면 무엇을 바꿔도 통과하는 공허한 단언이 된다.
    final photo = tester.getSize(
      find
          .descendant(
            of: find.byType(PhotoFrame),
            matching: find.byType(ClipRRect),
          )
          .first,
    );

    expect(
      photo.width / photo.height,
      closeTo(16 / 9, 0.06),
      reason: '액자가 사진 비율을 벗어나면 흰 띠가 생긴다',
    );
  });
}
