import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/main.dart';
import 'package:helpbee_booth/screens/analyzing_screen.dart';
import 'package:helpbee_booth/screens/attract_screen.dart';
import 'package:helpbee_booth/screens/guess_screen.dart';
import 'package:helpbee_booth/screens/intro_screen.dart';
import 'package:helpbee_booth/screens/outro_screen.dart';
import 'package:helpbee_booth/screens/picker_screen.dart';
import 'package:helpbee_booth/screens/summary_screen.dart';
import 'package:helpbee_booth/screens/tour_start_screen.dart';
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

/// 어트랙트 → 인트로 → 투어 시작 → 1라운드 추측 화면까지.
Future<void> _enterFirstRound(WidgetTester tester) async {
  await tester.tap(find.byType(AttractScreen));
  await tester.pump();
  await tester.pump(const Duration(seconds: 26)); // intro 자동 진행(25초)
  await tester.pump(const Duration(milliseconds: 400)); // 전환 크로스페이드
  expect(find.byType(TourStartScreen), findsOneWidget);
  await tester.tap(find.text('시작하기'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(GuessScreen), findsOneWidget);
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

    await tester.tap(find.byType(AttractScreen));
    await tester.pump();
    expect(find.byType(IntroScreen), findsOneWidget);

    // 인트로는 25초 뒤 "터치 없이" 자동으로 투어 시작 화면으로 넘어간다.
    await tester.pump(const Duration(seconds: 26));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TourStartScreen), findsOneWidget);

    // 여기서부터 관람객이 그냥 가버렸다고 가정 — 아무 터치도 없이 60초+.
    await tester.pump(const Duration(seconds: 65));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(AttractScreen),
      findsOneWidget,
      reason: '투어 시작 화면에서 60초 무동작이면 어트랙트로 돌아가야 한다',
    );

    await disposeAll(tester);
  });

  testWidgets('투어 3라운드를 돌고 요약까지 간다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);
    await _enterFirstRound(tester);

    for (var round = 1; round <= 3; round++) {
      expect(find.byType(GuessScreen), findsOneWidget, reason: 'R$round 추측');
      await tester.tap(find.text('문제 있음'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(AnalyzingScreen),
        findsOneWidget,
        reason: 'R$round 분석',
      );

      // 분석은 1.3초 x 3단계 = 약 4초.
      await tester.pump(const Duration(milliseconds: 4200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ReportScreen), findsOneWidget, reason: 'R$round 결과');

      await tester.tap(find.text(round == 3 ? '결과 보기 →' : '다음 사진 →'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(
      find.byType(SummaryScreen),
      findsOneWidget,
      reason: '3라운드가 끝나면 요약으로 간다',
    );
    await disposeAll(tester);
  });

  testWidgets('요약에서 더 해보기 → 자유 선택 → 마치기 로 마무리까지 간다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);
    await _enterFirstRound(tester);

    for (var round = 1; round <= 3; round++) {
      await tester.tap(find.text('문제 있음'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 4200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(round == 3 ? '결과 보기 →' : '다음 사진 →'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.tap(find.text('더 해보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PickerScreen), findsOneWidget);

    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(GuessScreen), findsOneWidget);

    await tester.tap(find.text('건강함'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 4200));
    await tester.pump(const Duration(milliseconds: 400));

    // 보너스 경로의 결과 화면은 요약이 아니라 마무리로 간다.
    expect(find.text('마치기 →'), findsOneWidget);
    await tester.tap(find.text('마치기 →'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(OutroScreen), findsOneWidget);

    await disposeAll(tester);
  });

  testWidgets('뒤쪽 단계(결과 화면)에서도 60초 무동작이면 어트랙트로 돌아간다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);
    await _enterFirstRound(tester);

    await tester.tap(find.text('건강함'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(
      const Duration(milliseconds: 4200),
    ); // analyzing -> report
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ReportScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byType(AttractScreen),
      findsOneWidget,
      reason: '결과 화면에서도 60초 무동작이면 어트랙트로 돌아가야 한다',
    );

    await disposeAll(tester);
  });

  // 주의: 이 테스트는 버튼을 실제로 `tester.tap()` 한다 — 앱 최상단의
  // `Listener.onPointerDown`(main.dart)이 화면 어디를 탭하든 무동작 타이머를
  // 다시 걸기 때문에, 전환 콜백이 `_goTo()`를 쓰는지 raw `setState`를 쓰는지는
  // **이 테스트로는 구분되지 않는다.** `_goTo()` 누락 자체를 잡는 뮤테이션
  // 가드는 아래 '콜백을 직접 호출해도' 테스트다.
  testWidgets('요약 화면에서도 60초 무동작이면 어트랙트로 돌아간다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);
    await _enterFirstRound(tester);

    for (var round = 1; round <= 3; round++) {
      await tester.tap(find.text('문제 있음'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 4200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(round == 3 ? '결과 보기 →' : '다음 사진 →'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(find.byType(SummaryScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 61));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byType(AttractScreen),
      findsOneWidget,
      reason: '요약 화면에서 관람객이 그냥 가버려도 다음 사람을 위해 초기화돼야 한다',
    );

    await disposeAll(tester);
  });

  testWidgets('요약→자유선택 전환 콜백 자체가 _goTo() 를 거친다 '
      '(뮤테이션 가드 — 위 테스트들은 tester.tap() 이 앱 최상단 Listener 를 거치며 '
      '부수적으로 타이머를 재무장시켜, 콜백 안에서 _goTo() 를 빼먹어도 통과해 버린다. '
      '그래서 여기서는 탭을 보내지 않고 위젯의 콜백을 직접 호출해 그 부수효과를 배제한다.)', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(const BoothApp());
    await _waitForCasesLoaded(tester);
    await _enterFirstRound(tester);

    for (var round = 1; round <= 3; round++) {
      await tester.tap(find.text('문제 있음'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 4200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(round == 3 ? '결과 보기 →' : '다음 사진 →'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    // t=0 에 요약 도착. 59초 흘린 뒤 **탭 없이** 콜백만 호출한다.
    await tester.pump(const Duration(seconds: 59));
    tester.widget<SummaryScreen>(find.byType(SummaryScreen)).onMore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PickerScreen), findsOneWidget);

    // 원래(t=0에 걸린) 타이머만 남아 있었다면 t=60 에 이미 터졌어야 한다.
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byType(PickerScreen),
      findsOneWidget,
      reason:
          'summary→picker 전환이 _goTo() 를 거쳐 타이머를 다시 걸었다면 '
          't=61 에는 아직 리셋되면 안 된다',
    );

    await disposeAll(tester);
  });
}
