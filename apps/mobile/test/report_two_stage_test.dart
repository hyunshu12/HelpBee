// 레포트 화면 — v0.2.0 two-stage 상태별 렌더링: VDI 카드 / 판독 불가 / 레거시 게이지.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/features/analyses/data/analysis_dto.dart';
import 'package:helpbee/features/analyses/presentation/analysis_flow_args.dart';
import 'package:helpbee/features/analyses/presentation/report_screen.dart';
import 'package:helpbee/l10n/app_localizations.dart';
import 'package:helpbee/shared/widgets/risk_gauge.dart';

Analysis _analysis({
  String? tier,
  String? vdiDisplay,
  double? vdi,
  double? ciLo,
  double? ciHi,
  int? beeTotal,
  int? beeInfested,
  int? risk,
  String? health,
  bool? corrected,
}) => Analysis(
  id: 'a',
  hiveId: 'h',
  imageId: 'i',
  status: 'success',
  varroaInfectionRisk: risk,
  overallHealth: health,
  createdAt: DateTime.utc(2026, 9, 26),
  updatedAt: DateTime.utc(2026, 9, 26),
  tierRaw: tier,
  vdiDisplay: vdiDisplay,
  vdi: vdi,
  vdiCiLow: ciLo,
  vdiCiHigh: ciHi,
  beeTotal: beeTotal,
  beeInfested: beeInfested,
  corrected: corrected,
);

Widget _app(Analysis a) => ProviderScope(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('ko'),
    home: ReportScreen(
      args: ReportArgs(analysis: a, hiveName: '1번 벌통'),
    ),
  ),
);

void main() {
  testWidgets('two-stage elevated: VDI display string, CI, counts, no gauge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _analysis(
          tier: 'elevated',
          vdiDisplay: '4.2',
          vdi: 4.2,
          ciLo: 2.4,
          ciHi: 6.9,
          beeTotal: 310,
          beeInfested: 14,
          risk: 71,
          health: 'warning',
          corrected: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vdi-display')), findsOneWidget);
    expect(find.text('4.2%'), findsOneWidget);
    expect(find.textContaining('2.4%'), findsOneWidget);
    expect(find.textContaining('310'), findsOneWidget);
    expect(find.text('주의 단계'), findsOneWidget);
    expect(find.byType(RiskGauge), findsNothing);
  });

  testWidgets('insufficient: retake copy, no gauge, no VDI', (tester) async {
    await tester.pumpWidget(
      _app(_analysis(tier: 'insufficient', beeTotal: 0, beeInfested: 0)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insufficient-body')), findsOneWidget);
    expect(find.byKey(const Key('vdi-display')), findsNothing);
    expect(find.byType(RiskGauge), findsNothing);
  });

  testWidgets('legacy row keeps the score gauge', (tester) async {
    await tester.pumpWidget(_app(_analysis(risk: 84, health: 'critical')));
    await tester.pumpAndSettle();
    expect(find.byType(RiskGauge), findsOneWidget);
    expect(find.byKey(const Key('vdi-display')), findsNothing);
  });
}
