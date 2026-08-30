import 'package:flutter/material.dart';

import '../data/risk_tier.dart';
import '../theme/app_colors.dart';

/// 위험도 추이 꺾은선. y축은 0~100 고정(자동 스케일 금지 — 점이 1~2개일 때
/// 축이 요동쳐 아무 의미 없는 그래프가 된다). seedCount 이전은 예시 기록이라
/// 회색으로 그린다.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.scores, required this.seedCount});

  final List<int> scores;
  final int seedCount;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _TrendPainter(scores: scores, seedCount: seedCount),
        ),
      ),
      const Positioned(
        left: 8,
        top: 8,
        child: Text(
          '예시 기록',
          style: TextStyle(fontSize: 16, color: Colors.black54),
        ),
      ),
    ],
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.scores, required this.seedCount});

  final List<int> scores;
  final int seedCount;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = Colors.black12
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axis,
    );

    if (scores.isEmpty) return;

    Offset at(int i) {
      final dx = scores.length == 1
          ? size.width / 2
          : size.width * i / (scores.length - 1);
      return Offset(dx, size.height * (1 - scores[i].clamp(0, 100) / 100));
    }

    for (var i = 0; i < scores.length - 1; i++) {
      final isSeed = i + 1 < seedCount;
      canvas.drawLine(
        at(i),
        at(i + 1),
        Paint()
          ..color = isSeed
              ? AppColors.tierUnknown
              : riskTierColor(riskTierFromScore(scores[i + 1]))
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i < scores.length; i++) {
      final isSeed = i < seedCount;
      canvas.drawCircle(
        at(i),
        isSeed ? 6 : 10,
        Paint()
          ..color = isSeed
              ? AppColors.tierUnknown
              : riskTierColor(riskTierFromScore(scores[i])),
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.scores != scores || old.seedCount != seedCount;
}
