import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/screens/picker_screen.dart';

import 'test_surface.dart';

BoothCase _case(String id, RiskTier tier, int risk) => BoothCase(
  id: id,
  photo: 'photos/$id.jpg',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: risk,
  tier: tier,
  beeTotal: 6,
  varroaCount: tier == RiskTier.safe ? 0 : 1,
  recommendations: const [],
  boxes: const [],
);

final _cases = [
  _case('danger-100', RiskTier.danger, 100),
  _case('danger-90', RiskTier.danger, 90),
  _case('watch-50', RiskTier.watch, 50),
  _case('safe-0', RiskTier.safe, 0),
];

void main() {
  testWidgets('네 장을 모두 그린다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickerScreen(cases: _cases, onPick: (_) {}),
        ),
      ),
    );
    expect(find.byType(Image), findsNWidgets(4));
  });

  testWidgets('카드 N 을 누르면 케이스 N 이 전달된다', (tester) async {
    await useBoothSurface(tester);
    final picked = <String>[];
    Widget app() => MaterialApp(
      home: Scaffold(
        body: PickerScreen(cases: _cases, onPick: (c) => picked.add(c.id)),
      ),
    );
    for (var i = 0; i < _cases.length; i++) {
      await tester.pumpWidget(app());
      await tester.tap(find.byType(InkWell).at(i));
    }
    // 모든 카드가 첫 케이스를 넘기는 회귀를 잡는다 — 그러면 관람객 전원이 같은 결과를 본다.
    expect(picked, ['danger-100', 'danger-90', 'watch-50', 'safe-0']);
  });

  testWidgets('카드에 티어나 점수를 표시하지 않는다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickerScreen(cases: _cases, onPick: (_) {}),
        ),
      ),
    );
    // 고르기 전에 답이 보이면 추측 단계가 무의미해진다.
    for (final word in ['위험', '주의', '안전', '100', '90', '50']) {
      expect(find.text(word), findsNothing, reason: '카드에 "$word" 가 보이면 안 된다');
    }
  });
}
