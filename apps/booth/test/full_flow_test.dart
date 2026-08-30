import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/main.dart';
import 'package:helpbee_booth/screens/analyzing_screen.dart';
import 'package:helpbee_booth/screens/attract_screen.dart';
import 'package:helpbee_booth/screens/guess_screen.dart';
import 'package:helpbee_booth/screens/intro_screen.dart';
import 'package:helpbee_booth/screens/picker_screen.dart';
import 'package:helpbee_booth/screens/report_screen.dart';

import 'test_surface.dart';

/// `BoothApp` 전체를 통으로 돌리는 테스트. 화면 각각은 이미 개별 테스트가 있지만,
/// 그 어떤 테스트도 스테이지 전환 배선(main.dart)을 실제로 밟지 않는다 — 그래서
/// "터치 없이 넘어가는 인트로 → 무동작 타이머가 걸리지 않는다" 버그가 리뷰까지
/// 살아남았다.
///
/// 주의:
/// - `AttractScreen` 이 마운트돼 있는 동안 `pumpAndSettle()` 을 쓰지 않는다 —
///   내부 `Timer.periodic(4s)` 가 절대 끝나지 않아 타임아웃날 때까지 돈다.
///   그래서 이 파일은 전부 `tester.pump(Duration)` 으로 명시적으로 시간을 흘린다.
/// - `BoothApp` 은 `initState` 에서 `assets/cases.json` 을 비동기로 읽는다.
///   `pumpWidget` 한 번만으로는 케이스가 아직 로드되지 않아 `CircularProgressIndicator`
///   상태다. 로드가 언제 끝나는지(실제 몇 번의 마이크로태스크를 도는지)가 실행마다
///   달라 고정된 횟수의 `pump()`로는 불안정하다 — 그렇다고 `pumpAndSettle()`을 쓰면
///   로드 완료 직후 `AttractScreen`이 마운트되며 그 4초 주기 타이머 때문에 절대
///   settle 되지 않는다(위 경고 참조). 그래서 `AttractScreen`이 나타날 때까지
///   짧은 pump를 여러 번 반복하는 쪽으로 기다린다.
Future<void> _waitForCasesLoaded(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byType(AttractScreen).evaluate().isNotEmpty) return;
  }
  fail('assets/cases.json 로드가 끝나지 않았다 (20회 폴링 초과)');
}

void main() {
  // `rootBundle`은 `loadString` 결과를 프로세스 전역으로 캐싱한다(`CachingAssetBundle`).
  // 캐시된 Future는 그걸 만든 테스트의 FakeAsync 존에 묶여 있어서, 다음 테스트의 존에서
  // 재사용하면 완료 콜백이 영영 안 온다 — 그래서 매 테스트 전에 캐시를 비운다.
  setUp(() => rootBundle.clear());

  // 각 테스트가 어트랙트로 돌아오며 남기는 `AttractScreen` 의 4초 주기 타이머를
  // 정리한다 — 위젯 트리를 비워 dispose() 가 타이머를 취소하게 한다.
  Future<void> disposeAll(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('인트로가 터치 없이 자동으로 넘어가도, 그 뒤 60초 무동작이면 어트랙트로 돌아간다 '
      '(회귀 — 예전 코드는 터치에만 타이머를 걸어서 이 경로에서 타이머가 영영 안 걸렸다)', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);
    expect(find.byType(AttractScreen), findsOneWidget);

    // 어트랙트를 터치해 시작한다 — 이 시점엔 `_stage`가 아직 attract 이므로
    // (구) `_touched()` 라면 여기서 타이머가 걸리지 않는다.
    await tester.tap(find.byType(AttractScreen));
    await tester.pump();
    expect(find.byType(IntroScreen), findsOneWidget);

    // 인트로는 3초 뒤 "터치 없이" 자동으로 픽커로 넘어간다.
    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(PickerScreen), findsOneWidget);

    // 여기서부터 관람객이 그냥 가버렸다고 가정 — 아무 터치도 없이 60초+.
    await tester.pump(const Duration(seconds: 65));

    expect(
      find.byType(AttractScreen),
      findsOneWidget,
      reason: '픽커에서 60초 무동작이면 어트랙트로 돌아가야 한다',
    );
    expect(find.byType(PickerScreen), findsNothing);

    await disposeAll(tester);
  });

  testWidgets('처음부터 끝까지 한 바퀴 탭으로 돈다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);
    expect(find.byType(AttractScreen), findsOneWidget);

    await tester.tap(find.byType(AttractScreen));
    await tester.pump();
    expect(find.byType(IntroScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.byType(PickerScreen), findsOneWidget);

    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    expect(find.byType(GuessScreen), findsOneWidget);

    await tester.tap(find.text('건강함'));
    await tester.pump();
    expect(find.byType(AnalyzingScreen), findsOneWidget);

    // 분석 화면은 500ms x 3단계 = 1.5초 뒤 자동으로 넘어간다.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byType(ReportScreen), findsOneWidget);

    await disposeAll(tester);
  });

  testWidgets('뒤쪽 단계(결과 화면)에서도 60초 무동작이면 어트랙트로 돌아간다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);

    await tester.tap(find.byType(AttractScreen));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4)); // intro -> picker

    await tester.tap(find.byType(InkWell).first);
    await tester.pump(); // picker -> guess

    await tester.tap(find.text('건강함'));
    await tester.pump(); // guess -> analyzing

    await tester.pump(
      const Duration(milliseconds: 1600),
    ); // analyzing -> report
    expect(find.byType(ReportScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 61));

    expect(
      find.byType(AttractScreen),
      findsOneWidget,
      reason: '결과 화면에서도 60초 무동작이면 어트랙트로 돌아가야 한다',
    );

    await disposeAll(tester);
  });
}
