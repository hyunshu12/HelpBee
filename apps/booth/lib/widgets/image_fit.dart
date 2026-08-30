import 'dart:math' as math;
import 'dart:ui';

/// 이미지 원본 픽셀 좌표 → 화면 좌표. `BoxFit.contain` 과 같은 규칙이다
/// (가로/세로 중 작은 배율을 쓰고 남는 쪽을 가운데 정렬).
///
/// cases.json 의 박스는 원본 픽셀 좌표이므로, 사진을 어떤 크기로 보여주든
/// 이 변환을 거쳐야 박스가 벌 위에 정확히 얹힌다.
class ImageFit {
  const ImageFit({required this.imageSize, required this.boxSize});

  final Size imageSize;
  final Size boxSize;

  double get scale => math.min(
    boxSize.width / imageSize.width,
    boxSize.height / imageSize.height,
  );

  Offset get offset => Offset(
    (boxSize.width - imageSize.width * scale) / 2,
    (boxSize.height - imageSize.height * scale) / 2,
  );

  Rect toScreen(Rect imageRect) {
    final s = scale;
    final o = offset;
    return Rect.fromLTWH(
      imageRect.left * s + o.dx,
      imageRect.top * s + o.dy,
      imageRect.width * s,
      imageRect.height * s,
    );
  }
}
