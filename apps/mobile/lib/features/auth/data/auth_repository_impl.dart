import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/api/refresh_coordinator.dart';
import '../../../core/config/app_config.dart';
import '../../../core/storage/token_store.dart';
import '../domain/auth_repository.dart';
import 'auth_api.dart';
import 'auth_dto.dart';

/// Default [AuthRepository] backed by [AuthApi] + the core token/refresh
/// infrastructure.
///
/// Persistence policy (backend contract §1.1):
/// - on signup/login success -> save the token pair (refresh in secure storage,
///   access in memory).
/// - on logout -> revoke server-side with the current refresh, then clear.
/// - on restore -> if a refresh exists, run the single-flight refresh; if it
///   yields an access token, confirm with `/me`.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._ref);

  final Ref _ref;

  AuthApi get _api => _ref.read(authApiProvider);
  TokenStore get _tokens => _ref.read(tokenStoreProvider);
  RefreshCoordinator get _refresher => _ref.read(refreshCoordinatorProvider);

  @override
  Future<AuthSession> signup({
    required String email,
    required String password,
    required String name,
  }) async {
    final session = await _api.signup(
      email: email,
      password: password,
      name: name,
    );
    await _persist(session);
    return session;
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final session = await _api.login(email: email, password: password);
    await _persist(session);
    return session;
  }

  @override
  Future<void> logout() async {
    final refresh = await _tokens.readRefresh();
    if (refresh != null && refresh.isNotEmpty) {
      try {
        // Revoke via the BARE dio (no auth-refresh interceptor). If the access
        // token is already expired, this 401s and is swallowed — we must NOT let
        // the interceptor rotate/re-persist a fresh token right before we clear.
        final access = _tokens.accessToken;
        await _ref.read(bareDioProvider).post<dynamic>(
          '${AppConfig.apiPrefix}/auth/logout',
          data: {'refreshToken': refresh},
          options: access != null
              ? Options(headers: {'Authorization': 'Bearer $access'})
              : null,
        );
      } catch (_) {
        // Server revoke is best-effort; always clear locally regardless.
      }
    }
    await _tokens.clear();
  }

  @override
  Future<void> forgetLocalSession() => _tokens.clear();

  @override
  Future<MeResult> me() => _api.me();

  @override
  Future<void> resendVerification() => _api.resendVerification();

  @override
  Future<bool> tryRestoreSession() async {
    final refresh = await _tokens.readRefresh();
    if (refresh == null || refresh.isEmpty) return false;

    // Single-flight refresh. Returns null (and clears tokens) if the refresh
    // chain is dead; throws only on transient (network/5xx) failures.
    final String? access;
    try {
      access = await _refresher.refresh();
    } catch (_) {
      // Transient failure on launch -> treat as not-restored without nuking
      // the (still valid) refresh token, so a later retry can succeed.
      return false;
    }
    if (access == null) return false;

    // Confirm the session is genuinely usable.
    try {
      await _api.me();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persist(AuthSession session) async {
    await _tokens.saveTokens(
      access: session.tokens.accessToken,
      refresh: session.tokens.refreshToken,
    );
  }
}

/// App-wide [AuthRepository] singleton.
final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepositoryImpl(ref));
