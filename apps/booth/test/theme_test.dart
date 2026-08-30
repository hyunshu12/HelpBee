import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpbee_booth/theme/app_colors.dart';
import 'package:helpbee_booth/theme/app_theme.dart';

void main() {
  // 2026-08-31 회귀: 예전 테마는 `ColorScheme.fromSeed(honeyBrand)` 결과를
  // 그대로 썼다. M3 톤 팔레트가 노란 시드에서 뽑는 primary 는 #755B0B(탁한
  // 올리브 갈색)이라, 화면의 모든 FilledButton 이 꿀색이 아니라 진갈색으로
  // 칠해졌다. 토큰 파일만 복사하고 스킴에 적용하지 않으면 조용히 재발한다.
  test('primary 는 시드 파생색이 아니라 honeyPrimary 토큰 그대로다', () {
    final scheme = boothTheme().colorScheme;

    expect(scheme.primary, AppColors.honeyPrimary);
    expect(scheme.onPrimary, AppColors.textPrimary);

    final generated = ColorScheme.fromSeed(
      seedColor: AppColors.honeyPrimary,
    ).primary;
    expect(
      scheme.primary,
      isNot(generated),
      reason: 'fromSeed 가 만든 색이 그대로 새어 나오면 버튼이 갈색이 된다',
    );
  });

  test('밝은 배경 위 본문이 배경과 충분히 대비된다', () {
    final theme = boothTheme();
    // 색을 빠뜨린 TextStyle 은 null 이 되어 "검정"이 아니라 **투명하게** 렌더된다.
    // 이전에 실제로 겪은 사고라, 슬롯마다 색이 실재하는지 단언한다.
    for (final entry in {
      'displayLarge': theme.textTheme.displayLarge,
      'headlineLarge': theme.textTheme.headlineLarge,
      'headlineMedium': theme.textTheme.headlineMedium,
      'headlineSmall': theme.textTheme.headlineSmall,
      'titleMedium': theme.textTheme.titleMedium,
      'bodyLarge': theme.textTheme.bodyLarge,
      'bodyMedium': theme.textTheme.bodyMedium,
      'labelLarge': theme.textTheme.labelLarge,
    }.entries) {
      final style = entry.value;
      expect(style, isNotNull, reason: '${entry.key} 슬롯이 비어 있다');
      expect(style!.color, isNotNull, reason: '${entry.key} 에 색이 없다');
      expect(
        _luminanceGap(style.color!, AppColors.boothBg),
        greaterThan(3.0),
        reason: '${entry.key} 가 크림 배경 위에서 읽히지 않는다',
      );
    }
  });

  test('부스 본문 최소 크기는 20pt 이상이다 (서서, 1m 밖에서 읽는 화면)', () {
    final t = boothTheme().textTheme;
    expect(t.bodyLarge!.fontSize, greaterThanOrEqualTo(22));
    expect(t.bodyMedium!.fontSize, greaterThanOrEqualTo(20));
  });
}

/// WCAG 대비비.
double _luminanceGap(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
