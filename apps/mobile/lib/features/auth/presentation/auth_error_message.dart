import 'package:helpbee/l10n/app_localizations.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_code.dart';

/// Maps any auth-flow failure to a localized, user-safe Korean message.
///
/// Screens call this in their `catch` block:
/// ```dart
/// catch (e) {
///   showError(authErrorMessage(AppLocalizations.of(context), e));
/// }
/// ```
///
/// - Never surfaces `AppException.detail` (internal English).
/// - Unrecognized errors fall back to [AppLocalizations.errUnknown].
String authErrorMessage(AppLocalizations l10n, Object error) {
  // Surface the server's Retry-After wait time for lockout / rate-limit (429).
  if (error is AppException &&
      error.retryAfter != null &&
      (error.code == ErrorCode.authAccountLocked ||
          error.code == ErrorCode.rateLimited)) {
    return l10n.errRetryAfter(error.retryAfter!.inSeconds);
  }
  final code = _resolveCode(error);
  return errorCodeMessage(l10n, code);
}

/// Pure [ErrorCode] -> localized message mapping (reusable by any screen).
String errorCodeMessage(AppLocalizations l10n, ErrorCode code) {
  switch (code) {
    case ErrorCode.authInvalidCredentials:
      return l10n.errInvalidCredentials;
    case ErrorCode.authAccountLocked:
      return l10n.errAccountLocked;
    case ErrorCode.authEmailTaken:
      return l10n.errEmailTaken;
    case ErrorCode.authEmailNotVerified:
      return l10n.errEmailNotVerified;
    case ErrorCode.rateLimited:
      return l10n.errRateLimited;
    case ErrorCode.network:
      return l10n.errNetwork;
    case ErrorCode.timeout:
      return l10n.errTimeout;
    // Session-dead / authorization codes: the controller already redirects to
    // login; show a neutral credentials message if one happens to surface.
    case ErrorCode.authTokenExpired:
    case ErrorCode.authUnauthorized:
    case ErrorCode.authRefreshInvalid:
    case ErrorCode.refreshReuseDetected:
      return l10n.errInvalidCredentials;
    // Backend faults.
    case ErrorCode.serverError:
      return l10n.errServer;
    // Input rejected by the backend (e.g. password composition).
    case ErrorCode.validationFailed:
      return l10n.errValidation;
    // Not expected on the auth path, but map to something sensible.
    case ErrorCode.notFound:
    case ErrorCode.quotaExceeded:
    case ErrorCode.aiUnavailable:
    case ErrorCode.unknown:
      return l10n.errUnknown;
  }
}

/// Extracts an [ErrorCode] from an arbitrary thrown object.
ErrorCode _resolveCode(Object error) {
  if (error is AppException) return error.code;
  return ErrorCode.unknown;
}
