import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/risk/risk_tier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/risk_badge.dart';
import '../../analyses/data/analyses_api.dart';
import '../../analyses/data/analysis_dto.dart';
import '../data/hive_dto.dart';

/// Home hive card matching the design: name + chevron, location, last-measured
/// date, tier badge, and the big risk score. Tier/score/date come from the
/// hive's latest analysis (per-hive [latestAnalysisProvider]); shows
/// "아직 진단 없음" until one exists.
class HiveSummaryCard extends ConsumerWidget {
  const HiveSummaryCard({super.key, required this.hive, this.onTap});

  final Hive hive;
  final VoidCallback? onTap;

  String get _location =>
      (hive.address != null && hive.address!.isNotEmpty) ? hive.address! : '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final latest = ref.watch(latestAnalysisProvider(hive.id));
    final Analysis? analysis = latest.asData?.value;
    final RiskTier tier = analysis?.tier ?? RiskTier.unknown;
    final tierColor = riskTierColor(tier);
    final int? score = analysis?.varroaInfectionRisk;

    // Distinguish "no analysis yet" from "still loading" / "failed to load" so
    // a transient/errored fetch doesn't masquerade as a never-diagnosed hive.
    final String statusText = analysis != null
        ? _fmtDate(analysis.analyzedAt ?? analysis.createdAt)
        : latest.isLoading
            ? '…'
            : (latest.hasError ? l10n.cardLoadFailed : l10n.noAnalysisYet);

    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: AppColors.divider),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      hive.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.hintBorder),
                  const Spacer(),
                  RiskBadge(tier: tier),
                ],
              ),
              if (_location.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    const Icon(Icons.location_on,
                        size: 16, color: AppColors.hintBorder),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              AppSpacing.gapMd,
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.lastMeasuredAt,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          statusText,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (score != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$score',
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: tierColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          l10n.scoreSuffix,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  final mm = l.month.toString().padLeft(2, '0');
  final dd = l.day.toString().padLeft(2, '0');
  return '${l.year}.$mm.$dd';
}
