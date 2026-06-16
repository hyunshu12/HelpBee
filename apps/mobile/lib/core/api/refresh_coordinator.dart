import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../errors/error_code.dart';
import '../storage/token_store.dart';
import 'dio_client.dart';
import 'problem_details.dart';

/// Coordinates JWT refresh with **single-flight** semantics.
///
/// Backend contract §1.1:
/// - `POST /v1/auth/refresh { refreshToken }` returns a NEW `{ accessToken,
///   refreshToken, expiresIn }`; the old refresh is rotated out.
/// - Concurrent 401s must NOT fire multiple `/refresh` calls. Only one request
///   is in flight; concurrent callers await the same future. This is what makes
///   the server "grace" window work — losers reuse the winner's new access.
/// - If `/refresh` itself 401s (`AUTH_REFRESH_INVALID` /
///   `REFRESH_REUSE_DETECTED`), tokens are cleared and `null` is returned; the
///   caller flips the session to unauthenticated.
class RefreshCoordinator {
  RefreshCoordinator(this._ref);

  final Ref _ref;

  /// The in-flight refresh, if any. Single-flight gate.
  Future<String?>? _inFlight;

  /// Returns a fresh access token, or `null` if the refresh token is invalid
  /// (in which case tokens are already cleared).
  ///
  /// Safe to call from many places at once — they all await the same call.
  Future<String?> refresh() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _doRefresh();
    _inFlight = future;
    // Clear the gate once this attempt settles (success or failure).
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }

  Future<String?> _doRefresh() async {
    final tokenStore = _ref.read(tokenStoreProvider);
    final refreshToken = await tokenStore.readRefresh();
    if (refreshToken == null || refreshToken.isEmpty) {
      // Nothing to refresh with — treat as unauthenticated.
      await tokenStore.clear();
      return null;
    }

    final dio = _ref.read(bareDioProvider);
    try {
      final res = await dio.post<dynamic>(
        '${AppConfig.apiPrefix}/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = res.data;
      final data = body is Map && body['data'] is Map
          ? (body['data'] as Map)
          : body;
      if (data is! Map) {
        await tokenStore.clear();
        return null;
      }
      final access = data['accessToken'] as String?;
      final newRefresh = data['refreshToken'] as String?;
      if (access == null || newRefresh == null) {
        await tokenStore.clear();
        return null;
      }
      await tokenStore.saveTokens(access: access, refresh: newRefresh);
      return access;
    } on DioException catch (e) {
      final appEx = appExceptionFromDio(e);
      // Distinguish a genuinely dead refresh chain from a transient/edge 401.
      //
      // On the server's "grace" window a concurrent-refresh *loser* may reuse the
      // winner's new access. This client is STRICT single-flight (one /refresh in
      // flight; others await it), so within one app instance there is never a
      // loser — an explicit AUTH_REFRESH_INVALID / REUSE / UNAUTHORIZED here means
      // our refresh token is truly invalid, so we clear and force re-auth.
      if (appEx.code == ErrorCode.authRefreshInvalid ||
          appEx.code == ErrorCode.refreshReuseDetected ||
          appEx.code == ErrorCode.authUnauthorized) {
        await tokenStore.clear();
        return null;
      }
      // A *codeless* 401 (e.g. an edge proxy / gateway with no problem+json body)
      // is NOT a reliable signal that the refresh token is dead. Treat it (and
      // network/5xx) as transient: do NOT clear, so a still-valid token survives
      // for a later retry.
      throw appEx;
    }
  }
}

/// App-wide singleton refresh coordinator.
final refreshCoordinatorProvider =
    Provider<RefreshCoordinator>((ref) => RefreshCoordinator(ref));
