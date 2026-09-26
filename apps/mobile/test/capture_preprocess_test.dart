// 업로드 전처리 정책 (spec v2.2 §8): 10 MB 이하면 원본 해상도 유지, 초과 시에만
// 긴 변 4000. 플랫폼 채널(flutter_image_compress)은 호스트에서 못 돌리므로
// 순수 정책 함수만 검증한다.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/features/analyses/data/capture_preprocess.dart';

void main() {
  _m4Tests();
  test('no downscale at or below 10 MB', () {
    expect(uploadBoxForBytes(5 * 1024 * 1024), greaterThan(8000));
    expect(uploadBoxForBytes(uploadMaxBytes), greaterThan(8000));
  });

  test('long side 4000 only above 10 MB', () {
    expect(uploadBoxForBytes(uploadMaxBytes + 1), downscaleLongSide);
    expect(downscaleLongSide, 4000);
  });
}

Uint8List _jpegWithSof(int w, int h) {
  // SOI, APP0 (empty), SOF0 (len 17: precision + h + w + 3 comps), EOI
  final sof = [
    0xFF,
    0xC0,
    0x00,
    0x11,
    0x08,
    (h >> 8) & 0xFF,
    h & 0xFF,
    (w >> 8) & 0xFF,
    w & 0xFF,
    0x03,
    0x01,
    0x22,
    0x00,
    0x02,
    0x11,
    0x01,
    0x03,
    0x11,
    0x01,
  ];
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x02,
    ...sof,
    0xFF,
    0xD9,
  ]);
}

// M4: 50 MP 가드 — JPEG 헤더에서 치수를 읽어 초과 시 긴 변을 제한한다.
void _m4Tests() {
  test('jpegDimensions parses SOF0 and returns null for non-JPEG', () {
    expect(jpegDimensions(_jpegWithSof(4000, 3000)), (4000, 3000));
    expect(jpegDimensions(Uint8List.fromList([0, 1, 2, 3])), isNull);
  });

  test('uploadBoxForPixels caps only above 50 MP', () {
    expect(uploadBoxForPixels(4000, 3000), greaterThan(8000)); // 12 MP passes
    expect(uploadBoxForPixels(9248, 6936), pixelCapLongSide); // 64 MP capped
    expect(uploadBoxForPixels(null, null), greaterThan(8000)); // HEIC: unknown
    expect(
      pixelCapLongSide * pixelCapLongSide * 3 ~/ 4,
      lessThan(maxInputPixels),
    );
  });
}
