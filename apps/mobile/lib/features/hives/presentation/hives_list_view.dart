import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/hive_card.dart';
import '../data/hive_dto.dart';
import 'create_hive_sheet.dart';
import 'hives_list_controller.dart';

/// Renders the signed-in user's hive list — loading / error / empty / list —
/// with pull-to-refresh and navigation to each hive's detail. Hosted by the
/// HomeScreen shell so the hives feature owns its own list rendering.
class HivesListView extends ConsumerWidget {
  const HivesListView({super.key});

  String _subtitleFor(Hive hive) {
    if (hive.address != null && hive.address!.isNotEmpty) return hive.address!;
    if (hive.hasLocation) {
      return '${hive.latitude!.toStringAsFixed(4)}, '
          '${hive.longitude!.toStringAsFixed(4)}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hives = ref.watch(hivesListControllerProvider);

    return hives.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: l10n.hivesErrorTitle,
        message: appErrorMessage(l10n, error),
        actionLabel: l10n.commonRetry,
        onAction: () =>
            ref.read(hivesListControllerProvider.notifier).refresh(),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.hive_outlined,
            title: l10n.hivesEmptyTitle,
            message: l10n.hivesEmptyBody,
            actionLabel: l10n.addHive,
            onAction: () => createHiveAndNotify(context),
          );
        }
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(hivesListControllerProvider.notifier).refresh(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.md,
              AppSpacing.screenH,
              96, // room for the extended FAB
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => AppSpacing.gapSm,
            itemBuilder: (context, index) {
              final hive = items[index];
              return HiveCard(
                name: hive.name,
                subtitle: _subtitleFor(hive),
                onTap: () => context.push(RoutePaths.hiveDetailTo(hive.id)),
              );
            },
          ),
        );
      },
    );
  }
}
