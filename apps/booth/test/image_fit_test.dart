import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/widgets/image_fit.dart';

void main() {
  group('BoxFit.contain 좌표 변환', () {
    test('세로가 남는 경우 위아래로 레터박스된다', () {
      // 1920x1080 사진을 800x600 영역에 contain → 800x450, 위아래 75씩 여백
      const fit = ImageFit(
        imageSize: Size(1920, 1080),
        boxSize: Size(800, 600),
      );
      expect(fit.scale, closeTo(0.4166667, 1e-6));
      expect(fit.offset.dx, closeTo(0, 1e-6));
      expect(fit.offset.dy, closeTo(75, 1e-6));
    });

    test('이미지 전체 사각형은 렌더 영역과 일치한다', () {
      const fit = ImageFit(
        imageSize: Size(1920, 1080),
        boxSize: Size(800, 600),
      );
      final r = fit.toScreen(const Rect.fromLTWH(0, 0, 1920, 1080));
      expect(r.left, closeTo(0, 1e-6));
      expect(r.top, closeTo(75, 1e-6));
      expect(r.width, closeTo(800, 1e-6));
      expect(r.height, closeTo(450, 1e-6));
    });

    test('실제 박스 좌표를 화면 좌표로 옮긴다', () {
      const fit = ImageFit(
        imageSize: Size(1920, 1080),
        boxSize: Size(800, 600),
      );
      final r = fit.toScreen(const Rect.fromLTWH(519, 71, 811, 636));
      expect(r.left, closeTo(216.25, 0.01));
      expect(r.top, closeTo(104.583, 0.01));
      expect(r.width, closeTo(337.917, 0.01));
      expect(r.height, closeTo(265.0, 0.01));
    });

    test('가로가 남는 경우 좌우로 레터박스된다', () {
      // 1000x1000 사진을 800x400 영역에 contain → 400x400, 좌우 200씩 여백
      const fit = ImageFit(
        imageSize: Size(1000, 1000),
        boxSize: Size(800, 400),
      );
      expect(fit.scale, closeTo(0.4, 1e-6));
      expect(fit.offset.dx, closeTo(200, 1e-6));
      expect(fit.offset.dy, closeTo(0, 1e-6));
    });
  });
}
