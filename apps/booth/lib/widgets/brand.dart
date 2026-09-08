import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_fonts.dart';

/// HelpBee 워드마크 — 육각(벌집) 마크 + Jua 로고 타입.
///
/// 이미지 에셋을 쓰지 않고 그린다. 이유가 둘 있다: (1) 부스 앱은 외부 패키지·
/// 에셋을 최소로 유지하고, (2) `picker_screen_test` 가 화면의 `Image` 위젯
/// 개수(사진 4장)를 세므로 헤더에 `Image` 를 하나라도 넣으면 그 테스트가
/// 깨진다. `CustomPaint` 는 세지 않는다.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.onDark = false, this.size = 30});

  final bool onDark;

  /// 로고 타입의 글자 크기. 마크는 이 값에 비례한다.
  final double size;

  @override
  Widget build(BuildContext context) {
    final markSize = size * 1.15;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: markSize,
          height: markSize,
          child: CustomPaint(painter: _HexMarkPainter(onDark: onDark)),
        ),
        SizedBox(width: size * 0.36),
        Text(
          'HelpBee',
          style: TextStyle(
            fontFamily: kDisplayFont,
            fontFamilyFallback: kDisplayFallback,
            fontSize: size,
            height: 1.0,
            letterSpacing: 0.2,
            color: onDark ? AppColors.honeyBrand : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// 벌집 셀 하나. 꿀색으로 채우고 안쪽에 작은 육각을 비워 "셀"처럼 보이게 한다.
class _HexMarkPainter extends CustomPainter {
  _HexMarkPainter({required this.onDark});

  final bool onDark;

  Path _hex(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      // -90° 에서 시작 = 꼭짓점이 위로 오는 육각(pointy-top).
      final a = -math.pi / 2 + i * math.pi / 3;
      final pt = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    canvas.drawPath(_hex(c, r), Paint()..color = AppColors.honeyPrimary);
    canvas.drawPath(
      _hex(c, r * 0.52),
      Paint()
        ..color = onDark ? AppColors.boothInk : AppColors.textPrimary
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_HexMarkPainter old) => old.onDark != onDark;
}

/// 화면 상단의 작은 안내 라벨("STEP 2 · 사진 고르기" 같은 것).
/// 헤드라인 위에 얹어 위계를 만든다 — 전부 같은 크기 텍스트만 쌓으면
/// 슬라이드처럼 보인다.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.onDark = false});

  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 20,
      height: 1.2,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.4,
      color: onDark ? AppColors.honeyBrand : AppColors.amberDeep,
    ),
  );
}
