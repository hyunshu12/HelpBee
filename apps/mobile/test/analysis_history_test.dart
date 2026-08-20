// 진단 이력 탭 — 하드코딩 빈 화면이던 걸 실제 목록으로 바꾼 뒤의 회귀 잠금.
//
// 배경: 이 화면은 원래 EmptyState 하나만 렌더하는 플레이스홀더였고, 백엔드
// `GET /v1/analyses`가 hiveId 필수라 전체 이력을 받을 방법이 없었다. hiveId를
// optional로 열면서 화면을 실제 목록으로 교체했다. 여기서 잠그는 것:
//  ① 여러 벌통의 이력이 한 목록에 나오고 벌통 이름이 붙는다
//  ② 이력이 없으면(진짜 0건) 빈 상태, 로드 실패면 에러 상태 — 둘을 섞지 않는다
//  ③ 실패한 분석 카드가 가로로 넘치지 않는다 (hive_detail 타임라인과 같은 회귀)

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/core/errors/app_exception.dart';
import 'package:helpbee/core/errors/error_code.dart';
import 'package:helpbee/core/text/korean_wrap.dart';
import 'package:helpbee/features/analyses/data/analyses_api.dart';
import 'package:helpbee/features/analyses/data/analysis_dto.dart';
import 'package:helpbee/features/analyses/presentation/analysis_history_screen.dart';
import 'package:helpbee/features/hives/data/hive_dto.dart';
import 'package:helpbee/features/hives/presentation/hives_list_controller.dart';
import 'package:helpbee/l10n/app_localizations.dart';

const _hiveA = 'hive-a';
const _hiveB = 'hive-b';

Hive _hive(String id, String name) => Hive(
      id: id,
      userId: 'u1',
      name: name,
      createdAt: DateTime.utc(2026, 8, 12),
      updatedAt: DateTime.utc(2026, 8, 12),
    );

Analysis _analysis(
  String id, {
  required String hiveId,
  String status = 'success',
  int? risk,
  DateTime? analyzedAt,
}) =>
    Analysis(
      id: id,
      hiveId: hiveId,
      imageId: 'img-$id',
      status: status,
      varroaInfectionRisk: risk,
      analyzedAt: analyzedAt ?? DateTime.utc(2026, 8, 20, 11, 12),
      createdAt: DateTime.utc(2026, 8, 20),
      updatedAt: DateTime.utc(2026, 8, 20),
    );

/// hivesListControllerProvider는 repo+auth에 의존하므로, 화면 테스트에서는
/// 컨트롤러 자체를 대체해 이름 조인만 고정한다.
class _FakeHivesController extends HivesListController {
  _FakeHivesController(this._hives);

  final List<Hive> _hives;

  @override
  Future<List<Hive>> build() async => _hives;
}

Future<void> _pump(
  WidgetTester tester, {
  required Future<List<Analysis>> Function() history,
  List<Hive> hives = const [],
}) async {
  // iPhone 세로 폭 — 오버플로가 실제로 터졌던 조건을 재현한다.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        allAnalysesProvider.overrideWith((ref) => history()),
        hivesListControllerProvider
            .overrideWith(() => _FakeHivesController(hives)),
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
        home: AnalysisHistoryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('여러 벌통의 진단이 한 목록에 벌통 이름과 함께 나온다', (tester) async {
    await _pump(
      tester,
      hives: [_hive(_hiveA, '가별벌통'), _hive(_hiveB, '안산루트창업캠프')],
      history: () async => [
        _analysis('a1', hiveId: _hiveA, risk: 35),
        _analysis('b1',
            hiveId: _hiveB,
            risk: 90,
            analyzedAt: DateTime.utc(2026, 8, 19, 9)),
      ],
    );

    expect(find.text('가별벌통'), findsOneWidget);
    expect(find.text('안산루트창업캠프'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
    expect(find.text('90'), findsOneWidget);
    // 서버가 준 순서(최신순)를 화면이 재정렬하지 않는다.
    final cards = tester.widgetList<Text>(find.text('가별벌통')).length +
        tester.widgetList<Text>(find.text('안산루트창업캠프')).length;
    expect(cards, 2);
  });

  testWidgets('이력이 0건이면 빈 상태를 보여준다', (tester) async {
    await _pump(tester, history: () async => []);

    final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
    expect(find.text(l10n.historyEmptyTitle), findsOneWidget);
    expect(find.text(keepAll(l10n.historyEmptyBody)), findsOneWidget);
  });

  testWidgets('로드 실패는 빈 상태가 아니라 에러 상태 + 다시 시도로 구분된다', (tester) async {
    await _pump(
      tester,
      history: () async => throw const AppException(ErrorCode.serverError),
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
    expect(find.text(l10n.historyErrorTitle), findsOneWidget);
    expect(find.text(l10n.commonRetry), findsOneWidget);
    // 실패를 "아직 진단 없음"으로 오해하게 두지 않는다.
    expect(find.text(l10n.historyEmptyTitle), findsNothing);
  });

  testWidgets('실패한 분석 카드가 가로로 넘치지 않는다', (tester) async {
    // 오버플로가 나면 위젯 테스트가 자동 실패하므로 별도 단언이 필요 없다.
    await _pump(
      tester,
      hives: [_hive(_hiveA, '가별벌통')],
      history: () async => [_analysis('a1', hiveId: _hiveA, status: 'failed')],
    );

    final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
    expect(find.text(keepAll(l10n.errAiUnavailable)), findsOneWidget);
  });

  testWidgets('벌통 목록이 아직 없어도 카드는 사라지지 않는다', (tester) async {
    // 이름 조인은 부가 정보 — 못 찾아도 진단 자체는 보여야 한다.
    await _pump(
      tester,
      hives: const [],
      history: () async => [_analysis('a1', hiveId: _hiveA, risk: 35)],
    );

    expect(find.text('35'), findsOneWidget);
  });
}
