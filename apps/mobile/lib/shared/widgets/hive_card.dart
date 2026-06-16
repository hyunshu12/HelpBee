import 'package:flutter/material.dart';

import 'package:helpbee/core/theme/app_colors.dart';
import 'package:helpbee/core/theme/app_radius.dart';
import 'package:helpbee/core/theme/app_spacing.dart';

/// Tappable summary card for a single hive — name, subtitle (address/location),
/// chevron. Pure presentation: the caller passes already-resolved display
/// strings so the widget stays decoupled from the data layer and easy to test.
class HiveCard extends StatelessWidget {
  const HiveCard({
    super.key,
    required this.name,
    this.subtitle,
    this.onTap,
  });

  final String name;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: AppSpacing.touchTarget),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.hive_rounded,
                  color: AppColors.honeyBrand, size: 28),
              AppSpacing.wGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (hasSubtitle) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.hintBorder),
            ],
          ),
        ),
      ),
    );
  }
}
