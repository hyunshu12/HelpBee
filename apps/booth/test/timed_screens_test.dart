import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/screens/intro_screen.dart';
import 'package:helpbee_booth/screens/outro_screen.dart';

import 'test_surface.dart';

void main() {
  // 2026-08-31: 3초 -> 25초. 3초는 클로즈업 사진에 초점을 맞추기도 전에 넘어가
  // 정작 이 부스에서 제일 중요한 "응애가 뭔지"가 전달되지 않았다.
  testWidgets('인트로는 25초 뒤 자동 진행한다', (tester) async {
    await useBoothSurface(tester);
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IntroScreen(onDone: () => done = true)),
      ),
    );
    await tester.pump(const Duration(seconds: 24));
    expect(done, isFalse, reason: '24초에는 아직 넘어가면 안 된다');
    await tester.pump(const Duration(seconds: 2));
    expect(done, isTrue);
  });

  // 25초 정지 화면은 "멈춘 화면"으로 오해받는다. 사실 세 줄이 순차로 나타나며
  // 화면이 살아 있음을 보여주는 것이 25초로 늘린 결정의 전제다.
  testWidgets('인트로의 사실 줄은 처음엔 숨어 있다가 시간이 지나며 드러난다', (tester) async {
    await useBoothSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IntroScreen(onDone: () {})),
      ),
    );

    double opacityOf(String text) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.text(text),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    for (final fact in _IntroFacts.all) {
      expect(opacityOf(fact), 0, reason: '0초에는 "$fact" 가 보이면 안 된다');
    }

    // 1.2초 / 3.2초 / 5.2초에 한 줄씩. 셋 다 6초 안에 나와야 한다 —
    // 관람객 체류 시간이 30초~1분이라, 마지막 줄을 10초 넘게 기다리게 하면
    // 그 전에 화면을 떠난다.
    await tester.pump(const Duration(seconds: 2));
    expect(opacityOf(_IntroFacts.all[0]), 1);
    expect(opacityOf(_IntroFacts.all[1]), 0);

    await tester.pump(const Duration(seconds: 2));
    expect(opacityOf(_IntroFacts.all[1]), 1);
    expect(opacityOf(_IntroFacts.all[2]), 0);

    await tester.pump(const Duration(seconds: 2));
    expect(opacityOf(_IntroFacts.all[2]), 1, reason: '6초 안에 사실 3줄이 모두 나와야 한다');

    await tester.pump(const Duration(seconds: 20)); // 타이머 정리
  });

  testWidgets('인트로는 터치하면 즉시 넘어간다', (tester) async {
    await useBoothSurface(tester);
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IntroScreen(onDone: () => done = true)),
      ),
    );
    await tester.tap(find.byType(IntroScreen));
    expect(done, isTrue);
    await tester.pump(const Duration(seconds: 26)); // 타이머 정리
  });

  testWidgets('마무리는 15초 뒤 초기화한다', (tester) async {
    await useBoothSurface(tester);
    var reset = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OutroScreen(onRestart: () => reset = true)),
      ),
    );
    await tester.pump(const Duration(seconds: 14));
    expect(reset, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(reset, isTrue);
  });
}

/// [IntroScreen.facts] 를 테스트에서 참조하기 위한 별칭. 문구가 바뀌어도
/// 테스트가 조용히 통과하지 않도록 화면의 상수를 그대로 읽는다.
abstract final class _IntroFacts {
  static List<String> get all => IntroScreen.facts;
}
