import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_client.dart';
import '../../../core/storage/app_prefs.dart';
import '../data/auth_repository_impl.dart';
import '../domain/auth_repository.dart';
import 'auth_flow_state.dart';

/// Owns the app's auth/navigation state and the bootstrap handshake.
///
/// Lifecycle:
/// 1. [build] returns [AuthFlowSplash] immediately and schedules [_bootstrap]
///    (we never `await` in build).
/// 2. [_bootstrap]:
///    - if onboarding not seen -> [AuthFlowOnboarding].
///    - else try silent restore -> [AuthFlowAuthenticated] or
///      [AuthFlowUnauthenticated].
/// 3. Listens to the core [sessionExpiryProvider] (refresh chain dead) and
///    flips to [AuthFlowUnauthenticated] so the router redirects to /login.
///
/// [login] / [signup] THROW [AppException] on failure (screens catch + map to
/// a localized message); on success they set [AuthFlowAuthenticated].
class AuthController extends Notifier<AuthFlowState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  AppPrefs get _prefs => ref.read(appPrefsProvider);

  @override
  AuthFlowState build() {
    // Bridge the core session-expiry bus (a ChangeNotifier) into this Notifier.
    final expiry = ref.read(sessionExpiryProvider);
    void onExpired() => _onSessionExpired();
    expiry.addListener(onExpired);
    ref.onDispose(() => expiry.removeListener(onExpired));

    // Kick off bootstrap without awaiting (build must be synchronous).
    Future.microtask(_bootstrap);
    return const AuthFlowState.splash();
  }

  Future<void> _bootstrap() async {
    try {
      final seenOnboarding = await _prefs.isOnboardingSeen();
      if (!seenOnboarding) {
        state = const AuthFlowState.onboarding();
        return;
      }
      await _restore();
    } catch (_) {
      // Fail open: a platform-channel throw (e.g. MissingPluginException on a
      // cold first run) must never strand the user on the splash screen.
      state = const AuthFlowState.unauthenticated();
    }
  }

  Future<void> _restore() async {
    // Honor "로그인 상태 유지". If the user opted out, do not silently restore
    // on cold start — forget the persisted session and require a fresh login.
    final keepLoggedIn = await _prefs.isKeepLoggedIn();
    if (!keepLoggedIn) {
      await _repo.forgetLocalSession();
      state = const AuthFlowState.unauthenticated();
      return;
    }

    bool restored = false;
    try {
      restored = await _repo.tryRestoreSession();
    } catch (_) {
      restored = false;
    }
    if (!restored) {
      state = const AuthFlowState.unauthenticated();
      return;
    }
    // Session is live — fetch the profile for the authenticated state.
    try {
      final me = await _repo.me();
      state = AuthFlowState.authenticated(me.user);
    } catch (_) {
      state = const AuthFlowState.unauthenticated();
    }
  }

  /// Marks onboarding complete and moves to the login gate.
  Future<void> completeOnboarding() async {
    try {
      await _prefs.setOnboardingSeen();
    } catch (_) {
      // Best-effort: even if the flag write fails, advance past onboarding.
    }
    state = const AuthFlowState.unauthenticated();
  }

  /// Authenticates. Persists "keep logged in". THROWS [AppException] on failure.
  Future<void> login({
    required String email,
    required String password,
    bool keepLoggedIn = true,
  }) async {
    await _prefs.setKeepLoggedIn(keepLoggedIn);
    final session = await _repo.login(email: email, password: password);
    state = AuthFlowState.authenticated(session.user);
  }

  /// Creates an account and signs in. THROWS [AppException] on failure.
  Future<void> signup({
    required String email,
    required String name,
    required String password,
  }) async {
    final session = await _repo.signup(
      email: email,
      password: password,
      name: name,
    );
    state = AuthFlowState.authenticated(session.user);
  }

  /// Signs out (server revoke best-effort + local clear) and returns to login.
  Future<void> logout() async {
    try {
      await _repo.logout();
    } finally {
      state = const AuthFlowState.unauthenticated();
    }
  }

  /// Fired when the core layer detects the refresh chain is dead.
  void _onSessionExpired() {
    // Only meaningful while authenticated; ignore during splash/onboarding.
    if (state is AuthFlowAuthenticated) {
      state = const AuthFlowState.unauthenticated();
    }
  }
}

/// App-wide auth controller. The router watches this for redirects.
final authControllerProvider =
    NotifierProvider<AuthController, AuthFlowState>(AuthController.new);
