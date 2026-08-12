import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/text/korean_wrap.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/empty_state.dart';

/// 진단 이력 탭. The backend's `GET /v1/analyses` is per-hive (requires
/// `hiveId`), so a global aggregated history is wired up in the analysis
/// milestone (Phase 3). For now this is the empty/placeholder state.
class AnalysisHistoryScreen extends ConsumerWidget {
  const AnalysisHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      body: SafeArea(
        child: EmptyState(
          icon: Icons.assignment_outlined,
          title: l10n.historyEmptyTitle,
          message: keepAll(l10n.historyEmptyBody),
        ),
      ),
      backgroundColor: AppColors.bgLight,
    );
  }
}
