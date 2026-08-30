import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/risk_tier.dart';
import '../theme/app_colors.dart';

/// Circular 0–100 risk gauge (Figma 레포트). A light full-circle track with a
/// tier-colored arc sweeping clockwise from the top, the big score in the
/// center, and a severity caption beneath it.
///
/// [score] null → unknown/failed: shows "—" with the unknown color and a full
/// faint track (no arc).
class RiskGauge extends StatelessWidget {
  const RiskGauge({
    super.key,
    required this.score,
    required this.tier,
    required this.caption,
    this.size = 200,
    this.stroke = 16,
  });

  /// 0–100, or null when there is no usable result (failed/pending).
  final int? score;
  final RiskTier tier;

  /// Severity text under the number (e.g. 심각 수준).
  final String caption;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = riskTierColor(tier);
    final progress = score == null ? 0.0 : (score!.clamp(0, 100)) / 100.0;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(
          progress: progress,
          arcColor: color,
          trackColor: AppColors.divider,
          stroke: stroke,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score?.toString() ?? '—',
                // displayLarge — 테마의 96pt 위험도 숫자 스타일(Jua). displayMedium은
                // app_theme.dart 가 오버라이드하지 않아 기본값(45pt, 시스템 폰트)으로
                // 떨어지는 채로 남아 있었다 — "위험도 숫자 96pt" 기준을 충족하지 못했다.
                style: theme.textTheme.displayLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                // 96pt 숫자는 그 자체로 의미가 없다 — 의미는 이 단어(위험/주의/안전)에
                // 있다. titleSmall(Material3 기본 14pt)로는 서서, 1m 밖에서 읽는
                // 부스 환경에서 읽히지 않는다. §9 22pt 바닥보다 크게, 숫자 옆에서도
                // 눈에 띄도록 28pt + 굵게.
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 28,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.progress,
    required this.arcColor,
    required this.trackColor,
    required this.stroke,
  });

  final double progress; // 0..1
  final Color arcColor;
  final Color trackColor;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;
    final arcPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    const startAngle = -math.pi / 2; // 12 o'clock
    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(rect, startAngle, sweepAngle, false, arcPaint);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress ||
      old.arcColor != arcColor ||
      old.trackColor != trackColor ||
      old.stroke != stroke;
}
