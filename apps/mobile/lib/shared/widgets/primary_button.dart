import 'package:flutter/material.dart';

import 'package:helpbee/core/theme/app_colors.dart';
import 'package:helpbee/core/theme/app_radius.dart';

/// HelpBee primary CTA button.
///
/// Spec: fill [AppColors.honeyPrimary], label [AppColors.textPrimary] bold ~17,
/// height 56, radius 14. Disabled = 45% opacity. Loading = centered
/// [CircularProgressIndicator] (strokeWidth 2, color textPrimary). Optional
/// leading [icon].
///
/// [onPressed] null OR [loading] true disables interaction.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null && !loading;

    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: Material(
          color: AppColors.honeyPrimary,
          borderRadius: AppRadius.buttonRadius,
          clipBehavior: Clip.antiAlias,
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
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 20, color: AppColors.textPrimary),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
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
