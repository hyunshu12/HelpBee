import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/hive_dto.dart';
import 'hives_list_controller.dart';

/// Opens the "register a hive" bottom sheet. Resolves to the created [Hive] on
/// success, or `null` if dismissed.
Future<Hive?> showCreateHiveSheet(BuildContext context) {
  return showModalBottomSheet<Hive>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (_) => const _CreateHiveSheet(),
  );
}

/// Opens the create sheet and shows a success snackbar on creation. Shared by
/// the home FAB and the empty-state CTA so the "created" feedback is consistent.
Future<void> createHiveAndNotify(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final created = await showCreateHiveSheet(context);
  if (created != null && context.mounted) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.hiveCreated)));
  }
}

class _CreateHiveSheet extends ConsumerStatefulWidget {
  const _CreateHiveSheet();

  @override
  ConsumerState<_CreateHiveSheet> createState() => _CreateHiveSheetState();
}

class _CreateHiveSheetState extends ConsumerState<_CreateHiveSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();
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
      final created =
          await ref.read(hivesListControllerProvider.notifier).createHive(
                name: _nameController.text.trim(),
                address: _emptyToNull(_addressController.text),
                note: _emptyToNull(_noteController.text),
              );
      if (mounted) Navigator.of(context).pop(created);
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
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenH,
        right: AppSpacing.screenH,
        top: AppSpacing.sm,
        bottom: AppSpacing.lg + viewInsets,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.addHive,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            AppSpacing.gapLg,
            AppTextField(
              controller: _nameController,
              label: l10n.hiveNameLabel,
              hint: l10n.hiveNameHint,
              textInputAction: TextInputAction.next,
              validator: _validateName,
            ),
            AppSpacing.gapMd,
            AppTextField(
              controller: _addressController,
              label: l10n.hiveAddressLabel,
              hint: l10n.hiveAddressHint,
              textInputAction: TextInputAction.next,
            ),
            AppSpacing.gapMd,
            AppTextField(
              controller: _noteController,
              label: l10n.hiveNoteLabel,
              hint: l10n.hiveNoteHint,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
            ),
            AppSpacing.gapXl,
            PrimaryButton(
              label: l10n.createHive,
              loading: _submitting,
              onPressed: _submitting ? null : _submit,
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
