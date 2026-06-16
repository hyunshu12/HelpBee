/// Canonical, transport-agnostic error taxonomy for the app.
///
/// The backend returns RFC 7807 `problem+json` with a string `code`
/// (e.g. `"AUTH_INVALID_CREDENTIALS"`). The UI must branch on the *enum*,
/// never on the wire string, and never show the server `detail` to users.
///
/// Wire mapping is centralized in [errorCodeFromWire]. Add a new wire code in
/// exactly two places: the enum and the switch below.
enum ErrorCode {
  // --- auth ---
  authInvalidCredentials,
  authAccountLocked,
  authEmailTaken,
  authTokenExpired,
  authUnauthorized,
  authRefreshInvalid,
  refreshReuseDetected,
  authEmailNotVerified,
  // --- cross-cutting (backend) ---
  rateLimited,
  validationFailed,
  notFound,
  quotaExceeded,
  aiUnavailable,
  serverError,
  // --- transport / client-side ---
  network,
  timeout,
  unknown,
}

/// Maps a backend `code` string (problem+json) to [ErrorCode].
///
/// Unknown or null inputs fall back to [ErrorCode.unknown] so the app never
/// crashes on a server code it hasn't seen yet.
ErrorCode errorCodeFromWire(String? wire) {
  switch (wire) {
    case 'AUTH_INVALID_CREDENTIALS':
      return ErrorCode.authInvalidCredentials;
    case 'AUTH_ACCOUNT_LOCKED':
      return ErrorCode.authAccountLocked;
    case 'AUTH_EMAIL_TAKEN':
      return ErrorCode.authEmailTaken;
    case 'AUTH_TOKEN_EXPIRED':
      return ErrorCode.authTokenExpired;
    case 'AUTH_UNAUTHORIZED':
      return ErrorCode.authUnauthorized;
    case 'AUTH_REFRESH_INVALID':
      return ErrorCode.authRefreshInvalid;
    case 'REFRESH_REUSE_DETECTED':
      return ErrorCode.refreshReuseDetected;
    case 'AUTH_EMAIL_NOT_VERIFIED':
      return ErrorCode.authEmailNotVerified;
    case 'RATE_LIMITED':
      return ErrorCode.rateLimited;
    case 'VALIDATION_FAILED':
      return ErrorCode.validationFailed;
    case 'NOT_FOUND':
      return ErrorCode.notFound;
    case 'QUOTA_EXCEEDED':
      return ErrorCode.quotaExceeded;
    case 'AI_UNAVAILABLE':
      return ErrorCode.aiUnavailable;
    case 'INTERNAL':
    case 'SERVER_ERROR':
      return ErrorCode.serverError;
    default:
      return ErrorCode.unknown;
  }
}
