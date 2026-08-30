import 'package:flutter/material.dart';

import '../data/booth_case.dart';
import '../theme/app_colors.dart';
import 'image_fit.dart';

/// 사진 + 탐지 박스. 박스는 0.4초에 걸쳐 fade + 살짝 축소되며 나타난다
/// ("AI가 개체를 짚는" 연출).
///
/// cls='varroa' 는 굵은 빨강, 그 외는 얇은 초록. 2026-08-30 bbox 포맷 정정 후
/// 박스가 벌 한 마리씩 정확히 잡히므로 정상 벌도 함께 그린다 — 정상 사진에
/// 초록 박스만 뜨는 그림이 "다 건강하다"를 눈에 보이게 한다.
class BboxOverlay extends StatefulWidget {
  const BboxOverlay({
    super.key,
    required this.photoAsset,
    required this.imageSize,
    required this.boxes,
    this.animate = true,
  });

  final String photoAsset;
  final Size imageSize;
  final List<BoothBox> boxes;
  final bool animate;

  @override
  State<BboxOverlay> createState() => _BboxOverlayState();
}

class _BboxOverlayState extends State<BboxOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _c.forward();
    } else {
      _c.value = 1.0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = ImageFit(
          imageSize: widget.imageSize,
          boxSize: Size(constraints.maxWidth, constraints.maxHeight),
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(widget.photoAsset, fit: BoxFit.contain),
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                painter: _BoxPainter(
                  fit: fit,
                  boxes: widget.boxes,
                  progress: Curves.easeOut.transform(_c.value),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BoxPainter extends CustomPainter {
  _BoxPainter({required this.fit, required this.boxes, required this.progress});

  final ImageFit fit;
  final List<BoothBox> boxes;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    for (final b in boxes) {
      final isVarroa = b.cls == 'varroa';
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isVarroa ? 6 : 3
        ..color = (isVarroa ? AppColors.tierDanger : AppColors.tierSafe)
            .withValues(alpha: progress * (isVarroa ? 1.0 : 0.75));
      final target = fit.toScreen(Rect.fromLTWH(b.x, b.y, b.w, b.h));
      // 1.12배에서 1.0배로 조여들며 나타난다 — "짚는" 느낌
      final k = 1.0 + 0.12 * (1 - progress);
      final r = Rect.fromCenter(
        center: target.center,
        width: target.width * k,
        height: target.height * k,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.progress != progress || old.boxes != boxes;
}
