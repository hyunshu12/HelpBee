import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/booth_scaffold.dart';

/// 투어 진입 안내. 5초 안에 지나가는 가벼운 화면이라 사진도 카드도 없다.
///
/// 여기서 "몇 장이나 맞히실까요?"로 **관람객에게 목표를 준다** — 목표가 없으면
/// 사진을 그냥 넘기게 되고, 요약의 "N장 맞힘"도 의미가 없어진다.
class TourStartScreen extends StatelessWidget {
  const TourStartScreen({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return BoothScaffold(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '사진 3장을 진단해 봅니다',
              style: t.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Text(
              '몇 장이나 맞히실까요?',
              style: t.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 48),
            FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(minimumSize: const Size(320, 76)),
              child: const Text('시작하기'),
            ),
          ],
        ),
      ),
    );
  }
}
