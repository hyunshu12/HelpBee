import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/case_kind.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/screens/picker_screen.dart';

import 'test_surface.dart';

BoothCase _case(String id, RiskTier tier, int risk) => BoothCase(
  id: id,
  photo: 'photos/$id.jpg',
  kind: CaseKind.varroa,
  disease: 'varroa',
  diseaseLabel: '응애',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: risk,
  tier: tier,
  beeTotal: 6,
  sickCount: tier == RiskTier.safe ? 0 : 1,
  recommendations: const [],
  boxes: const [],
);

/// 실제 풀과 같은 10장. 5x2 격자가 다 그려지고 마지막 칸까지 눌리는지 본다.
final _cases = [
  _case('danger-100', RiskTier.danger, 100),
  _case('danger-90', RiskTier.danger, 90),
  _case('danger-2', RiskTier.danger, 80),
  _case('watch-50', RiskTier.watch, 50),
  _case('watch-2', RiskTier.watch, 40),
  _case('chalk-1', RiskTier.safe, 0),
  _case('chalk-2', RiskTier.safe, 0),
  _case('dwv-1', RiskTier.safe, 0),
  _case('safe-0', RiskTier.safe, 0),
  _case('safe-2', RiskTier.safe, 0),
];

void main() {
  testWidgets('열 장을 모두 그린다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickerScreen(cases: _cases, onPick: (_) {}),
        ),
      ),
    );
    expect(find.byType(Image), findsNWidgets(10));
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
    expect(picked, [for (final c in _cases) c.id]);
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

  // 2026-08-31 회귀: 고정 childAspectRatio(16/10) GridView 는 캔버스가 가정보다
  // 짧으면(웹 백업의 브라우저 크롬, 기기별 세이프에어리어) 아래 줄을 잘라내
  // 아래 줄 카드를 **아예 누를 수 없게** 만든다. 실제 웹 빌드에서 재현됨.
  testWidgets('캔버스가 짧아도 열 카드 모두 넘침 없이 눌린다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickerScreen(cases: _cases, onPick: (c) => picked.add(c.id)),
        ),
      ),
    );

    expect(tester.takeException(), isNull, reason: '짧은 캔버스에서 레이아웃이 넘치면 안 된다');

    // 마지막 카드까지 실제로 탭이 닿아야 한다 — 잘린 카드는 히트테스트가 안 된다.
    await tester.tap(find.byType(InkWell).at(9), warnIfMissed: false);
    expect(picked, ['safe-2'], reason: '마지막 카드가 화면 밖으로 잘렸다');
  });
}
