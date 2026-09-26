// 업로드 전처리 정책 (spec v2.2 §8): 10 MB 이하면 원본 해상도 유지, 초과 시에만
// 긴 변 4000. 플랫폼 채널(flutter_image_compress)은 호스트에서 못 돌리므로
// 순수 정책 함수만 검증한다.

import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/features/analyses/data/capture_preprocess.dart';

void main() {
  test('no downscale at or below 10 MB', () {
    expect(uploadBoxForBytes(5 * 1024 * 1024), greaterThan(8000));
    expect(uploadBoxForBytes(uploadMaxBytes), greaterThan(8000));
  });

  test('long side 4000 only above 10 MB', () {
    expect(uploadBoxForBytes(uploadMaxBytes + 1), downscaleLongSide);
    expect(downscaleLongSide, 4000);
  });
}
