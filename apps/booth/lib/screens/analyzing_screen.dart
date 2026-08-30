import 'dart:async';

import 'package:flutter/material.dart';

import '../data/booth_case.dart';
import '../theme/app_colors.dart';
import '../widgets/booth_scaffold.dart';
import '../widgets/surfaces.dart';

/// 실제 추론은 없다. 곧바로 결과를 띄우면 관람객이 "분석한 게 맞나?" 하므로
/// 1.5초 동안 파이프라인 단계를 보여준다. 문구는 실제 동작 순서를 그대로 쓴다.
///
/// 단계를 **한 줄씩 갈아끼우지 않고 세 줄을 모두 그린 뒤** 완료/진행/대기로
/// 상태만 바꾼다 — 한 줄만 보이면 "무엇을 하는 중인지"는 알아도 "전체가 몇
/// 단계인지"를 알 수 없어 기다림이 길게 느껴진다.
class AnalyzingScreen extends StatefulWidget {
  const AnalyzingScreen({super.key, required this.case_, required this.onDone});

  final BoothCase case_;
  final VoidCallback onDone;

  @override
  State<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends State<AnalyzingScreen>
    with SingleTickerProviderStateMixin {
  /// 파이프라인 단계 문구. `{beeTotal}` 은 build 시 실제 마리 수로 치환된다.
  /// 타이머의 완료 임계값(initState)이 이 목록의 길이를 그대로 참조하므로,
  /// 단계를 추가/삭제해도 리터럴 상수를 따로 맞출 필요가 없다.
  static const _stepTemplates = ['사진을 읽는 중', '{beeTotal}마리 탐지', '감염 개체 판별 중'];

  Timer? _timer;
  int _step = 0;

  /// 사진 위를 훑는 스캔 바. "지금 이 사진을 보고 있다"를 눈에 보이게 한다.
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) return;
      setState(() => _step = t.tick);
      if (t.tick >= _stepTemplates.length) {
        t.cancel();
        widget.onDone();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final steps = [
      for (final template in _stepTemplates)
        template.replaceAll('{beeTotal}', '벌 ${widget.case_.beeTotal}'),
    ];

    return BoothScaffold(
      eyebrow: '3단계 · AI 분석',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: PhotoFrame(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/${widget.case_.photo}',
                    fit: BoxFit.cover,
                  ),
                  AnimatedBuilder(
                    animation: _scan,
                    builder: (context, _) => CustomPaint(
                      painter: _ScanPainter(progress: _scan.value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            flex: 5,
            child: Center(
              child: BoothCard(
                padding: const EdgeInsets.all(36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('분석하고 있어요', style: t.headlineMedium),
                    const SizedBox(height: 24),
                    for (var i = 0; i < steps.length; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: i == steps.length - 1 ? 0 : 20,
                        ),
                        child: _StepRow(
                          label: steps[i],
                          // _step 은 타이머 tick(1부터). i < _step 이면 끝난 단계.
                          done: i < _step,
                          active: i == _step,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color color = done
        ? AppColors.tierSafe
        : active
        ? AppColors.textPrimary
        : AppColors.hintBorder;

    return Row(
      children: [
        SizedBox(
          width: 38,
          height: 38,
          child: done
              ? const _Bullet(
                  fill: AppColors.tierSafe,
                  child: Icon(
                    Icons.check_rounded,
                    size: 24,
                    color: AppColors.surface,
                  ),
                )
              : active
              ? const Padding(
                  padding: EdgeInsets.all(4),
                  child: CircularProgressIndicator(strokeWidth: 4),
                )
              : const _Bullet(fill: AppColors.divider),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 24,
              height: 1.3,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.fill, this.child});

  final Color fill;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
    child: child,
  );
}

/// 위에서 아래로 훑는 꿀색 띠 + 진행선.
class _ScanPainter extends CustomPainter {
  _ScanPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    const band = 120.0;
    canvas.drawRect(
      Rect.fromLTWH(0, y - band, size.width, band),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFD869), Color(0x59FFD869)],
        ).createShader(Rect.fromLTWH(0, y - band, size.width, band)),
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = AppColors.honeyPrimary
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.progress != progress;
}
