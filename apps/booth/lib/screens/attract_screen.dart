import 'dart:async';

import 'package:flutter/material.dart';

import '../data/booth_case.dart';
import '../theme/app_colors.dart';
import '../widgets/bbox_overlay.dart';
import '../widgets/booth_scaffold.dart';
import '../widgets/risk_gauge.dart';
import '../widgets/surfaces.dart';
import '../widgets/tier_badge.dart';

/// 무동작 시 자동 반복 재생되는 유인 화면.
///
/// 목적은 하나다 — 지나가는 사람이 화면 움직임에 멈춰 서게 하는 것. 그래서 정지 화면이
/// 아니라 박스가 하나씩 그려지는 장면을 4초마다 반복한다.
///
/// 이 화면만 **다크 스테이지**다. 밝은 크림 화면 일색인 부스에서 검정 화면 하나가
/// 멀리서 가장 잘 걸린다.
class AttractScreen extends StatefulWidget {
  const AttractScreen({super.key, required this.case_, required this.onStart});

  final BoothCase case_;
  final VoidCallback onStart;

  @override
  State<AttractScreen> createState() => _AttractScreenState();
}

class _AttractScreenState extends State<AttractScreen>
    with SingleTickerProviderStateMixin {
  static const Duration replayEvery = Duration(seconds: 4);

  Timer? _timer;
  int _replay = 0;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(replayEvery, (_) {
      if (mounted) setState(() => _replay++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.case_;
    final t = Theme.of(context).textTheme;

    return BoothScaffold(
      dark: true,
      eyebrow: 'AI 벌통 진단',
      onTap: widget.onStart,
      footer: Center(
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.45, end: 1.0).animate(_pulse),
          child: HoneyChip(
            dark: true,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.touch_app_outlined,
                  color: AppColors.honeyBrand,
                  size: 34,
                ),
                const SizedBox(width: 14),
                Text(
                  '화면을 터치해 시작하세요',
                  style: t.headlineMedium?.copyWith(
                    color: AppColors.honeyBrand,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '사진 한 장으로 벌통을 진단합니다',
            style: t.headlineLarge?.copyWith(color: AppColors.onInk),
          ),
          const SizedBox(height: 6),
          Text(
            '꿀벌 응애 감염을 몇 초 만에',
            style: t.bodyLarge?.copyWith(color: AppColors.onInkSoft),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  // 부스에서는 사진이 주인공이다 — 게이지 컬럼보다 넓게.
                  flex: 7,
                  child: PhotoFrame(
                    dark: true,
                    child: BboxOverlay(
                      // key 가 바뀌면 State 가 새로 생겨 애니메이션이 처음부터 돈다.
                      key: ValueKey(_replay),
                      photoAsset: 'assets/${c.photo}',
                      imageSize: Size(
                        c.imageWidth.toDouble(),
                        c.imageHeight.toDouble(),
                      ),
                      boxes: c.boxes,
                    ),
                  ),
                ),
                const SizedBox(width: 36),
                Expanded(
                  flex: 4,
                  // FittedBox — 게이지 300 + 배지 + 문구는 부스 캔버스(1024 높이)
                  // 에서는 넉넉하지만, 세로가 짧은 캔버스(웹 백업의 브라우저
                  // 창)에서는 61px 넘쳐 잘렸다. scaleDown 은 공간이 있으면
                  // 원래 크기 그대로, 모자라면 비율을 유지한 채 줄인다.
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RiskGauge(
                            score: c.riskScore,
                            tier: c.tier,
                            size: 300,
                            stroke: 24,
                            onDark: true,
                          ),
                          const SizedBox(height: 22),
                          TierBadge(tier: c.tier, scale: 1.15),
                          const SizedBox(height: 18),
                          Text(
                            '${c.varroaCount}마리에게서 응애 감염 의심',
                            textAlign: TextAlign.center,
                            style: t.bodyLarge?.copyWith(
                              color: AppColors.onInkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
