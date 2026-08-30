import 'package:flutter/material.dart';

import '../data/risk_tier.dart';
import '../theme/app_colors.dart';

/// 위험도 추이 꺾은선. y축은 0~100 고정(자동 스케일 금지 — 점이 1~2개일 때
/// 축이 요동쳐 아무 의미 없는 그래프가 된다). seedCount 이전은 예시 기록이라
/// 회색으로 그린다.
///
/// 관람객 눈엔 그냥 구불구불한 선이라 y축이 뭘 뜻하는지 알 수 없다 — 그래서
/// "위험도 0~100" 표시와, 위험 기준선(70점)을 옅게 함께 그린다. 곁가지 화면이라
/// 최소한만: 눈금 전부 대신 기준선 하나 + 텍스트 두 줄.
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
      const Positioned(
        right: 8,
        top: 8,
        child: Text(
          '세로축: 위험도 0(안전)~100(위험)',
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

    _drawDangerThreshold(canvas, size);

    if (scores.isEmpty) return;

    Offset at(int i) {
      final dx = scores.length == 1
          ? size.width / 2
          : size.width * i / (scores.length - 1);
      return Offset(dx, _yFor(scores[i], size));
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

  /// 상단 라벨("예시 기록" · 세로축 설명) 자리를 위해 값 매핑에 여백을 둔다.
  /// 없으면 100점(가장 위험한 값)이 정확히 라벨과 같은 모서리에 찍혀 겹친다
  /// (2026-08-30 실측 — danger-100 기록 후 스크린샷에서 발견).
  static const double _topPad = 36;

  double _yFor(int score, Size size) =>
      _topPad + (size.height - _topPad) * (1 - score.clamp(0, 100) / 100);

  /// risk_tier.dart 의 위험 기준(70점 이상)을 옅은 빨강 점선으로 표시한다 —
  /// "위험" 태그를 선 옆에 붙여 숫자 없이도 기준선임을 알 수 있게.
  void _drawDangerThreshold(Canvas canvas, Size size) {
    final y = _yFor(70, size);
    final line = Paint()
      ..color = AppColors.tierDanger.withValues(alpha: 0.35)
      ..strokeWidth = 1.5;
    const dash = 8.0;
    const gap = 6.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), line);
      x += dash + gap;
    }

    final label = TextPainter(
      text: const TextSpan(
        text: '위험 70+',
        style: TextStyle(fontSize: 14, color: AppColors.tierDanger),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(size.width - label.width - 4, y - label.height - 2),
    );
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.scores != scores || old.seedCount != seedCount;
}
