import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/main.dart';
import 'package:helpbee_booth/screens/analyzing_screen.dart';
import 'package:helpbee_booth/screens/attract_screen.dart';
import 'package:helpbee_booth/screens/guess_screen.dart';
import 'package:helpbee_booth/screens/history_screen.dart';
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

    // 인트로는 25초 뒤 "터치 없이" 자동으로 픽커로 넘어간다.
    await tester.pump(const Duration(seconds: 26));
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

    await tester.pump(const Duration(seconds: 26));
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
    await tester.pump(const Duration(seconds: 26)); // intro -> picker

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

  // 주의: 이 테스트는 버튼을 실제로 `tester.tap()` 한다 — 앱 최상단의
  // `Listener.onPointerDown`(main.dart)이 화면 어디를 탭하든 무동작 타이머를
  // 다시 걸기 때문에, report→history/history→report 전환 콜백 자체가
  // `_goTo()`를 쓰는지 raw `setState`를 쓰는지는 **이 테스트로는 구분되지
  // 않는다** — 탭이라는 동작 자체가 이미 타이머를 재무장시켜 버린다. 그래서
  // 이 테스트는 "기록 화면을 오가는 실제 사용자 흐름이 배선대로 동작하고,
  // 그 뒤에도 결국 무동작 리셋이 살아있다"는 걸 검증하는 e2e 흐름 테스트다.
  // `_goTo()` 누락 자체를 잡는 진짜 뮤테이션 가드는 아래
  // '콜백을 직접 호출해도' 테스트 쪽이다(탭 이벤트를 보내지 않아 이 부수효과를
  // 배제한다).
  testWidgets('기록 보기로 들어갔다 돌아온 뒤에도 60초 무동작이면 어트랙트로 돌아간다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);

    await tester.tap(find.byType(AttractScreen));
    await tester.pump();
    await tester.pump(const Duration(seconds: 26)); // intro -> picker

    await tester.tap(find.byType(InkWell).first);
    await tester.pump(); // picker -> guess

    await tester.tap(find.text('건강함'));
    await tester.pump(); // guess -> analyzing

    await tester.pump(
      const Duration(milliseconds: 1600),
    ); // analyzing -> report
    expect(find.byType(ReportScreen), findsOneWidget);

    await tester.tap(find.text('기록 보기'));
    await tester.pump();
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.byType(ReportScreen), findsNothing);

    await tester.tap(find.text('돌아가기'));
    await tester.pump();
    expect(find.byType(ReportScreen), findsOneWidget);
    expect(find.byType(HistoryScreen), findsNothing);

    // 기록 화면을 보고 결과 화면으로 돌아온 뒤 아무 터치도 없이 60초+ 지났다고
    // 가정한다.
    await tester.pump(const Duration(seconds: 61));

    expect(
      find.byType(AttractScreen),
      findsOneWidget,
      reason: '기록 화면을 오간 뒤에도 60초 무동작이면 어트랙트로 돌아가야 한다',
    );

    await disposeAll(tester);
  });

  testWidgets('report→history, history→report 전환 콜백 자체가 _goTo() 를 거친다 '
      '(뮤테이션 가드 — 위 테스트는 tester.tap() 이 앱 최상단 Listener.onPointerDown 을 '
      '거치면서 부수적으로 타이머를 재무장시켜, 콜백 안에서 _goTo() 를 빼먹어도 통과해 버린다. '
      '그래서 여기서는 탭을 보내지 않고 위젯의 콜백을 직접 호출해 그 부수효과를 배제한다.)', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);

    await tester.tap(find.byType(AttractScreen));
    await tester.pump();
    await tester.pump(const Duration(seconds: 26)); // intro -> picker

    await tester.tap(find.byType(InkWell).first);
    await tester.pump(); // picker -> guess

    await tester.tap(find.text('건강함'));
    await tester.pump(); // guess -> analyzing

    // analyzing -> report 는 터치 없이 내부 타이머로 자동 전환된다(이 파일이
    // 건드리지 않는 기존 _goTo 경로). 이 순간 무동작 타이머가 60초로 걸린다 —
    // 이후 시간 계산은 전부 이 시점(t=0)을 기준으로 한다.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byType(ReportScreen), findsOneWidget);

    // t=59. 아직 리셋 전 — 원래 타이머(t=60에 만료)가 거의 다 됐을 때까지
    // 기다린다.
    await tester.pump(const Duration(seconds: 59));
    expect(find.byType(ReportScreen), findsOneWidget);

    // 탭이 아니라 콜백을 직접 부른다 — report→history 전환에서 `_goTo()`를
    // 썼다면 지금(t=59) 타이머가 다시 60초(→t=119)로 걸린다.
    tester.widget<ReportScreen>(find.byType(ReportScreen)).onHistory!();
    await tester.pump();
    expect(find.byType(HistoryScreen), findsOneWidget);

    // t=61. 원래(t=0에 걸린) 타이머만 남아 있었다면 t=60에 이미 터졌어야
    // 한다 — 여기서 여전히 HistoryScreen 이면 `_goTo()`가 실제로 재무장한
    // 것이다.
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byType(HistoryScreen),
      findsOneWidget,
      reason:
          'report→history 전환이 _goTo() 를 거쳐 타이머를 다시 걸었다면 '
          't=61 에는 아직 리셋되면 안 된다',
    );

    // 기록 화면 진입(t=59) 이후 다시 59초 경과 → 상대 시각 t=118.
    await tester.pump(const Duration(seconds: 57));
    expect(find.byType(HistoryScreen), findsOneWidget);

    // 같은 방식으로 history→report 도 콜백을 직접 불러 검증한다.
    tester.widget<HistoryScreen>(find.byType(HistoryScreen)).onBack();
    await tester.pump();
    expect(find.byType(ReportScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byType(ReportScreen),
      findsOneWidget,
      reason:
          'history→report 전환이 _goTo() 를 거쳐 타이머를 다시 걸었다면 '
          '여기서도 아직 리셋되면 안 된다',
    );

    await disposeAll(tester);
  });

  testWidgets('픽커 카드 순서가 매 세션(리셋)마다 섞인다 '
      '(스펙 §3 [2] "매 세션 순서 셔플" — 회귀: 셔플이 빠지면 danger-100 이 항상 '
      '첫 카드로 나와 나머지 세 장은 거의 선택되지 않는다)', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);

    String firstCardId() =>
        tester.widget<PickerScreen>(find.byType(PickerScreen)).cases.first.id;

    Future<void> enterPicker() async {
      await tester.tap(find.byType(AttractScreen));
      await tester.pump();
      await tester.pump(const Duration(seconds: 26)); // intro -> picker
      expect(find.byType(PickerScreen), findsOneWidget);
    }

    await enterPicker();
    final firstIds = <String>{firstCardId()};

    // 카드 4장을 섞으면 "직전과 같은 첫 카드"가 다시 나올 확률이 1/4이다 —
    // 그래서 "리셋 두 번이면 서로 달라야 한다"는 단순 비교는 그 자체로 약
    // 25% 확률로 깨지는 flaky assertion이 된다. 대신 서로 다른 첫 카드를
    // 2개 이상 관찰할 때까지 최대 maxAttempts 번 반복한다. 셔플이 실제로
    // 동작한다면 모든 시도에서 첫 카드가 계속 같을 확률은
    // (1/4)^(maxAttempts-1) 로, 20회 기준 약 10^-12 — 사실상 0에 수렴해
    // 이 테스트는 실질적으로 결정론적이다.
    const maxAttempts = 20;
    for (var i = 0; i < maxAttempts && firstIds.length < 2; i++) {
      // 60초 무동작 → attract 복귀. _resetSession() 이 다음 관람객을 위해
      // 다시 섞는다.
      await tester.pump(const Duration(seconds: 65));
      expect(find.byType(AttractScreen), findsOneWidget);
      await enterPicker();
      firstIds.add(firstCardId());
    }

    expect(
      firstIds.length,
      greaterThan(1),
      reason:
          '$maxAttempts번 리셋했는데도 픽커 첫 카드가 항상 같다 — 셔플이 '
          '빠졌거나 매 세션 재적용되지 않는 회귀',
    );

    await disposeAll(tester);
  });
}
