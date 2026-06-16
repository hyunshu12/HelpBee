import 'package:flutter/material.dart';

/// HelpBee design tokens (from Figma).
///
/// This is the SINGLE source of truth for color hex values in the app.
/// Widgets/screens must NEVER hardcode hex — only reference [AppColors] or
/// `Theme.of(context)`.
abstract final class AppColors {
  AppColors._();

  // ── Brand / honey palette ────────────────────────────────────────────────
  /// CTA fill (primary buttons).
  static const Color honeyPrimary = Color(0xFFFFD869);

  /// Logo / wordmark brand color.
  static const Color honeyBrand = Color(0xFFF9CA46);

  /// Accent / subtitle (deep amber).
  static const Color amberDeep = Color(0xFFE79D04);

  /// Checkbox / selected light tint.
  static const Color honeyLight = Color(0xFFFFE18C);

  // ── Backgrounds / surfaces ───────────────────────────────────────────────
  /// Splash (dark) background.
  static const Color splashBg = Color(0xFF18130C);

  /// Scaffold background (light).
  static const Color bgLight = Color(0xFFFDFCF9);

  /// Card / sheet surface.
  static const Color surface = Color(0xFFFFFFFF);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF18130C);
  static const Color textSecondary = Color(0xFF3C3C3C);

  /// Input border + placeholder text.
  static const Color hintBorder = Color(0xFFB9B9B9);

  // ── Tier (risk) colors — used by later screens ───────────────────────────
  static const Color tierSafe = Color(0xFF2E9E5B);
  static const Color tierWatch = Color(0xFFE79D04);
  static const Color tierDanger = Color(0xFFD7443E);
  static const Color tierUnknown = Color(0xFFB9B9B9);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color error = Color(0xFFD32F2F);
  static const Color divider = Color(0xFFEAE6DD);

  /// Modal scrim (dim behind loading overlays / dialogs).
  static const Color scrim = Color(0x66000000);
}
