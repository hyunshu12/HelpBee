import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../hives/presentation/hive_form_screen.dart';
import '../../hives/presentation/hives_list_view.dart';
import '../../subscriptions/presentation/quota_banner.dart';
import 'capture_launcher.dart';

/// Signed-in home (Figma "양봉장 현황"): app bar with add-hive (+), free-tier
/// quota banner, the hive summary list, and the 진단하기 (capture) FAB.
///
/// Shell screen — composes the `hives` list and `subscriptions` quota banner.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        titleSpacing: 20,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 28),
            tooltip: l10n.addHive,
            onPressed: () => createHiveAndNotify(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => launchCapture(context, ref),
        backgroundColor: AppColors.honeyPrimary,
        foregroundColor: AppColors.textPrimary,
        icon: const Icon(Icons.camera_alt),
        label: Text(l10n.captureCta),
      ),
      body: SafeArea(
        child: Column(
          children: const [
            QuotaBanner(),
            Expanded(child: HivesListView()),
          ],
        ),
      ),
    );
  }
}
