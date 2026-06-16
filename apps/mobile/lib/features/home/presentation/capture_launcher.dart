import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/hive_card.dart';
import '../../analyses/presentation/analysis_flow_args.dart';
import '../../hives/data/hive_dto.dart';
import '../../hives/presentation/hives_list_controller.dart';

/// Diagnosis-flow entry from the home FAB. Chooses which hive to photograph:
/// straight to the camera for a single hive, a picker sheet for several, or a
/// prompt to register one first when there are none.
Future<void> launchCapture(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final hives =
      ref.read(hivesListControllerProvider).asData?.value ?? const <Hive>[];

  if (hives.isEmpty) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.pickHiveEmpty)));
    return;
  }
  if (hives.length == 1) {
    _goCapture(context, hives.first);
    return;
  }

  final picked = await showModalBottomSheet<Hive>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (_) => _HivePickerSheet(hives: hives),
  );
  if (picked != null && context.mounted) _goCapture(context, picked);
}

void _goCapture(BuildContext context, Hive hive) {
  context.push(
    RoutePaths.capture,
    extra: CaptureArgs(hiveId: hive.id, hiveName: hive.name),
  );
}

class _HivePickerSheet extends StatelessWidget {
  const _HivePickerSheet({required this.hives});

  final List<Hive> hives;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          0,
          AppSpacing.screenH,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                l10n.pickHiveTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: hives.length,
                separatorBuilder: (_, _) => AppSpacing.gapSm,
                itemBuilder: (_, i) {
                  final h = hives[i];
                  return HiveCard(
                    name: h.name,
                    subtitle: (h.address != null && h.address!.isNotEmpty)
                        ? h.address
                        : null,
                    onTap: () => Navigator.of(context).pop(h),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
