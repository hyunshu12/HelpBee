import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// Central [ThemeData] factory for HelpBee.
///
/// Material 3. Seed from [AppColors.honeyPrimary], then override with our exact
/// tokens. Input decoration matches the Figma fields: white fill, 1px
/// [AppColors.hintBorder] border, radius 12, hint in [AppColors.hintBorder].
/// PrimaryButton is a custom widget, so ElevatedButton theming is minimal.
abstract final class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.honeyPrimary,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.honeyPrimary,
      secondary: AppColors.amberDeep,
      surface: isDark ? AppColors.splashBg : AppColors.surface,
      error: AppColors.error,
      onPrimary: AppColors.textPrimary,
      onSurface: isDark ? AppColors.bgLight : AppColors.textPrimary,
      outline: AppColors.hintBorder,
    );

    final scaffoldBg = isDark ? AppColors.splashBg : AppColors.bgLight;

    final baseTextTheme = ThemeData(brightness: brightness).textTheme;
    final textTheme = AppTypography.buildTextTheme(baseTextTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      canvasColor: scaffoldBg,
      textTheme: textTheme,
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: isDark ? AppColors.bgLight : AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
      ),
      inputDecorationTheme: _inputDecorationTheme(),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        side: const BorderSide(color: AppColors.hintBorder, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.honeyLight;
          }
          return AppColors.surface;
        }),
        checkColor: const WidgetStatePropertyAll(AppColors.textPrimary),
      ),
      // PrimaryButton/SecondaryButton are custom; keep ElevatedButton sane as a
      // fallback that still matches the brand.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.honeyPrimary,
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(56),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
          ),
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 17),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.bgLight),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadius.inputRadius,
        ),
      ),
    );
  }

  static InputDecorationTheme _inputDecorationTheme() {
    const border = OutlineInputBorder(
      borderRadius: AppRadius.inputRadius,
      borderSide: BorderSide(color: AppColors.hintBorder, width: 1),
    );

    return InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: AppColors.hintBorder, fontSize: 16),
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
      floatingLabelStyle: const TextStyle(color: AppColors.amberDeep, fontSize: 14),
      errorStyle: const TextStyle(color: AppColors.error, fontSize: 13),
      border: border,
      enabledBorder: border,
      focusedBorder: const OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide(color: AppColors.amberDeep, width: 1.5),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide(color: AppColors.error, width: 1),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide(color: AppColors.error, width: 1.5),
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: AppRadius.inputRadius,
        borderSide: BorderSide(color: AppColors.divider, width: 1),
      ),
    );
  }
}
