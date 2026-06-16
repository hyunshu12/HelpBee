import 'package:flutter/material.dart';

import 'package:helpbee/core/theme/app_colors.dart';
import 'package:helpbee/core/theme/app_typography.dart';

/// The "HelpBee" wordmark rendered in GoogleFonts.jua.
///
/// [size] is the font size; [color] defaults to [AppColors.honeyBrand].
/// The literal product name "HelpBee" is a brand mark, not user-facing copy,
/// so it is intentionally hardcoded here rather than localized.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.size = 32,
    this.color = AppColors.honeyBrand,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'HelpBee',
      style: AppTypography.wordmark(size: size, color: color),
    );
  }
}
