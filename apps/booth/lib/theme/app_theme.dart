import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 부스 전용 테마. apps/mobile 의 톤을 유지하되 서서 보는 화면이라
/// 본문 22sp, 위험도 숫자 96sp 로 키운다.
///
/// 폰트는 두 갈래다 — Jua(display: 헤드라인·위험도 숫자)는 pubspec.yaml 에
/// TTF 로 번들해 네트워크 의존 없이 뜬다. 본문 한글은 의도적으로 번들하지
/// 않고 플랫폼 시스템 폰트(iOS: Apple SD Gothic Neo)로 폴백한다 — 본문은
/// 분량이 많아 커스텀 서체를 번들하면 앱 크기·초기 렌더 비용이 늘고, 부스
/// 데모에서는 시스템 폰트 가독성으로 충분하기 때문.
ThemeData boothTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.honeyBrand),
  );
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFFFFBF0),
    textTheme: base.textTheme.copyWith(
      // copyWith replaces each TextStyle wholesale, not merged — a missing
      // color here becomes null, which renders invisible, not black. Every
      // override below must set color explicitly.
      displayLarge: const TextStyle(
        fontFamily: 'Jua',
        fontSize: 96,
        height: 1.0,
        color: AppColors.textPrimary,
      ),
      headlineLarge: const TextStyle(
        fontFamily: 'Jua',
        fontSize: 44,
        height: 1.2,
        color: AppColors.textPrimary,
      ),
      headlineMedium: const TextStyle(
        fontFamily: 'Jua',
        fontSize: 32,
        height: 1.25,
        color: AppColors.textPrimary,
      ),
      bodyLarge: const TextStyle(
        fontSize: 22,
        height: 1.6,
        color: AppColors.textPrimary,
      ),
      bodyMedium: const TextStyle(
        fontSize: 20,
        height: 1.6,
        color: AppColors.textSecondary,
      ),
    ),
  );
}
