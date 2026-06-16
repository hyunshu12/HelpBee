import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import 'auth_controller.dart';
import 'auth_error_message.dart';
import 'auth_validators.dart';

/// Sign-up form: email, name, password (+rule hint), confirm. Validates locally
/// then calls [AuthController.signup]; on success the flow state flips to
/// authenticated and the router redirects to `/home`.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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
      await ref.read(authControllerProvider.notifier).signup(
            email: _emailController.text.trim(),
            name: _nameController.text.trim(),
            password: _passwordController.text,
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
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RoutePaths.login);
            }
          },
        ),
        title: Text(l10n.signupTitle),
      ),
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
                AppTextField(
                  controller: _emailController,
                  label: l10n.emailLabel,
                  hint: l10n.emailHint,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: (v) => AuthValidators.email(l10n, v),
                ),
                AppSpacing.gapMd,
                AppTextField(
                  controller: _nameController,
                  label: l10n.nameLabel,
                  hint: l10n.nameHint,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  validator: (v) => AuthValidators.required(l10n, v),
                ),
                AppSpacing.gapMd,
                AppTextField(
                  controller: _passwordController,
                  label: l10n.passwordLabel,
                  hint: l10n.passwordRuleHint,
                  obscure: true,
                  suffixToggleObscure: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) => AuthValidators.signupPassword(l10n, v),
                ),
                AppSpacing.gapMd,
                AppTextField(
                  controller: _confirmController,
                  label: l10n.passwordConfirmLabel,
                  hint: l10n.passwordConfirmHint,
                  obscure: true,
                  suffixToggleObscure: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) =>
                      AuthValidators.confirm(l10n, v, _passwordController.text),
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                PrimaryButton(
                  label: l10n.signupCta,
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
                AppSpacing.gapLg,
                _HaveAccountRow(
                  question: l10n.haveAccount,
                  action: l10n.goLogin,
                  onTap: () => context.go(RoutePaths.login),
                ),
                AppSpacing.gapXl,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HaveAccountRow extends StatelessWidget {
  const _HaveAccountRow({
    required this.question,
    required this.action,
    required this.onTap,
  });

  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          question,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            action,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.amberDeep,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
