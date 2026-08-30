import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../widgets/booth_scaffold.dart';
import '../widgets/surfaces.dart';

/// "응애가 뭐죠?" — 관람객 대부분이 모르는 것을 먼저 알려준다.
///
/// 2026-08-31: 자동 진행을 3초 → **25초**로 늘렸다. 3초는 클로즈업 사진에
/// 초점을 맞추기도 전에 넘어가는 시간이라, 정작 이 부스에서 제일 중요한
/// "응애가 뭔지"가 전달되지 않았다. 다만 25초짜리 **정지 화면**은 지루하므로
/// 사실 한 줄씩 순차로 나타나게 하고, 남은 시간을 진행 막대로 보여준다
/// (멈춘 게 아니라는 신호). 터치하면 언제든 즉시 넘어간다.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  /// 사실 한 줄씩. 전부 검증 가능한 서술만 쓴다 — 부스에서 과장하면
  /// 관람객이 되묻는 순간 답할 수 없다.
  static const List<String> facts = [
    '다 자라도 2mm 남짓 — 벌 몸에 붙어 체액을 빨아먹습니다',
    '바이러스까지 옮겨서, 그대로 두면 벌통 전체가 무너집니다',
    '그런데 사진 속에서 찾아내기가 정말 어렵습니다',
  ];

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  static const Duration autoAdvance = Duration(seconds: 25);

  /// 각 줄이 나타나는 시점(전체 25초 대비 비율) = 3초 · 8초 · 13초.
  static const List<double> _factAt = [0.12, 0.32, 0.52];

  /// 마무리 한 줄(18초).
  static const double _punchAt = 0.72;

  /// 진행 막대 + 순차 등장을 함께 구동하는 **단일** 시간 소스.
  /// 타이머와 애니메이션을 따로 두면 둘이 어긋나 진행 막대가 다 찼는데
  /// 화면이 안 넘어가는(혹은 그 반대) 상태가 생긴다.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: autoAdvance,
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) widget.onDone();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return BoothScaffold(
      eyebrow: '먼저, 응애가 뭘까요?',
      onTap: widget.onDone,
      footer: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                child: LinearProgressIndicator(
                  value: _c.value,
                  minHeight: 8,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation(
                    AppColors.honeyPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Text(
              '탭하면 바로 넘어갑니다',
              style: t.bodyMedium?.copyWith(color: AppColors.hintBorder),
            ),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 5,
            child: PhotoFrame(
              child: Image.asset(
                'assets/varroa_closeup.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            flex: 6,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('꿀벌에 붙은 이 진드기가\n벌통을 무너뜨립니다', style: t.headlineLarge),
                  const SizedBox(height: 8),
                  Text(
                    '바로아 응애 (Varroa destructor)',
                    style: t.bodyMedium?.copyWith(
                      color: AppColors.amberDeep,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 28),
                  for (var i = 0; i < IntroScreen.facts.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _Reveal(
                        shown: _c.value >= _factAt[i],
                        child: _FactRow(text: IntroScreen.facts[i]),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _Reveal(
                    shown: _c.value >= _punchAt,
                    child: HoneyChip(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      child: Text(
                        '그래서 HelpBee가 대신 찾아냅니다',
                        style: t.titleMedium?.copyWith(
                          color: AppColors.amberDeep,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 아래에서 살짝 올라오며 나타난다. 순간적으로 튀어나오면 시선이 놀라고,
/// 페이드만 주면 변화를 눈치채지 못한다.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.shown, required this.child});

  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSlide(
    offset: shown ? Offset.zero : const Offset(0, 0.25),
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOut,
    child: AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: const Duration(milliseconds: 420),
      child: child,
    ),
  );
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        margin: const EdgeInsets.only(top: 10),
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          color: AppColors.honeyPrimary,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
    ],
  );
}
