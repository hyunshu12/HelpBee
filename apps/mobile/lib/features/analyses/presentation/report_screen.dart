import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/risk/recommendations.dart';
import '../../../core/risk/risk_tier.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/risk_gauge.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../data/analysis_dto.dart';
import 'analysis_flow_args.dart';

/// 레포트 (Figma 24:12): the diagnosis result. Risk gauge + tier title +
/// analyzed-photo card + recommended actions. Recommendations come from the
/// backend (`analysis.recommendations`, with per-item severity); when absent
/// (e.g. a list-sourced row that omits them) we fall back to client-side,
/// tier-based copy. A `failed` analysis shows a graceful "couldn't finish"
/// state instead of a score.
class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key, required this.args});

  final ReportArgs args;

  Analysis get _a => args.analysis;

  /// Backend recommendations (with severity) when present; otherwise fall back
  /// to client-side tier copy so list-sourced rows (which omit them) still show
  /// guidance. Severity for the fallback is derived from the tier.
  List<RecommendationDto> _recommendations(AppLocalizations l10n, RiskTier tier) {
    if (_a.recommendations.isNotEmpty) return _a.recommendations;
    final severity = _severityForTier(tier);
    final copy = recommendationsFor(l10n, tier);
    return [
      for (var i = 0; i < copy.length; i++)
        RecommendationDto(order: i, content: copy[i], severity: severity),
    ];
  }

  void _toHome(BuildContext context) => context.go(RoutePaths.home);

  void _saveToHistory(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // The analysis is already persisted on creation; land on the hive detail
    // (timeline) and confirm. go(home)+push(detail) leaves home underneath.
    context.go(RoutePaths.home);
    context.push(RoutePaths.hiveDetailTo(_a.hiveId));
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.reportSavedSnack)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final success = _a.isSuccess;
    final tier = _a.tier;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toHome(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.bgLight,
        appBar: AppBar(
          backgroundColor: AppColors.bgLight,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.captureCloseA11y,
            onPressed: () => _toHome(context),
          ),
          title: Text(l10n.reportTitle),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: l10n.reportShareA11y,
              onPressed: () => ScaffoldMessenger.of(context)
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text(l10n.comingSoon))),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    AppSpacing.lg,
                    AppSpacing.screenH,
                    AppSpacing.lg,
                  ),
                  children: [
                    Center(
                      child: RiskGauge(
                        score: success ? _a.varroaInfectionRisk : null,
                        tier: tier,
                        caption: gaugeCaption(l10n, tier),
                      ),
                    ),
                    AppSpacing.gapLg,
                    Text(
                      success
                          ? l10n.reportRiskStageTitle
                          : l10n.analyzingFailedTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AppSpacing.gapLg,
                    _PhotoCard(
                      imagePath: args.imagePath,
                      hiveName: args.hiveName,
                      whenLabel: _whenLabel(l10n, _a),
                    ),
                    AppSpacing.gapMd,
                    if (success && tier != RiskTier.unknown)
                      _RecommendationsCard(items: _recommendations(l10n, tier))
                    else
                      _FailedNoticeCard(message: l10n.errAiUnavailable),
                  ],
                ),
              ),
              _BottomBar(
                onHome: () => _toHome(context),
                onSave: () => _saveToHistory(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.imagePath,
    required this.hiveName,
    required this.whenLabel,
  });

  final String? imagePath;
  final String hiveName;
  final String whenLabel;

  void _openViewer(BuildContext context) {
    if (imagePath == null) return;
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: Semantics(
                  image: true,
                  label: l10n.reportAnalyzedPhoto,
                  child: Image.file(File(imagePath!), fit: BoxFit.contain),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: l10n.captureCloseA11y,
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return _Card(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppRadius.inputRadius,
            child: SizedBox(
              width: 56,
              height: 56,
              child: imagePath != null
                  ? Semantics(
                      image: true,
                      label: l10n.reportAnalyzedPhoto,
                      child: Image.file(File(imagePath!), fit: BoxFit.cover),
                    )
                  : Container(
                      color: AppColors.honeyLight.withValues(alpha: 0.4),
                      child: const Icon(
                        Icons.image_outlined,
                        color: AppColors.amberDeep,
                      ),
                    ),
            ),
          ),
          AppSpacing.wGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.reportAnalyzedPhoto,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$whenLabel\n$hiveName',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (imagePath != null)
            IconButton(
              icon: const Icon(Icons.zoom_in, color: AppColors.textSecondary),
              tooltip: l10n.reportAnalyzedPhoto,
              onPressed: () => _openViewer(context),
            ),
        ],
      ),
    );
  }
}

/// Severity ('info'|'warn'|'danger') → tier color token. Unknown → safe.
Color _severityColor(String severity) => switch (severity) {
  'danger' => AppColors.tierDanger,
  'warn' => AppColors.tierWatch,
  _ => AppColors.tierSafe,
};

/// Fallback severity when copy is client-side tier-based (no backend severity).
String _severityForTier(RiskTier tier) => switch (tier) {
  RiskTier.danger => 'danger',
  RiskTier.watch => 'warn',
  _ => 'info',
};

class _RecommendationsCard extends StatelessWidget {
  const _RecommendationsCard({required this.items});

  final List<RecommendationDto> items;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.tierDanger,
                size: 22,
              ),
              AppSpacing.wGapXs,
              Text(
                l10n.reportRecommendTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          AppSpacing.gapMd,
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _severityColor(
                        items[i].severity,
                      ).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: _severityColor(items[i].severity),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AppSpacing.wGapSm,
                  Expanded(
                    child: Text(
                      items[i].content,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Text(
            l10n.reportRecommendDisclaimer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.hintBorder,
            ),
          ),
        ],
      ),
    );
  }
}

class _FailedNoticeCard extends StatelessWidget {
  const _FailedNoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.tierWatch),
          AppSpacing.wGapSm,
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onHome, required this.onSave});

  final VoidCallback onHome;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.sm,
        AppSpacing.screenH,
        AppSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.bgLight,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SecondaryButton(label: l10n.reportHome, onPressed: onHome),
          ),
          AppSpacing.wGapMd,
          Expanded(
            flex: 2,
            child: PrimaryButton(
              label: l10n.reportSaveToHistory,
              onPressed: onSave,
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

/// "오늘 오전 10:45" style label from the analysis time (UTC → local).
String _whenLabel(AppLocalizations l10n, Analysis a) {
  final t = (a.analyzedAt ?? a.createdAt).toLocal();
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(t.year, t.month, t.day)).inDays;
  final String day = days <= 0
      ? l10n.today
      : (days == 1 ? l10n.yesterday : l10n.daysAgo(days));
  final bool am = t.hour < 12;
  final int h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final String mm = t.minute.toString().padLeft(2, '0');
  return '$day ${am ? l10n.am : l10n.pm} $h12:$mm';
}
