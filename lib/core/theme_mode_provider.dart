import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'balvia_theme_mode';

// ---------------------------------------------------------------------------
// SharedPreferences singleton (async — resolved once at startup)
// ---------------------------------------------------------------------------

final sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (_) => SharedPreferences.getInstance(),
);

// ---------------------------------------------------------------------------
// Theme mode notifier — persists selection via SharedPreferences
// ---------------------------------------------------------------------------

/// Controls and persists the app's ThemeMode (system / light / dark).
/// Value is stored under [_kThemeModeKey] as an integer (ThemeMode index).
class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    final idx = prefs.getInt(_kThemeModeKey);
    if (idx == null) return ThemeMode.system;
    return ThemeMode.values[idx.clamp(0, ThemeMode.values.length - 1)];
  }

  Future<void> setMode(ThemeMode mode) async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    await prefs.setInt(_kThemeModeKey, mode.index);
    state = AsyncValue.data(mode);
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
