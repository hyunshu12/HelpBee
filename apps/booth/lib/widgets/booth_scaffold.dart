import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'brand.dart';

/// 모든 부스 화면의 공통 틀. 화면마다 `Padding(Column(...))` 을 새로 짜면
/// 여백·정렬·브랜딩이 제각각이 되고, 그 불일치가 "슬라이드 같다"는 인상의
/// 절반을 만든다. 여기 한 곳에서 여백·헤더·배경을 정한다.
///
/// [dark] 는 어트랙트/마무리처럼 **시선을 끌어야 하는** 화면용이다. 밝은 크림
/// 화면들 사이에 검정 화면이 끼면 부스 앞을 지나는 사람 눈에 확실히 걸린다.
class BoothScaffold extends StatelessWidget {
  const BoothScaffold({
    super.key,
    required this.child,
    this.dark = false,
    this.eyebrow,
    this.footer,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(48, 28, 48, 36),
  });

  final Widget child;
  final bool dark;

  /// 헤더 우측의 단계 라벨. null 이면 헤더에 워드마크만 남는다.
  final String? eyebrow;

  /// 본문 아래 고정 영역(버튼 줄 등).
  final Widget? footer;

  /// 화면 전체를 탭 대상으로 만든다 (어트랙트·인트로).
  final VoidCallback? onTap;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Wordmark(onDark: dark, size: 28),
              const Spacer(),
              if (eyebrow != null) Eyebrow(eyebrow!, onDark: dark),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(child: child),
          if (footer != null) ...[const SizedBox(height: 24), footer!],
        ],
      ),
    );

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        // 배경: 밝은 화면은 은은한 꿀빛 그라디언트, 다크는 검정 + 상단 글로우.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: dark
                ? const RadialGradient(
                    center: Alignment(0.55, -0.85),
                    radius: 1.25,
                    colors: [Color(0xFF2E2413), AppColors.boothInk],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFFDF6), Color(0xFFFDF3DC)],
                  ),
          ),
        ),
        // 벌집 모티프. 아주 낮은 알파로 깔아 "그냥 단색 배경"을 면하게 한다.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _HoneycombPainter(dark: dark)),
          ),
        ),
        body,
      ],
    );

    final content = onTap == null
        ? stack
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: stack,
          );

    return DefaultTextStyle.merge(
      style: TextStyle(color: dark ? AppColors.onInk : AppColors.textPrimary),
      child: content,
    );
  }
}

/// 우하단에 겹치는 육각 격자. 장식이지 정보가 아니므로 알파를 크게 낮춘다.
class _HoneycombPainter extends CustomPainter {
  _HoneycombPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = (dark ? AppColors.honeyBrand : AppColors.amberDeep).withValues(
        alpha: dark ? 0.08 : 0.055,
      );

    const r = 74.0;
    final dx = r * math.sqrt(3);
    final dy = r * 1.5;

    // 우하단 모서리에서 시작해 왼쪽·위로 3열 x 3행만 그린다 — 화면 전체를
    // 덮으면 배경이 시끄러워 본문 가독성을 해친다.
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        final cx = size.width - 30 - col * dx + (row.isOdd ? dx / 2 : 0);
        final cy = size.height + 30 - row * dy;
        canvas.drawPath(_hex(Offset(cx, cy), r), paint);
      }
    }
  }

  Path _hex(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(_HoneycombPainter old) => old.dark != dark;
}
