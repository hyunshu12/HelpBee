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
import 'screens/history_screen.dart';
import 'screens/intro_screen.dart';
import 'screens/outro_screen.dart';
import 'screens/picker_screen.dart';
import 'screens/report_screen.dart';
import 'theme/app_colors.dart';
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

enum BoothStage {
  attract,
  intro,
  picker,
  guess,
  analyzing,
  report,
  outro,
  history,
}

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

  /// cases.json 로드 실패 원인. null 이면 로딩 중이거나 성공한 것.
  Object? _loadError;

  static const Duration _idleTimeout = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    loadBoothCases(rootBundle)
        .then((cs) {
          // 매 세션 카드 순서를 섞는다(설계 §3 [2]) — 여기서 한 번, 그리고
          // _resetSession() 에서 다음 관람객을 위해 다시. build() 안에서 섞으면
          // 리빌드마다 순서가 바뀌어 관람객이 겨눈 카드와 실제로 탭되는 카드가
          // 달라질 수 있어 절대 금지.
          if (mounted) setState(() => _cases = List.of(cs)..shuffle());
        })
        .catchError((Object e) {
          // 에셋이 없거나 cases.json 이 깨졌으면 스피너가 영원히 돈다 — 무동작
          // 타이머는 attract 단계에서 걸리지 않고(_armIdle 참조), 운영자 5탭
          // 제스처도 _cases 가 비어 있는 한 화면에 아무 변화가 없어 "느리게
          // 로딩 중"과 "완전히 죽음"을 구분할 수 없다. 최소한 사람이 읽고
          // 사진 찍어 보고할 수 있는 문구를 띄운다.
          if (mounted) setState(() => _loadError = e);
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
      // 다음 관람객을 위해 다시 섞는다 — 안 그러면 이전 순서가 그대로 남아
      // 사실상 세션 하나짜리 셔플이 된다.
      _cases = List.of(_cases)..shuffle();
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
    if (_loadError != null) return _LoadErrorView(error: _loadError!);
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
          onHistory: () => _goTo(BoothStage.history),
          onFinish: () => _goTo(BoothStage.outro),
        );
      case BoothStage.outro:
        return OutroScreen(onRestart: _resetSession);
      case BoothStage.history:
        return HistoryScreen(
          session: _session,
          onBack: () => _goTo(BoothStage.report),
        );
    }
  }
}

/// Break-glass 화면 — 디자인 대상이 아니다. cases.json 로드가 실패했을 때만
/// 뜬다. 운영자가 읽고 사진 찍어 보고할 수 있으면 그걸로 충분하다.
class _LoadErrorView extends StatelessWidget {
  const _LoadErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '체험 데이터를 불러오지 못했습니다. 운영자에게 알려주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
