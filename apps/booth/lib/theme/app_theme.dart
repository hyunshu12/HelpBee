import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 부스 전용 테마. apps/mobile 의 톤을 유지하되 서서 보는 화면이라
/// 본문 22sp, 위험도 숫자 96sp 로 키운다. 폰트는 번들 TTF (네트워크 의존 없음).
ThemeData boothTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.honeyBrand),
    // 본문 한글은 시스템 폰트(iOS: Apple SD Gothic Neo). 번들하지 않는다 — 위 pubspec 주석 참조.
  );
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFFFFBF0),
    textTheme: base.textTheme.copyWith(
      // TextTheme.copyWith replaces each style wholesale rather than merging
      // fields, so any color left unset here becomes null — not "inherit the
      // Material3 default". A null color does not paint as black; it renders
      // essentially invisible against the background. Every override below
      // must carry an explicit color for that reason (found via manual
      // simulator run in Task 6 — every headline/body line across the app
      // was rendering as a near-invisible cream-on-cream ghost).
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
