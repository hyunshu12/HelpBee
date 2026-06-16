import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../shared/widgets/secondary_button.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_flow_state.dart';
import '../../subscriptions/data/subscriptions_api.dart';

const String _appVersion = '1.0.0';

/// 설정 탭 — 계정 정보, 요금제/잔여 진단, 화면 테마, 앱 버전, 로그아웃.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.logout,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  String _planLabel(AppLocalizations l10n, String plan) => switch (plan) {
        'basic' => l10n.planBasic,
        'pro' => l10n.planPro,
        _ => l10n.planFree,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthFlowAuthenticated ? auth.user : null;
    final themeMode = ref.watch(themeModeControllerProvider);
    final sub = ref.watch(subscriptionMeProvider);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            // ── 계정 ──
            _SectionHeader(l10n.settingsAccountSection),
            _NavTile(
              leading: Icons.person_outline,
              title: user?.name ?? '-',
              subtitle: user?.email,
              onTap: () => context.push(RoutePaths.profileEdit),
            ),
            _InfoTile(
              label: l10n.fieldRole,
              value: user == null
                  ? '-'
                  : (user.isAdmin ? l10n.roleAdmin : l10n.roleUser),
            ),

            // ── 구독 ──
            _SectionHeader(l10n.settingsPlanSection),
            sub.when(
              loading: () => _InfoTile(label: l10n.planLabel, value: '…'),
              error: (_, _) => _InfoTile(label: l10n.planLabel, value: '-'),
              data: (s) => Column(
                children: [
                  _InfoTile(label: l10n.planLabel, value: _planLabel(l10n, s.plan)),
                  _InfoTile(
                    label: l10n.quotaRemaining,
                    value: s.isUnlimited
                        ? l10n.quotaUnlimited
                        : l10n.quotaCount(s.monthlyAnalysisQuota ?? 0),
                  ),
                ],
              ),
            ),

            // ── 앱 설정 ──
            _SectionHeader(l10n.settingsAppSection),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.xs,
                AppSpacing.screenH,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.themeMode,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  AppSpacing.gapXs,
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(l10n.themeSystem),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(l10n.themeLight),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(l10n.themeDark),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (selection) => ref
                        .read(themeModeControllerProvider.notifier)
                        .setMode(selection.first),
                  ),
                ],
              ),
            ),
            _InfoTile(label: l10n.appVersion, value: _appVersion),

            const SizedBox(height: AppSpacing.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: SecondaryButton(
                label: l10n.logout,
                onPressed: () => _confirmLogout(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.lg,
        AppSpacing.screenH,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.amberDeep,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.leading,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.xxs,
      ),
      leading: Icon(leading, color: AppColors.honeyBrand),
      title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right, color: AppColors.hintBorder),
      onTap: onTap,
    );
  }
}
