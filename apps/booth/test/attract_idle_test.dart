import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/case_kind.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/screens/attract_screen.dart';
import 'package:helpbee_booth/screens/report_screen.dart';
import 'package:helpbee_booth/theme/app_theme.dart';
import 'package:helpbee_booth/widgets/bbox_overlay.dart';

import 'test_surface.dart';

/// 부스 배터리 회귀 묶음.
///
/// 어트랙트는 관람객이 없는 **하루의 대부분**을 차지하는 화면이다. 여기서
/// 애니메이션이 쉬지 않으면 아이패드가 8시간 내내 60fps 프레임을 만들어낸다.
/// 화면 밝기 다음으로 배터리를 많이 먹는 항목이고, 코드로 통제 가능한 것 중엔
/// 가장 큰 항목이다.
const _case = BoothCase(
  id: 'danger-100',
  photo: 'photos/danger-100.jpg',
  kind: CaseKind.varroa,
  disease: 'varroa',
  diseaseLabel: '응애',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 100,
  tier: RiskTier.danger,
  beeTotal: 7,
  sickCount: 2,
  recommendations: ['처방'],
  boxes: [
    BoothBox(x: 100, y: 100, w: 300, h: 200, cls: 'varroa'),
    BoothBox(x: 500, y: 150, w: 280, h: 220, cls: 'normal'),
  ],
);

Future<void> _pumpAttract(WidgetTester tester) async {
  await useBoothSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: boothTheme(),
      home: Scaffold(
        body: AttractScreen(case_: _case, onStart: () {}),
      ),
    ),
  );
}

void main() {
  // 어트랙트의 안내 칩 맥박은 **일부러** 계속 뛴다 — 2026-09-08 실기기에서
  // 쉬는 구간을 넣어 봤더니 화면이 죽어 보여 시선을 못 끌었다. 그래서 여기서는
  // "멈추는가"가 아니라 "계속 뛰더라도 사진·게이지까지 다시 그리지는 않는가"를
  // 본다(아래 독립 레이어 테스트).

  testWidgets('재생할 때 사진 위젯을 다시 만들지 않는다', (tester) async {
    await _pumpAttract(tester);

    final before = tester.state(find.byType(BboxOverlay));

    // 주기를 두 번 넘긴다.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));

    final after = tester.state(find.byType(BboxOverlay));
    expect(
      identical(before, after),
      isTrue,
      reason:
          '재생마다 State 를 새로 만들면 컨트롤러와 이미지가 매번 다시 생긴다 '
          '— 8시간 부스에서 7,200번이다',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('사진과 게이지가 각각 독립 레이어다', (tester) async {
    await _pumpAttract(tester);
    // 형제가 애니메이션할 때 사진·게이지까지 매 프레임 다시 래스터화되지 않도록
    // RepaintBoundary 로 떼어놨는지 확인한다. (게이지의 MaskFilter.blur 가
    // 이 화면에서 가장 비싼 페인트다.)
    expect(
      find.byType(RepaintBoundary),
      findsAtLeast(2),
      reason: '리페인트 경계가 없으면 펄스 한 번에 사진과 블러가 같이 다시 그려진다',
    );
    await tester.pumpWidget(const SizedBox());
  });

  // 관람객이 결과를 읽는 동안(수십 초) 화면이 계속 애니메이션하면 어트랙트와
  // 같은 낭비가 난다. 결과 화면은 박스가 다 찍힌 뒤 완전히 멈춰야 한다.
  testWidgets('결과 화면은 연출이 끝나면 프레임을 요청하지 않는다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: boothTheme(),
        home: Scaffold(
          body: ReportScreen(
            case_: _case,
            guess: false,
            isLastRound: false,
            isBonus: false,
            onNext: () {},
          ),
        ),
      ),
    );

    for (var i = 0; i < 240 && tester.binding.hasScheduledFrame; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: '관람객이 결과를 읽는 내내 애니메이션이 돌면 배터리를 계속 먹는다',
    );
  });
}
