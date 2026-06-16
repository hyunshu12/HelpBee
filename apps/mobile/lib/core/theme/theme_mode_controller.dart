import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_prefs.dart';

/// App-wide theme mode (system / light / dark), persisted in [AppPrefs].
///
/// Starts at [ThemeMode.system] and loads the saved preference asynchronously
/// (build stays synchronous). The settings screen calls [setMode].
class ThemeModeController extends Notifier<ThemeMode> {
  AppPrefs get _prefs => ref.read(appPrefsProvider);

  @override
  ThemeMode build() {
    Future.microtask(_load);
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      state = _parse(await _prefs.getThemeMode());
    } catch (_) {
      // Best-effort: keep system default if prefs read fails.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      await _prefs.setThemeMode(_serialize(mode));
    } catch (_) {
      // Non-fatal: the in-memory choice still applies for this session.
    }
  }

  static ThemeMode _parse(String v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _serialize(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}

final themeModeControllerProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);
