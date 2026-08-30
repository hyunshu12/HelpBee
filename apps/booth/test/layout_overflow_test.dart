import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/data/booth_case.dart';
import 'package:helpbee_booth/data/booth_session.dart';
import 'package:helpbee_booth/data/risk_tier.dart';
import 'package:helpbee_booth/screens/analyzing_screen.dart';
import 'package:helpbee_booth/screens/attract_screen.dart';
import 'package:helpbee_booth/screens/guess_screen.dart';
import 'package:helpbee_booth/screens/history_screen.dart';
import 'package:helpbee_booth/screens/intro_screen.dart';
import 'package:helpbee_booth/screens/outro_screen.dart';
import 'package:helpbee_booth/screens/picker_screen.dart';
import 'package:helpbee_booth/screens/report_screen.dart';
import 'package:helpbee_booth/theme/app_theme.dart';

import 'test_surface.dart';

/// 화면 8개 × 캔버스 2종 오버플로 스윕.
///
/// 왜 필요한가: 부스 앱은 **고정 캔버스**를 전제로 짜여 있어서, 한 화면의
/// 여백을 조금만 키워도 다른 화면이 조용히 잘린다. 실제로 2026-08-31 재디자인
/// 중 사진 고르기 화면의 아래 두 카드가 통째로 잘려 **누를 수 없는** 상태로
/// 웹 빌드까지 나갔다(고정 childAspectRatio). 화면마다 테스트를 따로 쓰면
/// 새 화면이 추가될 때 빠지므로 여기서 한 번에 쓸어 본다.
///
/// 짧은 캔버스(1280x720)를 함께 도는 이유: 웹 백업은 브라우저 크롬 때문에
/// 아이패드보다 세로가 짧고, 기기별 세이프에어리어도 다르다.
const _surfaces = [kBoothSurface, Size(1280, 720)];

BoothCase _case({RiskTier tier = RiskTier.danger, int recs = 5}) => BoothCase(
  id: 'danger-100',
  photo: 'photos/danger-100.jpg',
  imageWidth: 1920,
  imageHeight: 1080,
  riskScore: 100,
  tier: tier,
  beeTotal: 14,
  varroaCount: 2,
  // 최악 케이스(위험 티어 처방 5줄)로 돈다 — 가장 길어지는 조합.
  recommendations: [
    for (var i = 0; i < recs; i++) '처방 문구 $i 입니다. 조금 긴 문장으로 둡니다.',
  ],
  boxes: const [
    BoothBox(x: 100, y: 100, w: 400, h: 300, cls: 'varroa'),
    BoothBox(x: 600, y: 200, w: 300, h: 250, cls: 'normal'),
  ],
);

void main() {
  final screens = <String, Widget Function()>{
    '어트랙트': () => AttractScreen(case_: _case(), onStart: () {}),
    '인트로': () => IntroScreen(onDone: () {}),
    '사진 고르기': () => PickerScreen(
      cases: [for (var i = 0; i < 4; i++) _case()],
      onPick: (_) {},
    ),
    '추측': () => GuessScreen(case_: _case(), onAnswer: (_) {}),
    '분석중': () => AnalyzingScreen(case_: _case(), onDone: () {}),
    '결과(추측 있음)': () => ReportScreen(
      case_: _case(),
      guess: false,
      onRestart: () {},
      onHistory: () {},
      onFinish: () {},
    ),
    '결과(추측 없음)': () =>
        ReportScreen(case_: _case(), guess: null, onRestart: () {}),
    '기록': () =>
        HistoryScreen(session: BoothSession()..record(_case()), onBack: () {}),
    '마무리': () => OutroScreen(onRestart: () {}),
  };

  for (final surface in _surfaces) {
    for (final entry in screens.entries) {
      testWidgets(
        '${entry.key} — ${surface.width.toInt()}x${surface.height.toInt()} 넘침 없음',
        (tester) async {
          await tester.binding.setSurfaceSize(surface);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            MaterialApp(
              theme: boothTheme(),
              home: Scaffold(body: entry.value()),
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));

          expect(
            tester.takeException(),
            isNull,
            reason:
                '${entry.key} 가 ${surface.width.toInt()}x${surface.height.toInt()} 에서 넘친다',
          );

          // 타이머/애니메이션이 도는 화면들을 정리한다.
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
