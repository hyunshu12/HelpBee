import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Row of four disabled circular SNS sign-in buttons (Kakao / Google / Naver /
/// Apple). These are VISUAL-ONLY — the backend has no SNS auth. Tapping any of
/// them invokes [onTapDisabled] (the screen shows a "coming soon" SnackBar).
///
/// Each button is a 56dp circular tap target (elderly-friendly) with a tooltip
/// + Semantics label so it remains accessible despite being a placeholder.
class SnsLoginRow extends StatelessWidget {
  const SnsLoginRow({super.key, required this.onTapDisabled});

  final VoidCallback onTapDisabled;

  @override
  Widget build(BuildContext context) {
    const providers = <_SnsProvider>[
      _SnsProvider(label: 'Kakao', icon: Icons.chat_bubble_rounded),
      _SnsProvider(label: 'Google', icon: Icons.g_mobiledata_rounded),
      _SnsProvider(label: 'Naver', icon: Icons.alternate_email_rounded),
      _SnsProvider(label: 'Apple', icon: Icons.apple_rounded),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final p in providers)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: _SnsButton(provider: p, onTap: onTapDisabled),
          ),
      ],
    );
  }
}

class _SnsProvider {
  const _SnsProvider({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _SnsButton extends StatelessWidget {
  const _SnsButton({required this.provider, required this.onTap});

  final _SnsProvider provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: provider.label,
      child: Tooltip(
        message: provider.label,
        child: Material(
          color: AppColors.surface,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.divider, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: AppSpacing.touchTarget,
              height: AppSpacing.touchTarget,
              child: Icon(
                provider.icon,
                color: AppColors.hintBorder,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
