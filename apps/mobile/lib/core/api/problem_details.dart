import 'package:dio/dio.dart';

import '../errors/app_exception.dart';
import '../errors/error_code.dart';

/// RFC 7807 `application/problem+json` error body returned by the backend.
///
/// ```jsonc
/// { "type", "title", "status", "code", "detail", "instance", "requestId" }
/// ```
///
/// The UI branches on [code] (string enum) via [ErrorCode]; [detail] is
/// internal English text and must never be shown to users.
class ProblemDetails {
  final String? type;
  final String? title;
  final int? status;
  final String? code;
  final String? detail;
  final String? instance;
  final String? requestId;

  const ProblemDetails({
    this.type,
    this.title,
    this.status,
    this.code,
    this.detail,
    this.instance,
    this.requestId,
  });

  /// Parses a decoded JSON map. Tolerates missing/odd fields.
  factory ProblemDetails.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'];
    return ProblemDetails(
      type: json['type'] as String?,
      title: json['title'] as String?,
      status: rawStatus is int
          ? rawStatus
          : (rawStatus is num ? rawStatus.toInt() : null),
      code: json['code'] as String?,
      detail: json['detail'] as String?,
      instance: json['instance'] as String?,
      requestId: json['requestId'] as String?,
    );
  }

  /// Attempts to build a [ProblemDetails] from an arbitrary response body.
  /// Returns null if the body is not a recognizable problem+json map.
  static ProblemDetails? tryParse(Object? body) {
    if (body is Map) {
      try {
        return ProblemDetails.fromJson(
          body.map((k, v) => MapEntry(k.toString(), v)),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Converts to the app's single exception type.
  ///
  /// [retryAfter] (parsed from the `Retry-After` header by the caller) is
  /// attached for 429 responses.
  AppException toAppException({Duration? retryAfter}) {
    return AppException(
      errorCodeFromWire(code),
      status: status,
      detail: detail,
      requestId: requestId,
      retryAfter: retryAfter,
    );
  }
}

/// Central Dio-error -> [AppException] conversion used by interceptors,
/// repositories and the refresh coordinator.
///
/// - timeouts -> [ErrorCode.timeout]
/// - connection/cancel/unknown transport -> [ErrorCode.network]
/// - bad response with problem+json body -> mapped via [ProblemDetails]
/// - bad response without a parseable body -> classified from HTTP status
AppException appExceptionFromDio(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return AppException.timeout();
    case DioExceptionType.connectionError:
    case DioExceptionType.cancel:
      return AppException.network();
    case DioExceptionType.badCertificate:
      return AppException.network();
    case DioExceptionType.unknown:
    case DioExceptionType.badResponse:
      final response = error.response;
      if (response == null) {
        return AppException.network();
      }
      final retryAfter = _parseRetryAfter(response.headers);
      final problem = ProblemDetails.tryParse(response.data);
      if (problem != null && problem.code != null) {
        return problem.toAppException(retryAfter: retryAfter);
      }
      return _fromStatus(
        response.statusCode,
        requestId: _headerValue(response.headers, 'x-request-id'),
        retryAfter: retryAfter,
      );
  }
}

AppException _fromStatus(
  int? status, {
  String? requestId,
  Duration? retryAfter,
}) {
  final ErrorCode code;
  switch (status) {
    case 400:
      code = ErrorCode.validationFailed;
      break;
    case 401:
      code = ErrorCode.authUnauthorized;
      break;
    case 403:
      // A bare 403 with no problem+json code (infra/proxy) — classify as an
      // auth/forbidden failure rather than falling through to `unknown`.
      code = ErrorCode.authUnauthorized;
      break;
    case 402:
      code = ErrorCode.quotaExceeded;
      break;
    case 404:
      code = ErrorCode.notFound;
      break;
    case 429:
      code = ErrorCode.rateLimited;
      break;
    case 503:
      code = ErrorCode.aiUnavailable;
      break;
    default:
      if (status != null && status >= 500) {
        code = ErrorCode.serverError;
      } else {
        code = ErrorCode.unknown;
      }
  }
  return AppException(
    code,
    status: status,
    requestId: requestId,
    retryAfter: retryAfter,
  );
}

Duration? _parseRetryAfter(Headers headers) {
  final raw = _headerValue(headers, 'retry-after');
  if (raw == null) return null;
  final seconds = int.tryParse(raw.trim());
  if (seconds != null) return Duration(seconds: seconds);
  // HTTP-date form is uncommon here; treat unparseable as absent.
  return null;
}

String? _headerValue(Headers headers, String name) {
  final values = headers.map[name] ?? headers.map[name.toLowerCase()];
  if (values == null || values.isEmpty) return null;
  return values.first;
}
