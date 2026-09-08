import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/risk_tier.dart';
import '../theme/app_colors.dart';

/// Circular 0–100 risk gauge (Figma 레포트). A light full-circle track with a
/// tier-colored arc sweeping clockwise from the top, the big score in the
/// center, and an optional severity caption beneath it.
///
/// [score] null → unknown/failed: shows "—" with the unknown color and a full
/// faint track (no arc).
///
/// [onDark] 는 어트랙트/마무리의 검은 배경용이다. 트랙과 캡션 색이 밝은 배경
/// 기준으로 고정돼 있으면 다크 화면에서 트랙이 사라지거나 캡션이 안 읽힌다.
class RiskGauge extends StatelessWidget {
  const RiskGauge({
    super.key,
    required this.score,
    required this.tier,
    this.caption,
    this.size = 200,
    this.stroke = 16,
    this.onDark = false,
    this.showScale = true,
  });

  /// 0–100, or null when there is no usable result (failed/pending).
  final int? score;
  final RiskTier tier;

  /// Severity text under the number (예: 위험). null 이면 캡션을 그리지 않는다 —
  /// 결과 화면은 캡션 대신 [TierBadge] 를 쓴다.
  final String? caption;
  final double size;
  final double stroke;
  final bool onDark;

  /// 숫자 아래 `/100` 눈금 표기. 관람객은 "90"만 보면 무엇에 대한 90인지 모른다.
  final bool showScale;

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
          trackColor: onDark ? AppColors.boothInkLine : AppColors.divider,
          stroke: stroke,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score?.toString() ?? '—',
                // displayLarge — 테마의 104pt 위험도 숫자 스타일(Jua). 게이지
                // 지름에 맞춰 축소한다 (size 260 기준 100%).
                style: theme.textTheme.displayLarge?.copyWith(
                  color: color,
                  fontSize:
                      (theme.textTheme.displayLarge?.fontSize ?? 104) *
                      (size / 280).clamp(0.5, 1.25),
                  height: 1.0,
                ),
              ),
              if (showScale)
                Text(
                  '/100',
                  style: TextStyle(
                    fontSize: (size * 0.075).clamp(13, 26),
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    color: onDark ? AppColors.onInkSoft : AppColors.hintBorder,
                  ),
                ),
              if (caption != null) ...[
                SizedBox(height: size * 0.035),
                Text(
                  caption!,
                  style: TextStyle(
                    fontSize: (size * 0.105).clamp(18, 34),
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
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
    const startAngle = -math.pi / 2; // 12 o'clock
    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = arcColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.progress != progress ||
      old.arcColor != arcColor ||
      old.trackColor != trackColor ||
      old.stroke != stroke;
}
