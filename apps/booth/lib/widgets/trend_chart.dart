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
      // 두 캡션을 좌상단에 함께 쌓는다. seedScores([12, 28, 21, 45])는 항상
      // 맨 앞(왼쪽) 네 점이라 이 구석은 어떤 기록으로도 채워지지 않는다 —
      // 반대로 우상단은 관람객이 위험 사진을 고르면 마지막 점(자신의 결과)이
      // 정확히 그 자리에서 끝나는, 이 그래프의 핵심 지점이라 캡션이 있으면
      // 안 된다(2026-08-30 실측 — danger 케이스 기록 후 "세로축..." 캡션과
      // 점이 겹침).
      const Positioned(
        left: 8,
        top: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '예시 기록',
              style: TextStyle(fontSize: 22, color: AppColors.textSecondary),
            ),
            SizedBox(height: 4),
            Text(
              '세로축: 위험도 0(안전)~100(위험)',
              style: TextStyle(fontSize: 22, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    ],
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.scores, required this.seedCount});

  final List<int> scores;
  final int seedCount;

  /// 점 반지름 중 가장 큰 값(비-seed 점, `paint()` 아래 `isSeed ? 6 : 10`).
  static const double _maxDotRadius = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axis,
    );

    _drawDangerThreshold(canvas, size);

    if (scores.isEmpty) return;

    // 마지막 점(관람객 자신의 결과)이 정확히 x=size.width 에 찍히면 반지름
    // 10짜리 원의 절반이 Stack 의 Clip.hardEdge 에 잘려나간다 — 이 화면
    // 전체의 핵심인 "내 결과 점"이 우측 캡션 아래로 잘려 보였다(2026-08-30
    // 실측). 좌우로 최대 반지름만큼 여백을 둬 첫 점과 마지막 점이 항상
    // 완전히 그려지는 영역 안에 들어오게 한다.
    Offset at(int i) {
      final usable = size.width - _maxDotRadius * 2;
      final dx = scores.length == 1
          ? size.width / 2
          : _maxDotRadius + usable * i / (scores.length - 1);
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
        style: TextStyle(fontSize: 22, color: AppColors.tierDanger),
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
