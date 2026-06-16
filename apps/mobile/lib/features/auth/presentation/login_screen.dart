import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/brand_wordmark.dart';
import '../../../shared/widgets/primary_button.dart';
import 'auth_controller.dart';
import 'auth_error_message.dart';
import 'auth_validators.dart';
import 'widgets/sns_login_row.dart';

/// Login gate. Email + password, a "keep logged in" checkbox, the primary CTA,
/// a links row (find id / find password / sign up), an SNS divider, and the
/// disabled SNS button row. On success [AuthController.login] flips the flow
/// state to authenticated and the router redirects to `/home`.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _keepLoggedIn = true;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_submitting) return;

    setState(() => _submitting = true);
    try {
      await ref.read(authControllerProvider.notifier).login(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            keepLoggedIn: _keepLoggedIn,
          );
      // On success the router redirect handles navigation to /home.
    } on AppException catch (e) {
      _showSnack(authErrorMessage(l10n, e));
    } catch (e) {
      _showSnack(authErrorMessage(l10n, e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenH,
            vertical: AppSpacing.xl,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSpacing.gapXxl,
                const Center(
                  child: BrandWordmark(size: 40, color: AppColors.honeyBrand),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                AppTextField(
                  controller: _emailController,
                  label: l10n.emailLabel,
                  hint: l10n.emailHint,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  validator: (v) => AuthValidators.email(l10n, v),
                ),
                AppSpacing.gapMd,
                AppTextField(
                  controller: _passwordController,
                  label: l10n.passwordLabel,
                  hint: l10n.passwordHint,
                  obscure: true,
                  suffixToggleObscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  validator: (v) => AuthValidators.loginPassword(l10n, v),
                  onFieldSubmitted: (_) => _submit(),
                ),
                AppSpacing.gapSm,
                _KeepLoggedInRow(
                  value: _keepLoggedIn,
                  onChanged: (v) => setState(() => _keepLoggedIn = v),
                  label: l10n.keepLoggedIn,
                ),
                AppSpacing.gapLg,
                PrimaryButton(
                  label: l10n.loginCta,
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
                AppSpacing.gapMd,
                _LinksRow(
                  findId: l10n.findId,
                  findPassword: l10n.findPassword,
                  signupLink: l10n.signupLink,
                  onFindId: () => _showSnack(l10n.comingSoon),
                  onFindPassword: () => _showSnack(l10n.comingSoon),
                  onSignup: () => context.go(RoutePaths.signup),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                _DividerLabel(label: l10n.snsDivider),
                AppSpacing.gapLg,
                SnsLoginRow(onTapDisabled: () => _showSnack(l10n.comingSoon)),
                AppSpacing.gapXl,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Keep logged in" checkbox + label as a single 56dp tappable row.
class _KeepLoggedInRow extends StatelessWidget {
  const _KeepLoggedInRow({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            AppSpacing.wGapSm,
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline links row: find-id | find-password | sign-up.
class _LinksRow extends StatelessWidget {
  const _LinksRow({
    required this.findId,
    required this.findPassword,
    required this.signupLink,
    required this.onFindId,
    required this.onFindPassword,
    required this.onSignup,
  });

  final String findId;
  final String findPassword;
  final String signupLink;
  final VoidCallback onFindId;
  final VoidCallback onFindPassword;
  final VoidCallback onSignup;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LinkText(label: findId, onTap: onFindId),
        const _LinkDivider(),
        _LinkText(label: findPassword, onTap: onFindPassword),
        const _LinkDivider(),
        _LinkText(label: signupLink, onTap: onSignup),
      ],
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
      ),
    );
  }
}

class _LinkDivider extends StatelessWidget {
  const _LinkDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      color: AppColors.divider,
    );
  }
}

/// A centered label flanked by two thin divider lines.
class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.divider, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.divider, thickness: 1)),
      ],
    );
  }
}
