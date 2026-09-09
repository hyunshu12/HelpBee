import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/case_kind.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/screens/analyzing_screen.dart';

import 'test_surface.dart';

const _c = BoothCase(
  id: 'danger-90',
  photo: 'photos/danger-90.jpg',
  kind: CaseKind.varroa,
  disease: 'varroa',
  diseaseLabel: '응애',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 90,
  tier: RiskTier.danger,
  beeTotal: 6,
  sickCount: 1,
  recommendations: ['즉시 처치가 필요합니다.'],
  boxes: [],
);

void main() {
  testWidgets('탐지 마리 수를 보여주고 약 4초 뒤 onDone을 부른다', (tester) async {
    await useBoothSurface(tester);
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnalyzingScreen(case_: _c, onDone: () => done = true),
        ),
      ),
    );

    // 첫 프레임은 '사진을 읽는 중'이다. 두 번째 단계에서 마리 수가 나온다.
    expect(find.text('사진을 읽는 중'), findsOneWidget);
    expect(done, isFalse);

    // 2026-09-08: 1.5초는 관람객이 단계를 읽기도 전에 지나갔다 → 1.3초 x 3단계.
    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.textContaining('6마리'), findsOneWidget);
    expect(done, isFalse, reason: '1.4초에 끝나면 단계를 읽을 시간이 없다');

    await tester.pump(const Duration(milliseconds: 1400));
    expect(done, isFalse);

    await tester.pump(const Duration(milliseconds: 1400));
    expect(done, isTrue);
  });
}
