import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_fonts.dart';
import 'app_radius.dart';

/// 부스 전용 테마. apps/mobile 의 톤을 유지하되 서서 보는 화면이라
/// 본문 22sp, 위험도 숫자 104sp 로 키운다.
///
/// 폰트는 두 갈래다 — Jua(display: 헤드라인·위험도 숫자)는 pubspec.yaml 에
/// TTF 로 번들해 네트워크 의존 없이 뜬다. 본문 한글은 의도적으로 번들하지
/// 않고 플랫폼 시스템 폰트(iOS: Apple SD Gothic Neo)로 폴백한다 — 본문은
/// 분량이 많아 커스텀 서체를 번들하면 앱 크기·초기 렌더 비용이 늘고, 부스
/// 데모에서는 시스템 폰트 가독성으로 충분하기 때문.
///
/// ⚠️ 2026-08-31: `ColorScheme.fromSeed(honeyBrand)` 를 **그대로 쓰면 안 된다.**
/// M3 톤 팔레트가 노란 시드에서 뽑아내는 primary 는 `#755B0B`(탁한 올리브
/// 갈색)이라, FilledButton 전부가 꿀색이 아니라 진갈색으로 칠해졌었다.
/// apps/mobile 과 똑같이 시드 결과를 실제 토큰으로 **덮어쓴다**.
ThemeData boothTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.honeyPrimary)
      .copyWith(
        primary: AppColors.honeyPrimary,
        onPrimary: AppColors.textPrimary,
        secondary: AppColors.amberDeep,
        onSecondary: AppColors.surface,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        outline: AppColors.divider,
      );

  // 본문 기본 서체를 번들 폰트로 못박는다. 지정하지 않으면 Flutter Web 이
  // 런타임에 fonts.gstatic.com 에서 한글 글리프를 받아오고, 오프라인 부스에서
  // 본문이 전부 두부(□)가 된다(2026-08-31 실측). fallback 의 Jua 는 서브셋에
  // 없는 글자가 나와도 최소한 읽히게 하는 안전망이다.
  const body = kBodyFont;
  const fallback = kBodyFallback;

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: body,
    fontFamilyFallback: fallback,
  );

  // copyWith replaces each TextStyle wholesale, not merged — a missing
  // color here becomes null, which renders invisible, not black. Every
  // override below must set color explicitly.
  final textTheme = base.textTheme.copyWith(
    // ── Jua (display) — 헤드라인과 숫자 전용. 본문에는 쓰지 않는다.
    displayLarge: const TextStyle(
      fontFamily: kDisplayFont,
      fontFamilyFallback: kDisplayFallback,
      fontSize: 104,
      height: 1.0,
      letterSpacing: -2,
      color: AppColors.textPrimary,
    ),
    displayMedium: const TextStyle(
      fontFamily: kDisplayFont,
      fontFamilyFallback: kDisplayFallback,
      fontSize: 64,
      height: 1.05,
      color: AppColors.textPrimary,
    ),
    headlineLarge: const TextStyle(
      fontFamily: kDisplayFont,
      fontFamilyFallback: kDisplayFallback,
      fontSize: 46,
      height: 1.22,
      color: AppColors.textPrimary,
    ),
    headlineMedium: const TextStyle(
      fontFamily: kDisplayFont,
      fontFamilyFallback: kDisplayFallback,
      fontSize: 34,
      height: 1.28,
      color: AppColors.textPrimary,
    ),
    headlineSmall: const TextStyle(
      fontFamily: kDisplayFont,
      fontFamilyFallback: kDisplayFallback,
      fontSize: 27,
      height: 1.3,
      color: AppColors.textPrimary,
    ),
    // ── 시스템 한글 (본문·라벨)
    titleLarge: const TextStyle(
      fontFamily: body,
      fontFamilyFallback: fallback,
      fontSize: 26,
      height: 1.35,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    titleMedium: const TextStyle(
      fontFamily: body,
      fontFamilyFallback: fallback,
      fontSize: 22,
      height: 1.4,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    bodyLarge: const TextStyle(
      fontFamily: body,
      fontFamilyFallback: fallback,
      fontSize: 22,
      height: 1.55,
      color: AppColors.textPrimary,
    ),
    bodyMedium: const TextStyle(
      fontFamily: body,
      fontFamilyFallback: fallback,
      fontSize: 20,
      height: 1.55,
      color: AppColors.textSecondary,
    ),
    bodySmall: const TextStyle(
      fontFamily: body,
      fontFamilyFallback: fallback,
      fontSize: 18,
      height: 1.5,
      color: AppColors.textSecondary,
    ),
    labelLarge: const TextStyle(
      fontFamily: body,
      fontFamilyFallback: fallback,
      fontSize: 22,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.boothBg,
    canvasColor: AppColors.boothBg,
    textTheme: textTheme,
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    // 주 CTA — 꿀색 채우기 + 진한 글자. 부스는 서서 누르므로 높이 72 가 기본.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.honeyPrimary,
        foregroundColor: AppColors.textPrimary,
        disabledBackgroundColor: AppColors.divider,
        minimumSize: const Size(0, 72),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.buttonRadius,
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    // 보조 액션 — 예전에는 스타일 없는 TextButton 이라 "그냥 글자"로 보였다.
    // 옅은 꿀색 알약 + 테두리를 줘서 눌러야 할 것으로 읽히게 한다.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        backgroundColor: AppColors.honeySoft,
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size(0, 60),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.buttonRadius,
          side: BorderSide(color: AppColors.honeyEdge),
        ),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 20),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.amberDeep,
      linearTrackColor: AppColors.divider,
      circularTrackColor: AppColors.divider,
    ),
  );
}
