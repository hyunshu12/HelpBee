import '../data/auth_dto.dart';

/// Domain contract for authentication.
///
/// Implementations own token persistence (via the core `TokenStore`) and the
/// session-restore handshake. The presentation layer depends ONLY on this
/// interface, never on `data/`.
///
/// Every method throws an [AppException] on failure (the presentation layer
/// catches and maps it to a localized message).
abstract class AuthRepository {
  /// Creates an account and starts an authenticated session.
  /// On success the token pair is already persisted.
  Future<AuthSession> signup({
    required String email,
    required String password,
    required String name,
  });

  /// Authenticates with credentials and starts a session.
  /// On success the token pair is already persisted.
  Future<AuthSession> login({
    required String email,
    required String password,
  });

  /// Revokes the current refresh token server-side (best-effort) and clears
  /// all local tokens. Never throws for the local clear — a network failure on
  /// the server revoke still results in a cleared local session.
  Future<void> logout();

  /// Clears the local session (access + refresh) WITHOUT a server round-trip.
  /// Used when "로그인 상태 유지" is off so a non-persistent session is dropped
  /// on the next cold start.
  Future<void> forgetLocalSession();

  /// Fetches the current user + subscription. Requires a valid session.
  Future<MeResult> me();

  /// Attempts to silently restore a session on app launch using the persisted
  /// refresh token (single-flight refresh -> /me).
  ///
  /// Returns `true` if a valid session was restored, `false` otherwise
  /// (no refresh token, or refresh chain dead). Does not throw on the common
  /// "not logged in" path.
  Future<bool> tryRestoreSession();
}
