import 'package:flutter/material.dart';

import 'package:helpbee/core/theme/app_colors.dart';
import 'package:helpbee/core/theme/app_radius.dart';

/// HelpBee secondary button — outlined variant of [PrimaryButton].
///
/// Transparent fill, [AppColors.hintBorder] 1px outline, height 56, radius 14,
/// label [AppColors.textPrimary]. Disabled = 45% opacity. Loading = centered
/// [CircularProgressIndicator] (strokeWidth 2, color textPrimary).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          // NOTE: `shape` and `borderRadius` are mutually exclusive on Material
          // (asserts otherwise). The outline needs a `side`, so the rounded
          // corners come from the shape — do NOT also set `borderRadius`.
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
            side: BorderSide(color: AppColors.hintBorder, width: 1),
          ),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textPrimary,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
