import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/routing/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/hive_dto.dart';
import 'hives_list_controller.dart';

/// Pushes the full-screen hive register form and shows a success snackbar on
/// creation. Shared by the home (+) action and the empty-state CTA so the
/// "created" feedback is consistent.
Future<void> createHiveAndNotify(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final created = await context.push<Hive>(RoutePaths.hiveCreate);
  if (created != null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.hiveCreated)));
  }
}

/// 벌통 등록 (Figma 15:2): full-screen form — name* / location (+GPS) /
/// installed-date* / memo, with a decorative hero banner and the 등록하기 CTA.
/// Pops the created [Hive] on success.
class CreateHiveScreen extends ConsumerStatefulWidget {
  const CreateHiveScreen({super.key});

  @override
  ConsumerState<CreateHiveScreen> createState() => _CreateHiveScreenState();
}

class _CreateHiveScreenState extends ConsumerState<CreateHiveScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _installedAt;
  bool _dateError = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    final l10n = AppLocalizations.of(context);
    if (v == null || v.trim().isEmpty) return l10n.valRequired;
    return null;
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _installedAt ?? now,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _installedAt = picked;
        _dateError = false;
      });
    }
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
    final nameOk = _formKey.currentState?.validate() ?? false;
    final dateOk = _installedAt != null;
    if (!dateOk) setState(() => _dateError = true);
    if (!nameOk || !dateOk || _submitting) return;

    setState(() => _submitting = true);
    try {
      final created =
          await ref.read(hivesListControllerProvider.notifier).createHive(
                name: _nameController.text.trim(),
                address: _emptyToNull(_addressController.text),
                note: _emptyToNull(_noteController.text),
                installedAt: _installedAt,
              );
      if (mounted) context.pop(created);
    } on AppException catch (e) {
      _showSnack(appErrorMessage(l10n, e));
      if (mounted) setState(() => _submitting = false);
    } catch (e) {
      _showSnack(appErrorMessage(l10n, e));
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: AppColors.bgLight,
        title: Text(l10n.addHive),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.screenH,
                      AppSpacing.md, AppSpacing.screenH, AppSpacing.lg),
                  children: [
                    const _HeroBanner(),
                    AppSpacing.gapLg,
                    _FieldLabel(l10n.hiveNameLabel, required: true),
                    AppSpacing.gapXs,
                    AppTextField(
                      controller: _nameController,
                      hint: l10n.hiveNamePlaceholder,
                      textInputAction: TextInputAction.next,
                      validator: _validateName,
                    ),
                    AppSpacing.gapLg,
                    _FieldLabel(l10n.hiveLocationCard),
                    AppSpacing.gapXs,
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _addressController,
                            hint: l10n.hiveLocationHint,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        AppSpacing.wGapSm,
                        _GpsButton(onTap: () => _showSnack(l10n.comingSoon)),
                      ],
                    ),
                    AppSpacing.gapLg,
                    _FieldLabel(l10n.hiveInstalledAtLabel, required: true),
                    AppSpacing.gapXs,
                    _DateField(
                      value: _installedAt,
                      hint: l10n.hiveInstalledHint,
                      errorText: _dateError ? l10n.installDateRequired : null,
                      onTap: _pickDate,
                    ),
                    AppSpacing.gapLg,
                    _FieldLabel(l10n.memoTitle),
                    AppSpacing.gapXs,
                    TextFormField(
                      controller: _noteController,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: l10n.hiveNotePlaceholder,
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screenH,
                  AppSpacing.xs, AppSpacing.screenH, AppSpacing.md),
              child: PrimaryButton(
                label: l10n.createHive,
                loading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _emptyToNull(String v) {
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Decorative honey banner (no real asset yet — see follow-up).
class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          borderRadius: AppRadius.cardRadius,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.honeyLight, AppColors.honeyPrimary],
          ),
        ),
        child: const Center(
          child: Icon(Icons.hive_outlined, size: 56, color: AppColors.amberDeep),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        );
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text.rich(
        TextSpan(
          text: text,
          style: style,
          children: required
              ? [
                  TextSpan(
                    text: ' *',
                    style: style?.copyWith(color: AppColors.error),
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

class _GpsButton extends StatelessWidget {
  const _GpsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).useCurrentLocationA11y,
      child: Material(
        color: AppColors.honeyPrimary,
        borderRadius: AppRadius.inputRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(Icons.my_location, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.hint,
    required this.onTap,
    this.errorText,
  });

  final DateTime? value;
  final String hint;
  final String? errorText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value != null;
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).pickDateA11y,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.inputRadius,
        child: InputDecorator(
          decoration: InputDecoration(
            errorText: errorText,
            suffixIcon: const Icon(Icons.calendar_month_outlined,
                color: AppColors.hintBorder),
            constraints: const BoxConstraints(minHeight: 56),
          ),
          child: Text(
            hasValue ? _fmtDate(value!) : hint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: hasValue ? AppColors.textPrimary : AppColors.hintBorder,
            ),
          ),
        ),
      ),
    );
  }
}

String _fmtDate(DateTime d) {
  final l = d.toLocal();
  final mm = l.month.toString().padLeft(2, '0');
  final dd = l.day.toString().padLeft(2, '0');
  return '${l.year}.$mm.$dd';
}
