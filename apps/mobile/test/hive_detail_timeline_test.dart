// 벌통 상세 타임라인 — 실패한 분석 행이 가로로 넘치지 않는지 잠근다.
//
// 회귀 배경: 실패 행의 값 텍스트는 점수("90점 (위험)")가 아니라 문장
// ("AI 분석 서비스가 일시적으로 불안정해요…")이다. 이걸 라벨과 같은 Row에
// 폭 제한 없이 두면 문장이 폭을 다 가져가 라벨이 0으로 밀리고 Row가 233px 넘쳤다.
// 위젯 테스트는 오버플로가 나면 자동으로 실패하므로 별도 단언이 필요 없다.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/core/text/korean_wrap.dart';
import 'package:helpbee/features/analyses/data/analyses_api.dart';
import 'package:helpbee/features/analyses/data/analysis_dto.dart';
import 'package:helpbee/features/hives/data/hive_dto.dart';
import 'package:helpbee/features/hives/presentation/hive_detail_controller.dart';
import 'package:helpbee/features/hives/presentation/hive_detail_screen.dart';
import 'package:helpbee/l10n/app_localizations.dart';

const _hiveId = 'hive-1';

Hive _hive() => Hive(
      id: _hiveId,
      userId: 'u1',
      name: '양봉장 1호',
      createdAt: DateTime.utc(2026, 8, 12),
      updatedAt: DateTime.utc(2026, 8, 12),
    );

Analysis _analysis({required String status, int? risk}) => Analysis(
      id: 'a-$status',
      hiveId: _hiveId,
      imageId: 'img-1',
      status: status,
      varroaInfectionRisk: risk,
      createdAt: DateTime.utc(2026, 8, 12),
      updatedAt: DateTime.utc(2026, 8, 12),
    );

Future<void> _pump(WidgetTester tester, List<Analysis> analyses) async {
  // iPhone 세로 폭 — 실제 기기에서 넘쳤던 조건을 재현한다.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hiveDetailProvider(_hiveId).overrideWith((ref) async => _hive()),
        hiveAnalysesProvider(_hiveId).overrideWith((ref) async => analyses),
      ],
      child: const MaterialApp(
        locale: Locale('ko'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [Locale('ko')],
        home: HiveDetailScreen(hiveId: _hiveId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('실패한 분석 행이 가로로 넘치지 않는다', (tester) async {
    await _pump(tester, [_analysis(status: 'failed')]);

    final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
    // 렌더링 텍스트에는 keepAll()의 WORD JOINER가 섞이므로 같은 변환을 거쳐 비교한다.
    expect(find.text(keepAll(l10n.errAiUnavailable)), findsOneWidget);
  });

  testWidgets('성공한 분석 행은 라벨과 점수가 한 줄에 유지된다', (tester) async {
    await _pump(tester, [_analysis(status: 'success', risk: 90)]);

    final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
    expect(find.text(l10n.aiAutoDiagnosis), findsOneWidget);
  });
}
