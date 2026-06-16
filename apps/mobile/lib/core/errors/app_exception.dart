import 'error_code.dart';

/// The single exception type the presentation layer ever sees.
///
/// Repositories / interceptors convert raw [Object] failures (DioException,
/// SocketException, parse errors, problem+json bodies) into an [AppException].
/// Screens branch on [code] and map it to a localized Korean message — they
/// must NOT surface [detail] (it is internal English text).
class AppException implements Exception {
  /// Canonical, transport-agnostic error category.
  final ErrorCode code;

  /// HTTP status if it originated from a response (null for transport errors).
  final int? status;

  /// Server `detail` (problem+json). For logging/debugging only — never shown
  /// to users.
  final String? detail;

  /// `x-request-id` echoed by the server (for support/log correlation).
  final String? requestId;

  /// `Retry-After` duration for 429 responses, when the server provided it.
  final Duration? retryAfter;

  const AppException(
    this.code, {
    this.status,
    this.detail,
    this.requestId,
    this.retryAfter,
  });

  /// No connectivity / DNS / connection refused / cancelled, etc.
  factory AppException.network() => const AppException(ErrorCode.network);

  /// Connect/receive/send timeout.
  factory AppException.timeout() => const AppException(ErrorCode.timeout);

  /// Anything we could not classify.
  factory AppException.unknown([String? detail]) =>
      AppException(ErrorCode.unknown, detail: detail);

  @override
  String toString() =>
      'AppException(code: $code, status: $status, requestId: $requestId, '
      'retryAfter: $retryAfter, detail: $detail)';
}
