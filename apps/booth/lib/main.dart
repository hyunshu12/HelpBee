import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/booth_case.dart';
import 'data/booth_session.dart';
import 'data/case_loader.dart';
import 'data/operator_gesture.dart';
import 'screens/analyzing_screen.dart';
import 'screens/attract_screen.dart';
import 'screens/guess_screen.dart';
import 'screens/intro_screen.dart';
import 'screens/outro_screen.dart';
import 'screens/picker_screen.dart';
import 'screens/report_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 부스 거치대는 가로다. 세로로 돌아가면 레이아웃이 깨진다.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const BoothApp());
}

/// history 는 Task 7 에서 추가한다 (HistoryScreen 이 아직 없다).
enum BoothStage { attract, intro, picker, guess, analyzing, report, outro }

class BoothApp extends StatefulWidget {
  const BoothApp({super.key});

  @override
  State<BoothApp> createState() => _BoothAppState();
}

class _BoothAppState extends State<BoothApp> {
  final BoothSession _session = BoothSession();
  final OperatorGesture _operator = OperatorGesture();
  BoothStage _stage = BoothStage.attract;
  List<BoothCase> _cases = const [];
  BoothCase? _picked;
  bool? _guess;
  Timer? _idle;

  static const Duration _idleTimeout = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    loadBoothCases(rootBundle).then((cs) {
      if (mounted) setState(() => _cases = cs);
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    _session.dispose();
    super.dispose();
  }

  /// 무동작 타이머를 새로 건다. 터치뿐 아니라 **화면이 바뀔 때마다** 다시 건다 —
  /// 인트로처럼 터치 없이 자동으로 넘어가는 구간이 있어서, 터치에만 의존하면
  /// 타이머가 한 번도 걸리지 않는 경로가 생긴다(관람객이 사진 선택 화면에서 그냥
  /// 떠나면 부스가 그대로 멈춘다).
  void _armIdle() {
    _idle?.cancel();
    if (_stage == BoothStage.attract) return; // 어트랙트가 이미 초기 상태다
    _idle = Timer(_idleTimeout, _resetSession);
  }

  /// 스테이지 전환의 단일 통로. 여기를 거치지 않는 전환을 만들지 말 것 —
  /// 그 경로만 타이머가 빠진다.
  void _goTo(BoothStage next) {
    setState(() => _stage = next);
    _armIdle();
  }

  void _resetSession() {
    _idle?.cancel();
    _session.reset();
    setState(() {
      _stage = BoothStage.attract;
      _picked = null;
      _guess = null;
    });
  }

  void _operatorTap() {
    if (_operator.tap(DateTime.now())) _resetSession();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: boothTheme(),
      home: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _armIdle(),
        child: Stack(
          children: [
            Scaffold(body: _buildStage()),
            Positioned(
              left: 0,
              top: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _operatorTap,
                child: const SizedBox(width: 60, height: 60),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStage() {
    if (_cases.isEmpty) return const Center(child: CircularProgressIndicator());
    switch (_stage) {
      case BoothStage.attract:
        return AttractScreen(
          // 히어로는 danger-100 — 응애 박스가 2개라 애니메이션이 가장 강하다.
          case_: _cases.firstWhere(
            (c) => c.id == 'danger-100',
            orElse: () => _cases.first,
          ),
          onStart: () => _goTo(BoothStage.intro),
        );
      case BoothStage.intro:
        return IntroScreen(onDone: () => _goTo(BoothStage.picker));
      case BoothStage.picker:
        return PickerScreen(
          cases: _cases,
          onPick: (c) {
            _picked = c;
            _guess = null;
            _goTo(BoothStage.guess);
          },
        );
      case BoothStage.guess:
        return GuessScreen(
          case_: _picked!,
          onAnswer: (g) {
            _guess = g;
            _goTo(BoothStage.analyzing);
          },
        );
      case BoothStage.analyzing:
        return AnalyzingScreen(
          case_: _picked!,
          onDone: () {
            _session.record(_picked!);
            _goTo(BoothStage.report);
          },
        );
      case BoothStage.report:
        return ReportScreen(
          // 케이스마다 새 State 로 마운트한다 — 앞 관람객이 처방을 펼쳐두거나
          // 스크롤을 내려둔 상태가 다음 사람에게 남지 않게.
          key: ValueKey(_picked!.id),
          case_: _picked!,
          guess: _guess,
          onRestart: () => _goTo(BoothStage.picker),
          // onHistory 는 Task 7 에서 연결한다 (HistoryScreen 이 아직 없다).
          onFinish: () => _goTo(BoothStage.outro),
        );
      case BoothStage.outro:
        return OutroScreen(onRestart: _resetSession);
    }
  }
}
