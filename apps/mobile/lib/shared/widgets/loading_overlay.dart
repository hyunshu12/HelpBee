import 'package:flutter/material.dart';

import 'package:helpbee/core/theme/app_colors.dart';

/// Full-screen modal loading overlay.
///
/// Wraps [child]; when [loading] is true, dims the screen and shows a centered
/// spinner, absorbing pointer events so the underlying UI is non-interactive.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    required this.loading,
    required this.child,
  });

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (loading)
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.scrim,
              child: Center(
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.honeyPrimary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
