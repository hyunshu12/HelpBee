import 'package:helpbee/l10n/app_localizations.dart';

/// Client-side form validators for the auth screens. They return a localized
/// error string (to display under the field) or `null` when valid.
///
/// Kept deliberately lenient — the backend is the source of truth; these only
/// catch obvious mistakes before a network round-trip.
class AuthValidators {
  const AuthValidators._();

  /// Minimum password length enforced by the backend (signup: 10..128).
  static const int minPasswordLength = 10;

  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Required, well-formed email.
  static String? email(AppLocalizations l10n, String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return l10n.valRequired;
    if (!_emailRe.hasMatch(v)) return l10n.valEmail;
    return null;
  }

  /// Login password: just required (length rules are a signup concern).
  static String? loginPassword(AppLocalizations l10n, String? value) {
    if ((value ?? '').isEmpty) return l10n.valRequired;
    return null;
  }

  /// Signup password: required + minimum length.
  static String? signupPassword(AppLocalizations l10n, String? value) {
    final v = value ?? '';
    if (v.isEmpty) return l10n.valRequired;
    if (v.length < minPasswordLength) return l10n.valPasswordLen;
    return null;
  }

  /// Generic required text (used for name).
  static String? required(AppLocalizations l10n, String? value) {
    if ((value ?? '').trim().isEmpty) return l10n.valRequired;
    return null;
  }

  /// Password confirmation must match [original].
  static String? confirm(AppLocalizations l10n, String? value, String original) {
    if ((value ?? '').isEmpty) return l10n.valRequired;
    if (value != original) return l10n.passwordMismatch;
    return null;
  }
}
