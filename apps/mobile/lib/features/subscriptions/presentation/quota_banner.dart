import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/subscriptions_api.dart';

/// Home quota banner (free users only): "이번 달 무료 진단 N회 남음" + UPGRADE.
/// Hidden for paid/unlimited plans or until the subscription loads.
///
/// NOTE: the backend exposes the monthly *allowance* (`monthlyAnalysisQuota`),
/// not the live remaining count, so N is the allowance (best available).
class QuotaBanner extends ConsumerWidget {
  const QuotaBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sub = ref.watch(subscriptionMeProvider).asData?.value;
    if (sub == null || sub.isUnlimited) return const SizedBox.shrink();

    final n = sub.monthlyAnalysisQuota ?? 0;
    return Container(
      width: double.infinity,
      color: AppColors.honeyBrand,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.quotaBanner(n),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Material(
            color: AppColors.surface,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text(l10n.comingSoon))),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  'UPGRADE',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
