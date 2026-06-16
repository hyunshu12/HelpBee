import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/hive_dto.dart';
import 'hive_detail_controller.dart';
import 'hives_list_controller.dart';

/// Detail view for one hive. Shows its fields and a delete action. Analysis
/// history is a later milestone (a coming-soon placeholder section here).
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
            child: Text(
              l10n.commonDelete,
              style: const TextStyle(color: AppColors.error),
            ),
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
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.deleteHive,
              onPressed: () => _confirmDelete(context, ref),
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
          data: (hive) => _HiveDetailBody(hive: hive),
        ),
      ),
    );
  }
}

class _HiveDetailBody extends StatelessWidget {
  const _HiveDetailBody({required this.hive});

  final Hive hive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final rows = <(String, String)>[
      (l10n.hiveNameLabel, hive.name),
      if (hive.address != null && hive.address!.isNotEmpty)
        (l10n.hiveAddressLabel, hive.address!),
      if (hive.hasLocation)
        (
          l10n.hiveLocationLabel,
          '${hive.latitude!.toStringAsFixed(6)}, '
              '${hive.longitude!.toStringAsFixed(6)}',
        ),
      if (hive.installedAt != null)
        (l10n.hiveInstalledAtLabel, _fmtDate(hive.installedAt!)),
      (l10n.hiveCreatedAtLabel, _fmtDate(hive.createdAt)),
      if (hive.note != null && hive.note!.isNotEmpty)
        (l10n.hiveNoteLabel, hive.note!),
    ];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenH),
      children: [
        ...rows.map((r) => _InfoRow(label: r.$1, value: r.$2)),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          l10n.hiveAnalysesSectionTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
        AppSpacing.gapSm,
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.science_outlined, color: AppColors.hintBorder),
              AppSpacing.wGapMd,
              Expanded(
                child: Text(
                  l10n.hiveAnalysesComingSoon,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          AppSpacing.gapXs,
          const Divider(height: 1, color: AppColors.divider),
        ],
      ),
    );
  }
}

/// Numeric `yyyy.MM.dd` (local). Avoids intl locale-symbol initialization.
String _fmtDate(DateTime d) {
  final l = d.toLocal();
  final mm = l.month.toString().padLeft(2, '0');
  final dd = l.day.toString().padLeft(2, '0');
  return '${l.year}.$mm.$dd';
}
