import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/brand_wordmark.dart';
// Ensures the auth controller is constructed (its build() schedules bootstrap).
import 'auth_controller.dart';

/// Boot screen. Dark background, centered wordmark, amber tagline near the
/// bottom third. It performs no navigation itself — the router redirect advances
/// away from `/splash` as soon as [authControllerProvider] resolves to a
/// non-splash state.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // Touch the provider so bootstrap starts even if this is the very first
    // frame the controller is read (idempotent — provider is a singleton).
    ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.splashBg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 5),
            // Bee mark placeholder (illustration asset is a later TODO).
            const _BeeMark(),
            AppSpacing.gapLg,
            const BrandWordmark(size: 40, color: AppColors.surface),
            const Spacer(flex: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Text(
                l10n.splashTagline,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.amberDeep,
                    ),
              ),
            ),
            const Spacer(flex: 2),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.honeyPrimary,
              ),
            ),
            AppSpacing.gapXxl,
          ],
        ),
      ),
    );
  }
}

/// Simple rounded honey-tinted bee mark placeholder (no asset dependency yet).
class _BeeMark extends StatelessWidget {
  const _BeeMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: const BoxDecoration(
        color: AppColors.honeyBrand,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.hive_rounded,
        size: 56,
        color: AppColors.splashBg,
      ),
    );
  }
}
