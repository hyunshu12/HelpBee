import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// HelpBee typography.
///
/// - Display / logo  → GoogleFonts.jua
/// - Body text       → GoogleFonts.notoSansKr
///
/// Body base size is 16 (lg 18) to favour readability for elderly beekeepers.
/// Pretendard bundling is a later TODO; for now Noto Sans KR is the body font.
abstract final class AppTypography {
  AppTypography._();

  /// Brand wordmark / logo style ("HelpBee").
  static TextStyle wordmark({double size = 28, Color color = AppColors.honeyBrand}) {
    return GoogleFonts.jua(
      fontSize: size,
      color: color,
      height: 1.0,
      letterSpacing: 0.2,
    );
  }

  /// Display style for large headline/hero text (Jua).
  static TextStyle display({
    double size = 24,
    Color color = AppColors.textPrimary,
    double height = 1.3,
  }) {
    return GoogleFonts.jua(
      fontSize: size,
      color: color,
      height: height,
    );
  }

  /// Builds the full body [TextTheme] from Noto Sans KR, layered over a base
  /// theme (so platform metrics are preserved), then tuned for HelpBee.
  static TextTheme buildTextTheme(TextTheme base) {
    final body = GoogleFonts.notoSansKrTextTheme(base);

    return body.copyWith(
      // Display / headline slots use Jua for brand consistency.
      displayLarge: GoogleFonts.jua(
        textStyle: body.displayLarge,
        color: AppColors.textPrimary,
        height: 1.2,
      ),
      displayMedium: GoogleFonts.jua(
        textStyle: body.displayMedium,
        color: AppColors.textPrimary,
        height: 1.2,
      ),
      displaySmall: GoogleFonts.jua(
        textStyle: body.displaySmall,
        color: AppColors.textPrimary,
        height: 1.25,
      ),
      headlineLarge: GoogleFonts.jua(
        textStyle: body.headlineLarge,
        color: AppColors.textPrimary,
        height: 1.25,
      ),
      headlineMedium: GoogleFonts.jua(
        textStyle: body.headlineMedium,
        color: AppColors.textPrimary,
        height: 1.3,
      ),
      headlineSmall: GoogleFonts.jua(
        textStyle: body.headlineSmall,
        color: AppColors.textPrimary,
        height: 1.3,
      ),
      // Titles + body use Noto Sans KR.
      titleLarge: body.titleLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      titleMedium: body.titleMedium?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      titleSmall: body.titleSmall?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      bodyLarge: body.bodyLarge?.copyWith(
        color: AppColors.textPrimary,
        fontSize: 18,
        height: 1.5,
      ),
      bodyMedium: body.bodyMedium?.copyWith(
        color: AppColors.textPrimary,
        fontSize: 16,
        height: 1.5,
      ),
      bodySmall: body.bodySmall?.copyWith(
        color: AppColors.textSecondary,
        fontSize: 14,
        height: 1.45,
      ),
      labelLarge: body.labelLarge?.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      labelMedium: body.labelMedium?.copyWith(
        color: AppColors.textSecondary,
      ),
      labelSmall: body.labelSmall?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }
}
