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

  /// 안내 칩의 맥박. **계속 돌리지 않는다.**
  ///
  /// 예전에는 `repeat(reverse: true)` 로 하루 종일 60fps 프레임을 요구했다.
  /// 어트랙트는 관람객이 없는 대부분의 시간을 차지하는 화면이라, 이게 부스
  /// 배터리를 가장 많이 먹는 단일 원인이었다. 이제 4초 주기마다 1.2초만
  /// 뛰고 멈춘다 — 나머지 2.8초는 **프레임을 아예 요청하지 않는다.**
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  /// 0.45 → 1.0 → 0.45 한 번 뛰고 끝난다.
  late final Animation<double> _pulseOpacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.45, end: 1.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.45), weight: 1),
  ]).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _beat();
    _timer = Timer.periodic(replayEvery, (_) => _beat());
  }

  /// 한 주기: 박스를 다시 그리고, 칩을 한 번 뛰게 한다.
  void _beat() {
    if (!mounted) return;
    setState(() => _replay++);
    _pulse.forward(from: 0);
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
          opacity: _pulseOpacity,
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
                    // 액자가 컬럼 높이만큼 늘어나면 히어로 사진이 가운데
                    // 조그맣게 뜬다 — 부스에서 사진이 주인공인데 공간을
                    // 절반 넘게 버리게 된다 (2026-08-31 아이패드 실측).
                    aspectRatio: c.imageWidth / c.imageHeight,
                    child: BboxOverlay(
                      // 위젯을 다시 만들지 않고 프로퍼티로 재생만 시킨다 —
                      // key 를 바꾸면 State·컨트롤러·이미지가 매번 새로 생긴다.
                      replay: _replay,
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
                    // RepaintBoundary — 게이지의 MaskFilter.blur 는 이 화면에서
                    // 가장 비싼 페인트다. 한 번 래스터화해두고 재사용한다.
                    child: RepaintBoundary(
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
