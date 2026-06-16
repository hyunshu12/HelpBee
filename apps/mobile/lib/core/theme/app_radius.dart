import 'package:flutter/widgets.dart';

/// Corner-radius scale (from Figma).
abstract final class AppRadius {
  AppRadius._();

  /// Input fields.
  static const double input = 12;

  /// Primary CTA buttons.
  static const double button = 14;

  /// Cards.
  static const double card = 16;

  static const BorderRadius inputRadius = BorderRadius.all(Radius.circular(input));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(button));
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(card));
}
