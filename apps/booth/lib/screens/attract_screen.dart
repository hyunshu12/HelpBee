import 'dart:async';

import 'package:flutter/material.dart';

import '../data/booth_case.dart';
import '../data/risk_tier.dart';
import '../widgets/bbox_overlay.dart';
import '../widgets/risk_gauge.dart';

/// 무동작 시 자동 반복 재생되는 유인 화면.
///
/// 목적은 하나다 — 지나가는 사람이 화면 움직임에 멈춰 서게 하는 것. 그래서 정지 화면이
/// 아니라 박스가 하나씩 그려지는 장면을 4초마다 반복한다.
class AttractScreen extends StatefulWidget {
  const AttractScreen({super.key, required this.case_, required this.onStart});

  final BoothCase case_;
  final VoidCallback onStart;

  @override
  State<AttractScreen> createState() => _AttractScreenState();
}

class _AttractScreenState extends State<AttractScreen> {
  static const Duration replayEvery = Duration(seconds: 4);

  Timer? _timer;
  int _replay = 0;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.case_;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onStart,
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Text(
              '사진 한 장으로 벌통을 진단합니다',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    // 부스에서는 사진이 주인공이다 — 게이지 컬럼보다 넓게.
                    flex: 7,
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
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 3,
                    child: Center(
                      // 좁아진 컬럼을 게이지가 채우도록 키운다 — 기존 260 은
                      // 컬럼 대비 작아 여백이 과했다.
                      child: RiskGauge(
                        score: c.riskScore,
                        tier: c.tier,
                        caption: riskTierLabel(c.tier),
                        size: 320,
                        stroke: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '화면을 터치해 시작하세요',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
    );
  }
}
