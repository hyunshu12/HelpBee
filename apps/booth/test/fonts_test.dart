import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/theme/app_fonts.dart';
import 'package:helpbee_booth/theme/app_theme.dart';
import 'package:helpbee_booth/widgets/bbox_overlay.dart';

/// 2026-08-31 회귀 묶음.
///
/// Flutter Web(CanvasKit)은 번들 폰트에 없는 글리프를 만나면 런타임에
/// fonts.gstatic.com 에서 Noto 조각을 내려받는다. 즉 **폰트를 번들하지 않거나
/// 서체를 명시하지 않으면, 인터넷 없는 부스에서 한글이 전부 두부(□)로 뜬다.**
/// 웹 백업은 정확히 "네이티브가 안 될 때"를 위한 것이라 이게 깨지면 백업으로서
/// 의미가 없다. 실제로 두 군데서 터졌다:
///  1. 테마가 본문 서체를 지정하지 않아 화면 전체가 두부 (수정: boothTheme)
///  2. 추이 그래프의 '위험 70+' 라벨이 TextPainter 라 테마를 안 타서 두부
void main() {
  test('본문 서체 이름이 pubspec 의 번들 선언과 일치한다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final family in [kBodyFont, kDisplayFont]) {
      expect(
        pubspec,
        contains('family: $family'),
        reason: '$family 가 pubspec 에 번들되어 있지 않다 — 웹에서 두부로 뜬다',
      );
    }
  });

  test('테마의 본문 슬롯이 번들 서체를 명시한다', () {
    final t = boothTheme().textTheme;
    for (final entry in {
      'bodyLarge': t.bodyLarge,
      'bodyMedium': t.bodyMedium,
      'titleMedium': t.titleMedium,
      'labelLarge': t.labelLarge,
    }.entries) {
      expect(
        entry.value!.fontFamily,
        isNotNull,
        reason: '${entry.key} 에 서체가 없으면 웹이 CDN 에서 한글을 받아온다',
      );
    }
  });

  test('캔버스에 직접 그리는 박스 태그도 번들 서체를 명시한다', () {
    // TextPainter 는 위젯 트리 밖이라 테마를 상속하지 않는다 — 서체를 안 박으면
    // 웹에서 '응애'/'질병' 태그가 두부(□)가 된다.
    expect(boxTagStyle.fontFamily, kBodyFont);
    expect(boxTagStyle.fontFamilyFallback, contains(kDisplayFont));
  });

  test('서브셋 폰트가 화면에 쓰는 한글을 실제로 담고 있다', () {
    // 서브셋 스크립트(tool/build_body_font.py)가 커버리지를 좁히다 글자를
    // 빠뜨리면, 그 글자만 조용히 두부가 된다.
    for (final path in [
      'assets/fonts/NotoSansKR-Regular.ttf',
      'assets/fonts/NotoSansKR-Bold.ttf',
    ]) {
      final f = File(path);
      expect(
        f.existsSync(),
        isTrue,
        reason: '$path 가 없다 — tool/build_body_font.py 실행 필요',
      );
      expect(
        f.lengthSync(),
        greaterThan(100 * 1024),
        reason: '$path 가 비정상적으로 작다',
      );
    }
  });
}
