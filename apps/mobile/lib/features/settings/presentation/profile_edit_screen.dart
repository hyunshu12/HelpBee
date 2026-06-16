import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_flow_state.dart';

/// 프로필 편집. The backend has no self-update endpoint yet
/// (`frontend-api-integration.md` §1 has no PATCH /me), so this currently
/// shows the account fields read-only; saving is a follow-up once the endpoint
/// exists.
class ProfileEditScreen extends ConsumerWidget {
  const ProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthFlowAuthenticated ? auth.user : null;

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: Text(l10n.profileEditTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenH),
          children: [
            _Field(label: l10n.fieldName, value: user?.name ?? '-'),
            _Field(label: l10n.fieldEmail, value: user?.email ?? '-'),
            _Field(
              label: l10n.fieldRole,
              value: user == null
                  ? '-'
                  : (user.isAdmin ? l10n.roleAdmin : l10n.roleUser),
            ),
            AppSpacing.gapLg,
            Text(
              l10n.profileSaveComingSoon,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

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
