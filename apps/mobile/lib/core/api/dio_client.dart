import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'auth_interceptor.dart';
import 'logging_interceptor.dart';

/// Broadcasts "session expired" (refresh chain dead) to whoever listens —
/// typically the AuthController, which flips state to unauthenticated and the
/// router redirects to /login.
///
/// Exposed as a [ChangeNotifier] so the auth layer can `addListener` /
/// `ref.listen` without the api layer importing the auth feature.
class SessionExpiryNotifier extends ChangeNotifier {
  /// Fire once when the user's session can no longer be recovered.
  void trigger() => notifyListeners();
}

/// App-wide session-expiry bus. AuthController listens; AuthInterceptor fires.
final sessionExpiryProvider =
    Provider<SessionExpiryNotifier>((ref) => SessionExpiryNotifier());

const Duration _connectTimeout = Duration(seconds: 15);
const Duration _receiveTimeout = Duration(seconds: 30);
const Duration _sendTimeout = Duration(seconds: 30);

BaseOptions _baseOptions() => BaseOptions(
      baseUrl: AppConfig.apiBase,
      connectTimeout: _connectTimeout,
      receiveTimeout: _receiveTimeout,
      sendTimeout: _sendTimeout,
      headers: const {'Accept': 'application/json'},
      // Treat only 2xx/3xx as success. 4xx/5xx must throw a DioException so the
      // AuthInterceptor can see 401 AUTH_TOKEN_EXPIRED (refresh trigger) and
      // repositories receive a typed AppException. The problem+json body is
      // still parsed from `error.response.data`.
      validateStatus: (status) => status != null && status >= 200 && status < 300,
      responseType: ResponseType.json,
    );

/// Bare Dio with NO auth interceptor. Used by:
/// - [RefreshCoordinator] (the /refresh call must not loop through auth),
/// - [AuthInterceptor] retries (to avoid re-entering the interceptor),
/// - S3 presigned PUT uploads later (must send NO Authorization header).
final bareDioProvider = Provider<Dio>((ref) {
  final dio = Dio(_baseOptions());
  if (kDebugMode) {
    dio.interceptors.add(LoggingInterceptor());
  }
  return dio;
});

/// The authenticated Dio every feature/repository uses. Attaches
/// [AuthInterceptor] (bearer + x-request-id + refresh-on-401) and, in debug,
/// [LoggingInterceptor].
///
/// NEVER construct `Dio()` outside this file — always read this provider.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(_baseOptions());
  dio.interceptors.add(AuthInterceptor(ref));
  if (kDebugMode) {
    dio.interceptors.add(LoggingInterceptor());
  }
  return dio;
});
