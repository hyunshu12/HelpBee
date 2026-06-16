import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/error_code.dart';
import '../storage/token_store.dart';
import 'dio_client.dart';
import 'problem_details.dart';
import 'refresh_coordinator.dart';

/// Attaches auth on every request and transparently handles access-token
/// expiry with a single retry.
///
/// onRequest:
///  - `Authorization: Bearer <access>` when an access token is present.
///  - `x-request-id` for log correlation (best-effort; see [_RequestId]).
///
/// onError:
///  - If 401 with code `AUTH_TOKEN_EXPIRED` and the request hasn't been retried
///    yet -> single-flight [RefreshCoordinator.refresh].
///    - new access -> clone the original request with the new bearer and retry
///      ONCE (via [bareDioProvider], so this interceptor doesn't re-run).
///    - null (refresh dead) -> trigger [SessionExpiryNotifier] and reject.
///  - Any other error -> convert to [AppException] and reject so repositories
///    see a typed failure (not a raw DioException).
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._ref);

  final Ref _ref;

  /// Marker on `RequestOptions.extra` so we never retry the same request twice.
  static const String _retriedFlag = 'hb_retried';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final access = _ref.read(tokenStoreProvider).accessToken;
    if (access != null && access.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $access';
    }
    options.headers.putIfAbsent('x-request-id', _RequestId.next);
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final appEx = appExceptionFromDio(err);
    final alreadyRetried = err.requestOptions.extra[_retriedFlag] == true;

    final isExpired = appEx.code == ErrorCode.authTokenExpired;
    if (!isExpired || alreadyRetried) {
      // Not a refreshable case (or already attempted): surface typed error.
      handler.reject(_asAppError(err, appEx));
      return;
    }

    final String? newAccess;
    try {
      newAccess = await _ref.read(refreshCoordinatorProvider).refresh();
    } catch (refreshError) {
      // Transient refresh failure (network/5xx). Surface original error.
      handler.reject(_asAppError(err, appEx));
      return;
    }

    if (newAccess == null) {
      // Refresh chain is dead -> force re-auth.
      _ref.read(sessionExpiryProvider).trigger();
      handler.reject(_asAppError(err, appEx));
      return;
    }

    // Retry the original request once with the fresh access token, using the
    // bare Dio so this interceptor does not run again.
    try {
      final retried = await _retry(err.requestOptions, newAccess);
      handler.resolve(retried);
    } on DioException catch (retryErr) {
      handler.reject(_asAppError(retryErr, appExceptionFromDio(retryErr)));
    } catch (_) {
      handler.reject(_asAppError(err, appEx));
    }
  }

  Future<Response<dynamic>> _retry(
    RequestOptions options,
    String newAccess,
  ) {
    final bareDio = _ref.read(bareDioProvider);
    final headers = Map<String, dynamic>.from(options.headers)
      ..['Authorization'] = 'Bearer $newAccess';
    return bareDio.request<dynamic>(
      options.path,
      data: options.data,
      queryParameters: options.queryParameters,
      cancelToken: options.cancelToken,
      onReceiveProgress: options.onReceiveProgress,
      onSendProgress: options.onSendProgress,
      options: Options(
        method: options.method,
        headers: headers,
        responseType: options.responseType,
        contentType: options.contentType,
        sendTimeout: options.sendTimeout,
        receiveTimeout: options.receiveTimeout,
        followRedirects: options.followRedirects,
        validateStatus: options.validateStatus,
        receiveDataWhenStatusError: options.receiveDataWhenStatusError,
        extra: {...options.extra, _retriedFlag: true},
      ),
    );
  }

  /// Wraps the [AppException] inside the DioException's `error` slot so callers
  /// using Dio still receive a typed failure they can unwrap.
  DioException _asAppError(DioException original, Object appEx) {
    return original.copyWith(error: appEx);
  }
}

/// Tiny monotonic request-id generator (no `uuid` dependency).
///
/// Combines a base-36 launch timestamp with an incrementing counter. Not a
/// cryptographic UUID — purely for log correlation, which is best-effort.
class _RequestId {
  _RequestId._();

  static final String _prefix =
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  static int _counter = 0;

  static String next() => 'hb-$_prefix-${(_counter++).toRadixString(36)}';
}
