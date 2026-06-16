import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive flags only (onboarding seen, "keep logged in").
///
/// NEVER store tokens / secrets / PII here — those go in [TokenStore]
/// (secure storage). Uses the async [SharedPreferencesAsync] API.
class AppPrefs {
  AppPrefs({SharedPreferencesAsync? prefs})
      : _prefs = prefs ?? SharedPreferencesAsync();

  static const String _kOnboardingSeen = 'hb_onboarding_seen';
  static const String _kKeepLoggedIn = 'hb_keep_logged_in';
  static const String _kThemeMode = 'hb_theme_mode';

  final SharedPreferencesAsync _prefs;

  /// Whether the 3-step onboarding has been completed at least once.
  Future<bool> isOnboardingSeen() async =>
      await _prefs.getBool(_kOnboardingSeen) ?? false;

  /// Marks onboarding as completed (idempotent).
  Future<void> setOnboardingSeen() => _prefs.setBool(_kOnboardingSeen, true);

  /// Whether the user opted into staying logged in. Default: true (most
  /// beekeepers want to skip re-login in the field).
  Future<bool> isKeepLoggedIn() async =>
      await _prefs.getBool(_kKeepLoggedIn) ?? true;

  /// Persists the "keep logged in" choice from the login screen.
  Future<void> setKeepLoggedIn(bool value) =>
      _prefs.setBool(_kKeepLoggedIn, value);

  /// Theme preference: 'system' (default) | 'light' | 'dark'.
  Future<String> getThemeMode() async =>
      await _prefs.getString(_kThemeMode) ?? 'system';

  /// Persists the theme preference from settings.
  Future<void> setThemeMode(String value) =>
      _prefs.setString(_kThemeMode, value);
}

/// App-wide singleton. Override in tests with a fake [AppPrefs].
final appPrefsProvider = Provider<AppPrefs>((ref) => AppPrefs());
