import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_flow_state.dart';
import '../../hives/presentation/create_hive_sheet.dart';
import '../../hives/presentation/hives_list_view.dart';

/// Signed-in home shell (Figma "홈: 벌통 리스트 + FAB").
///
/// Composition root for the authenticated landing screen: it owns the Scaffold,
/// the greeting/logout AppBar, the add-hive FAB, and hosts the hives feature's
/// [HivesListView] in its body.
///
/// The cross-feature imports here are the documented, accepted exceptions
/// (CLAUDE.md §18.1): home is a *shell* that composes the `auth` session
/// (greeting/logout) and the `hives` list — it deliberately does NOT reach into
/// another feature's data layer (the list view owns that).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider);

    final String title = auth is AuthFlowAuthenticated
        ? l10n.homeGreeting(auth.user.name)
        : l10n.homeTitle;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => createHiveAndNotify(context),
        backgroundColor: AppColors.honeyPrimary,
        foregroundColor: AppColors.textPrimary,
        icon: const Icon(Icons.add),
        label: Text(l10n.addHive),
      ),
      body: const SafeArea(child: HivesListView()),
    );
  }
}
