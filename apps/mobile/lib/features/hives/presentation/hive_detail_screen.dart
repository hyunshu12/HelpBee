import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/risk/risk_tier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/risk_badge.dart';
import '../../analyses/data/analyses_api.dart';
import '../../analyses/data/analysis_dto.dart';
import '../data/hive_dto.dart';
import 'hive_detail_controller.dart';
import 'hives_list_controller.dart';

/// 벌통 상세 (Figma): 위험 요약 카드 · 위치 · 설치날짜/상태 · 메모 ·
/// 과거 진단 이력 타임라인 · "벌통 다시 촬영하기" CTA · ⋮(수정/삭제).
class HiveDetailScreen extends ConsumerWidget {
  const HiveDetailScreen({super.key, required this.hiveId});

  final String hiveId;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteHive),
        content: Text(l10n.deleteHiveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete,
                style: const TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(hivesListControllerProvider.notifier).deleteHive(hiveId);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.hiveDeleted)));
        context.pop();
      }
    } on AppException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(appErrorMessage(l10n, e))));
      }
    }
  }

  void _comingSoon(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.comingSoon)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(hiveDetailProvider(hiveId));

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(detail.value?.name ?? l10n.hiveDetailTitle),
        actions: [
          if (detail.hasValue)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') {
                  _confirmDelete(context, ref);
                } else {
                  _comingSoon(context);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(l10n.editHive)),
                PopupMenuItem(value: 'delete', child: Text(l10n.deleteHive)),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.error_outline,
            title: l10n.hivesErrorTitle,
            message: appErrorMessage(l10n, error),
            actionLabel: l10n.commonRetry,
            onAction: () => ref.invalidate(hiveDetailProvider(hiveId)),
          ),
          data: (hive) => _Body(hive: hive, onRetake: () => _comingSoon(context)),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.hive, required this.onRetake});

  final Hive hive;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final analyses = ref.watch(hiveAnalysesProvider(hive.id)).asData?.value ??
        const <Analysis>[];
    final Analysis? latest = analyses.isEmpty ? null : analyses.first;
    final tier = latest?.tier ?? RiskTier.unknown;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, AppSpacing.md, AppSpacing.screenH, AppSpacing.xxl),
      children: [
        _RiskSummaryCard(tier: tier, score: latest?.varroaInfectionRisk),
        AppSpacing.gapMd,
        _LocationCard(address: hive.address),
        AppSpacing.gapMd,
        Row(
          children: [
            Expanded(
              child: _MiniCard(
                label: l10n.installDateLabel,
                value: hive.installedAt != null
                    ? _fmtDate(hive.installedAt!)
                    : '-',
              ),
            ),
            AppSpacing.wGapMd,
            Expanded(child: _StatusCard(tier: tier)),
          ],
        ),
        if (hive.note != null && hive.note!.isNotEmpty) ...[
          AppSpacing.gapMd,
          _MemoCard(note: hive.note!),
        ],
        AppSpacing.gapXl,
        Text(
          l10n.historyRecentTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
        AppSpacing.gapSm,
        if (analyses.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              l10n.noAnalysisYet,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          )
        else
          ...List.generate(analyses.length, (i) {
            return _TimelineRow(
              analysis: analyses[i],
              isLast: i == analyses.length - 1,
            );
          }),
        AppSpacing.gapXl,
        PrimaryButton(label: l10n.retakePhoto, onPressed: onRetake),
      ],
    );
  }
}

class _RiskSummaryCard extends StatelessWidget {
  const _RiskSummaryCard({required this.tier, required this.score});

  final RiskTier tier;
  final int? score;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = riskTierColor(tier);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiskBadge(tier: tier),
          AppSpacing.gapSm,
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  l10n.hiveRiskSubtitle,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              if (score != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$score',
                        style: theme.textTheme.displaySmall
                            ?.copyWith(color: color, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 2),
                    Text(l10n.scoreSuffix,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(color: AppColors.textSecondary)),
                  ],
                )
              else
                Text(l10n.noAnalysisYet,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({this.address});

  final String? address;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return _Card(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.honeyLight.withValues(alpha: 0.4),
              borderRadius: AppRadius.inputRadius,
            ),
            child: const Icon(Icons.location_on, color: AppColors.amberDeep),
          ),
          AppSpacing.wGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.hiveLocationCard,
                    style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  (address != null && address!.isNotEmpty) ? address! : '-',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.label, required this.value, this.valueChild});

  final String label;
  final String value;
  final Widget? valueChild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          valueChild ??
              Text(value,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.tier});

  final RiskTier tier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = riskTierColor(tier);
    return _MiniCard(
      label: l10n.statusLabel,
      value: '',
      valueChild: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(riskTierBadge(l10n, tier),
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _MemoCard extends StatelessWidget {
  const _MemoCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.memoTitle,
              style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(note,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.analysis, required this.isLast});

  final Analysis analysis;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tier = analysis.tier;
    final color = riskTierColor(tier);
    final when = analysis.analyzedAt ?? analysis.createdAt;

    final String valueText;
    if (analysis.isFailed) {
      valueText = l10n.errAiUnavailable;
    } else if (analysis.varroaInfectionRisk != null) {
      valueText = l10n.scoreWithTier(
          analysis.varroaInfectionRisk!, _tierShort(l10n, tier));
    } else {
      valueText = l10n.noAnalysisYet;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              const SizedBox(height: 4),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 1.5, color: AppColors.divider),
                ),
            ],
          ),
          AppSpacing.wGapMd,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_fmtDate(when)}(${_relative(l10n, when)})',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.bgLight,
                      borderRadius: AppRadius.inputRadius,
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(l10n.aiAutoDiagnosis,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Text(valueText,
                            style: theme.textTheme.bodyLarge?.copyWith(
                                color: analysis.isFailed
                                    ? AppColors.textSecondary
                                    : color,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }
}

String _tierShort(AppLocalizations l10n, RiskTier tier) => switch (tier) {
      RiskTier.safe => l10n.tierSafe,
      RiskTier.watch => l10n.tierWatch,
      RiskTier.danger => l10n.tierDanger,
      RiskTier.unknown => l10n.tierUnknown,
    };

String _relative(AppLocalizations l10n, DateTime d) {
  final now = DateTime.now();
  final l = d.toLocal(); // backend timestamps are UTC; match _fmtDate's local day
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(l.year, l.month, l.day))
      .inDays;
  if (days <= 0) return l10n.today;
  if (days == 1) return l10n.yesterday;
  return l10n.daysAgo(days);
}

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  final mm = l.month.toString().padLeft(2, '0');
  final dd = l.day.toString().padLeft(2, '0');
  return '${l.year}.$mm.$dd';
}
