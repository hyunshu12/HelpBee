import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../widgets/booth_scaffold.dart';

/// 마무리 화면. 동아리 홈페이지 QR 을 크게 띄우고 15초 뒤 세션을 초기화한다.
/// 관람객이 폰을 꺼내 찍을 시간을 주되, 다음 사람을 오래 기다리게 하지 않는 길이다.
///
/// QR 은 **반드시 흰 바탕 위**에 둔다 — 다크 스테이지에 그대로 얹으면 대비가
/// 반전돼 상당수 카메라 앱이 인식하지 못한다.
class OutroScreen extends StatefulWidget {
  const OutroScreen({super.key, required this.onRestart});

  final VoidCallback onRestart;

  @override
  State<OutroScreen> createState() => _OutroScreenState();
}

class _OutroScreenState extends State<OutroScreen>
    with SingleTickerProviderStateMixin {
  static const Duration autoReset = Duration(seconds: 15);

  /// 남은 시간 표시 + 자동 초기화를 함께 구동하는 단일 시간 소스
  /// ([IntroScreen] 과 같은 방식).
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: autoReset,
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) widget.onRestart();
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
      dark: true,
      eyebrow: '체험 완료',
      footer: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: LinearProgressIndicator(
            value: _c.value,
            minHeight: 6,
            backgroundColor: AppColors.boothInkLine,
            valueColor: const AlwaysStoppedAnimation(AppColors.honeyBrand),
          ),
        ),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '체험해 주셔서\n감사합니다',
                    style: t.displayMedium?.copyWith(color: AppColors.onInk),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'QR 을 찍으면 저희 팀 홈페이지로 갑니다',
                    style: t.bodyLarge?.copyWith(color: AppColors.onInkSoft),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: widget.onRestart,
                    icon: const Icon(Icons.refresh_rounded, size: 28),
                    label: const Text('처음으로'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(260, 72),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 64),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppRadius.cardRadius,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33FFD869),
                    blurRadius: 60,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: SizedBox(
                width: 300,
                height: 300,
                child: Image.asset('assets/qr_mrmr.png', fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
