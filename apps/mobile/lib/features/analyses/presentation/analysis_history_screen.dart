import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/risk/risk_tier.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/text/korean_wrap.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/risk_badge.dart';
import '../../hives/data/hive_dto.dart';
import '../../hives/presentation/hives_list_controller.dart';
import '../data/analyses_api.dart';
import '../data/analysis_dto.dart';
import 'analysis_flow_args.dart';

/// 진단 이력 탭 — every analysis across the user's hives, most-recent first
/// (`GET /v1/analyses` with no `hiveId`). Tapping a row opens its report.
///
/// Hive names aren't on the analysis payload, so they're joined client-side
/// from [hivesListControllerProvider] (already loaded for the home tab). A row
/// whose hive is missing from that list still renders — it just falls back to
/// a neutral label rather than disappearing.
class AnalysisHistoryScreen extends ConsumerWidget {
  const AnalysisHistoryScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(allAnalysesProvider);
    await ref.read(allAnalysesProvider.future);
  }

  void _openReport(BuildContext context, Analysis analysis, String hiveName) {
    // The list endpoint omits recommendations; ReportScreen falls back to
    // tier-based copy for list-sourced rows, so this is safe without a refetch.
    context.push(
      RoutePaths.report,
      extra: ReportArgs(analysis: analysis, hiveName: hiveName),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(allAnalysesProvider);
    final hives =
        ref.watch(hivesListControllerProvider).asData?.value ?? const <Hive>[];
    final names = {for (final h in hives) h.id: h.name};

    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: l10n.historyErrorTitle,
            message: appErrorMessage(l10n, error),
            actionLabel: l10n.commonRetry,
            onAction: () => ref.invalidate(allAnalysesProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              // Pull-to-refresh has to survive the empty state too: a diagnosis
              // run on another device should be reachable without a restart.
              return RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.sizeOf(context).height * 0.6,
                      child: EmptyState(
                        icon: Icons.assignment_outlined,
                        title: l10n.historyEmptyTitle,
                        message: keepAll(l10n.historyEmptyBody),
                      ),
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.md,
                  AppSpacing.screenH,
                  AppSpacing.xxl,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) => AppSpacing.gapMd,
                itemBuilder: (context, index) {
                  final analysis = items[index];
                  final hiveName =
                      names[analysis.hiveId] ?? l10n.hiveDetailTitle;
                  return _HistoryCard(
                    analysis: analysis,
                    hiveName: hiveName,
                    onTap: () => _openReport(context, analysis, hiveName),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One row: hive name + tier pill, when it ran, and the score (or a graceful
/// failure line). Mirrors HiveSummaryCard's card shape for visual continuity.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.analysis,
    required this.hiveName,
    this.onTap,
  });

  final Analysis analysis;
  final String hiveName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tier = analysis.tier;
    final color = riskTierColor(tier);
    final when = analysis.analyzedAt ?? analysis.createdAt;
    final score = analysis.varroaInfectionRisk;

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
                      hiveName,
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
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '${_fmtDate(when)} (${_relative(l10n, when)})',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              AppSpacing.gapSm,
              // 실패 문구는 한 문장이라 점수 자리에 두면 라벨을 밀어내 Row가 넘친다
              // (hive_detail의 타임라인과 같은 처리) — 실패일 때만 아래 줄로 내린다.
              if (analysis.isFailed) ...[
                Text(
                  l10n.aiAutoDiagnosis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  keepAll(l10n.errAiUnavailable),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.aiAutoDiagnosis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (score != null) ...[
                      Text(
                        '$score',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        l10n.scoreSuffix,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else
                      Text(
                        l10n.noAnalysisYet,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppColors.textSecondary,
                        ),
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

String _relative(AppLocalizations l10n, DateTime d) {
  final now = DateTime.now();
  final l = d
      .toLocal(); // backend timestamps are UTC; match _fmtDate's local day
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(l.year, l.month, l.day)).inDays;
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
