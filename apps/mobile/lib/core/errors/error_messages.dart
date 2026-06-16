import 'package:helpbee/l10n/app_localizations.dart';

import 'app_exception.dart';
import 'error_code.dart';

/// Generic, feature-agnostic error -> localized Korean message mapping.
///
/// Lives in `core` so any feature (hives, analyses, …) can turn an
/// [AppException] / [ErrorCode] into a user-safe message without importing
/// another feature. Never surfaces [AppException.detail] (internal English).
///
/// (The auth feature keeps its own `authErrorMessage` for historical reasons;
/// both share the same key set.)
String appErrorMessage(AppLocalizations l10n, Object error) {
  // Surface the server's Retry-After wait for lockout / rate-limit (429).
  if (error is AppException &&
      error.retryAfter != null &&
      (error.code == ErrorCode.authAccountLocked ||
          error.code == ErrorCode.rateLimited)) {
    return l10n.errRetryAfter(error.retryAfter!.inSeconds);
  }
  final code = error is AppException ? error.code : ErrorCode.unknown;
  return errorCodeMessage(l10n, code);
}

/// Pure [ErrorCode] -> localized message.
String errorCodeMessage(AppLocalizations l10n, ErrorCode code) {
  switch (code) {
    case ErrorCode.authInvalidCredentials:
    // Session-dead / authorization codes: the controller already redirects to
    // login; show a neutral message if one happens to surface.
    case ErrorCode.authTokenExpired:
    case ErrorCode.authUnauthorized:
    case ErrorCode.authRefreshInvalid:
    case ErrorCode.refreshReuseDetected:
      return l10n.errInvalidCredentials;
    case ErrorCode.authAccountLocked:
      return l10n.errAccountLocked;
    case ErrorCode.authEmailTaken:
      return l10n.errEmailTaken;
    case ErrorCode.authEmailNotVerified:
      return l10n.errEmailNotVerified;
    case ErrorCode.rateLimited:
      return l10n.errRateLimited;
    case ErrorCode.notFound:
      return l10n.errNotFound;
    case ErrorCode.quotaExceeded:
      return l10n.errQuota;
    case ErrorCode.validationFailed:
      return l10n.errValidation;
    case ErrorCode.aiUnavailable:
      return l10n.errAiUnavailable;
    case ErrorCode.serverError:
      return l10n.errServer;
    case ErrorCode.network:
      return l10n.errNetwork;
    case ErrorCode.timeout:
      return l10n.errTimeout;
    case ErrorCode.unknown:
      return l10n.errUnknown;
  }
}
