import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The single source of truth for auth tokens.
///
/// Policy (backend contract §1.1):
/// - **access** token: 15 min, **memory only** — never persisted.
/// - **refresh** token: 7 days, **secure storage only** (Keychain / Keystore).
///
/// Never store tokens in shared_preferences, hive, or plain files.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Android: force the EncryptedSharedPreferences backend (no plaintext
              // fallback on older API levels).
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              // iOS/macOS: keep the refresh token on THIS device only — excluded
              // from iCloud Keychain sync and device backups/restore.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const String _refreshKey = 'hb_refresh';

  final FlutterSecureStorage _storage;

  /// In-memory access token. Lost on app restart (by design) — restored via a
  /// refresh round-trip on launch.
  String? _accessToken;

  /// Current in-memory access token, or null if not authenticated.
  String? get accessToken => _accessToken;

  /// Replaces (or clears, with null) the in-memory access token.
  void setAccess(String? value) {
    _accessToken = value;
  }

  /// Reads the persisted refresh token from secure storage.
  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  /// Persists a fresh token pair: refresh -> secure storage, access -> memory.
  /// Called on login/signup success and on every successful refresh rotation.
  Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    _accessToken = access;
    await _storage.write(key: _refreshKey, value: refresh);
  }

  /// Wipes both tokens (logout / refresh-invalid / reuse-detected).
  Future<void> clear() async {
    _accessToken = null;
    await _storage.delete(key: _refreshKey);
  }
}

/// App-wide singleton. Override in tests with a fake [TokenStore].
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
