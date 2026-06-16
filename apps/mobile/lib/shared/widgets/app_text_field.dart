import 'package:flutter/material.dart';

import 'package:helpbee/core/theme/app_colors.dart';
import 'package:helpbee/l10n/app_localizations.dart';

/// HelpBee text field.
///
/// White background, [AppColors.hintBorder] 1px border, radius 12 (inherited
/// from [InputDecorationTheme]). Hint in [AppColors.hintBorder]. Optional label,
/// validator, obscure mode with a trailing visibility toggle. Touch height is
/// comfortably 48dp+ for elderly users.
///
/// When [suffixToggleObscure] is true (and [obscure] is true), a visibility
/// eye-toggle is shown that flips obscuring locally.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.validator,
    this.textInputAction,
    this.suffixToggleObscure = false,
    this.onChanged,
    this.onFieldSubmitted,
    this.enabled = true,
    this.autofillHints,
  });

  final TextEditingController? controller;
  final String? label;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;

  /// Show a trailing eye toggle to reveal/hide the obscured text.
  final bool suffixToggleObscure;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;
  final Iterable<String>? autofillHints;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.obscure;
  }

  @override
  void didUpdateWidget(covariant AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.obscure != widget.obscure) {
      _obscured = widget.obscure;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    Widget? suffix;
    if (widget.obscure && widget.suffixToggleObscure) {
      suffix = IconButton(
        // 48dp minimum touch target preserved by IconButton's default sizing.
        icon: Icon(
          _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: AppColors.hintBorder,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
        tooltip: _obscured ? l10n.showPassword : l10n.hidePassword,
      );
    }

    final Widget field = TextFormField(
      controller: widget.controller,
      obscureText: _obscured,
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
      enabled: widget.enabled,
      autofillHints: widget.autofillHints,
      style: theme.textTheme.bodyMedium,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        hintText: widget.hint,
        suffixIcon: suffix,
        constraints: const BoxConstraints(minHeight: 56),
      ),
    );

    if (widget.label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            widget.label!,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        field,
      ],
    );
  }
}
