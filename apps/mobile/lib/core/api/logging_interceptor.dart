import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Debug-only request/response/error logger.
///
/// - No-op in release/profile builds ([kDebugMode] gate).
/// - Redacts the `Authorization` header and any token-bearing body fields
///   (`accessToken`, `refreshToken`, `password`) so secrets never hit logs.
/// - Bodies are capped at [_bodyCap] characters.
class LoggingInterceptor extends Interceptor {
  static const int _bodyCap = 2000;
  static const Set<String> _redactHeaders = {'authorization'};
  static const Set<String> _redactBodyKeys = {
    'accesstoken',
    'refreshtoken',
    'password',
    'uploadurl', // presigned URLs carry signing query params
  };

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      debugPrint('→ ${options.method} ${options.uri}');
      final headers = _redactedHeaders(options.headers);
      if (headers.isNotEmpty) debugPrint('  headers: $headers');
      final body = _redactedBody(options.data);
      if (body != null) debugPrint('  body: ${_cap(body)}');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      final req = response.requestOptions;
      debugPrint('← ${response.statusCode} ${req.method} ${req.uri}');
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      final req = err.requestOptions;
      debugPrint('✗ ${err.response?.statusCode ?? '-'} ${req.method} ${req.uri}'
          ' (${err.type.name})');
      final body = _redactedBody(err.response?.data);
      if (body != null) debugPrint('  error body: ${_cap(body)}');
    }
    handler.next(err);
  }

  Map<String, Object?> _redactedHeaders(Map<String, dynamic> headers) {
    final out = <String, Object?>{};
    headers.forEach((key, value) {
      out[key] =
          _redactHeaders.contains(key.toLowerCase()) ? '***' : value;
    });
    return out;
  }

  String? _redactedBody(Object? data) {
    if (data == null) return null;
    return _redact(data).toString();
  }

  /// Recursively redacts token-bearing keys at every depth so a nested payload
  /// (e.g. the `{ data: { accessToken, refreshToken } }` auth envelope, or a
  /// list of objects) never leaks a secret to the debug log.
  Object? _redact(Object? value) {
    if (value is Map) {
      return value.map((key, v) {
        final lower = key.toString().toLowerCase();
        return MapEntry(
          key.toString(),
          _redactBodyKeys.contains(lower) ? '***' : _redact(v),
        );
      });
    }
    if (value is List) {
      return value.map(_redact).toList();
    }
    return value;
  }

  String _cap(String s) =>
      s.length <= _bodyCap ? s : '${s.substring(0, _bodyCap)}…(truncated)';
}
