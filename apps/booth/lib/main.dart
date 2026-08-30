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
    loadBoothCases(rootBundle).then((cs) => setState(() => _cases = cs));
  }

  @override
  void dispose() {
    _idle?.cancel();
    _session.dispose();
    super.dispose();
  }

  /// 관람객이 그냥 가버려도 다음 사람에게 깨끗한 첫 화면이 보이게 한다.
  void _touched() {
    _idle?.cancel();
    if (_stage == BoothStage.attract) return;
    _idle = Timer(_idleTimeout, _resetSession);
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
        onPointerDown: (_) => _touched(),
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
          onStart: () => setState(() => _stage = BoothStage.intro),
        );
      case BoothStage.intro:
        return IntroScreen(
          onDone: () => setState(() => _stage = BoothStage.picker),
        );
      case BoothStage.picker:
        return PickerScreen(
          cases: _cases,
          onPick: (c) => setState(() {
            _picked = c;
            _guess = null;
            _stage = BoothStage.guess;
          }),
        );
      case BoothStage.guess:
        return GuessScreen(
          case_: _picked!,
          onAnswer: (g) => setState(() {
            _guess = g;
            _stage = BoothStage.analyzing;
          }),
        );
      case BoothStage.analyzing:
        return AnalyzingScreen(
          case_: _picked!,
          onDone: () {
            _session.record(_picked!);
            setState(() => _stage = BoothStage.report);
          },
        );
      case BoothStage.report:
        return ReportScreen(
          // 케이스마다 새 State 로 마운트한다 — 앞 관람객이 처방을 펼쳐두거나
          // 스크롤을 내려둔 상태가 다음 사람에게 남지 않게.
          key: ValueKey(_picked!.id),
          case_: _picked!,
          guess: _guess,
          onRestart: () => setState(() => _stage = BoothStage.picker),
          // onHistory 는 Task 7 에서 연결한다 (HistoryScreen 이 아직 없다).
          onFinish: () => setState(() => _stage = BoothStage.outro),
        );
      case BoothStage.outro:
        return OutroScreen(onRestart: _resetSession);
    }
  }
}
