/// Compile-time configuration for the app.
///
/// `API_BASE` is injected via `--dart-define=API_BASE=...`.
/// Default is the local backend (`http://localhost:3001`). For the Android
/// emulator use `--dart-define=API_BASE=http://10.0.2.2:3001`.
///
/// All business endpoints live under [apiPrefix] (`/v1`). The bare `/health`
/// endpoint (no prefix) is the only exception and is not used by this layer.
class AppConfig {
  const AppConfig._();

  /// Backend base URL (no trailing slash, no `/v1`).
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:3001',
  );

  /// Version prefix for every business route.
  static const String apiPrefix = '/v1';

  /// Convenience: fully qualified `/v1` base. Dio's [baseUrl] is [apiBase];
  /// route strings include the prefix (e.g. `/v1/auth/login`), so this is only
  /// here for callers that want the combined value.
  static const String apiBaseV1 = '$apiBase$apiPrefix';
}
