import 'package:flutter/material.dart';

import 'package:helpbee/core/theme/app_colors.dart';
import 'package:helpbee/core/theme/app_radius.dart';

/// HelpBee secondary button — outlined variant of [PrimaryButton].
///
/// Transparent fill, [foreground] (default [AppColors.textPrimary]) for the
/// 1px outline + label + spinner, height 56, radius 14. Optional leading
/// [icon]. Pass [foreground] = white to place it over a dark/photo background.
/// Disabled = 45% opacity.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
    this.foreground,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;
    final Color fg = foreground ?? AppColors.textPrimary;
    final Color border = foreground ?? AppColors.hintBorder;

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
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.buttonRadius,
            side: BorderSide(color: border, width: 1),
          ),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Center(
              child: loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: fg,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 20, color: fg),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: TextStyle(
                            color: fg,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
