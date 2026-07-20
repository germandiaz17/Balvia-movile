// Overlay (floating bubble) settings.
//
// Stored in SharedPreferences so they are readable from both the main app
// isolate and the overlay FlutterEngine isolate (via SharedPreferences.getInstance()).
//
// Keys are prefixed with "overlay_" to avoid collisions.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Key constants
// ---------------------------------------------------------------------------

abstract final class OverlayPrefsKeys {
  static const enabled = 'overlay_enabled';
  static const opacity = 'overlay_opacity';
  static const colorHex = 'overlay_color_hex';
  static const defaultAccountId = 'overlay_default_account_id';
  static const showTodaySpend = 'overlay_show_today_spend';
  static const showBalance = 'overlay_show_balance';
  static const autoOffMinutes = 'overlay_auto_off_minutes'; // -1 = never
  static const bubbleSize = 'overlay_bubble_size';
}

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class OverlaySettings {
  const OverlaySettings({
    this.enabled = false,
    this.opacity = 0.85,
    this.colorHex = '#0F9D8C', // Balvia teal
    this.defaultAccountId,
    this.showTodaySpend = true,
    this.showBalance = false,
    this.autoOffMinutes, // null = never
    this.bubbleSize = 56.0,
  });

  final bool enabled;

  /// Bubble opacity: 0.3 – 1.0.
  final double opacity;

  /// ARGB hex string, e.g. "#0F9D8C" or "#FF0F9D8C". Controls the bubble tint.
  final String colorHex;

  /// UUID of the account where captured expenses are written. null → first account.
  final String? defaultAccountId;

  /// Whether to show today's total spend in the expanded overlay.
  final bool showTodaySpend;

  /// Whether to show the default account balance in the expanded overlay.
  final bool showBalance;

  /// Minutes of inactivity (after leaving the app) before the bubble hides.
  /// null means never auto-hide.
  final int? autoOffMinutes;

  /// Collapsed bubble height in dp (44 – 88). The pill width and the overlay
  /// window size derive from this (see overlay_logic.dart helpers).
  final double bubbleSize;

  OverlaySettings copyWith({
    bool? enabled,
    double? opacity,
    String? colorHex,
    Object? defaultAccountId = _sentinel, // use _sentinel for nullable clear
    bool? showTodaySpend,
    bool? showBalance,
    Object? autoOffMinutes = _sentinel,
    double? bubbleSize,
  }) {
    return OverlaySettings(
      enabled: enabled ?? this.enabled,
      opacity: opacity ?? this.opacity,
      colorHex: colorHex ?? this.colorHex,
      defaultAccountId: defaultAccountId == _sentinel
          ? this.defaultAccountId
          : defaultAccountId as String?,
      showTodaySpend: showTodaySpend ?? this.showTodaySpend,
      showBalance: showBalance ?? this.showBalance,
      autoOffMinutes: autoOffMinutes == _sentinel
          ? this.autoOffMinutes
          : autoOffMinutes as int?,
      bubbleSize: bubbleSize ?? this.bubbleSize,
    );
  }

  /// Parse color string to Flutter Color.
  Color get bubbleColor {
    try {
      final hex = colorHex.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF0F9D8C); // fallback to brand teal
  }
}

const Object _sentinel = Object();

// ---------------------------------------------------------------------------
// SharedPreferences helpers (used from both isolates)
// ---------------------------------------------------------------------------

/// Reads [OverlaySettings] from [SharedPreferences].
/// Call this from the overlay isolate (no Riverpod available there).
OverlaySettings overlaySettingsFromPrefs(SharedPreferences prefs) {
  return OverlaySettings(
    enabled: prefs.getBool(OverlayPrefsKeys.enabled) ?? false,
    opacity: prefs.getDouble(OverlayPrefsKeys.opacity) ?? 0.85,
    colorHex: prefs.getString(OverlayPrefsKeys.colorHex) ?? '#0F9D8C',
    defaultAccountId: prefs.getString(OverlayPrefsKeys.defaultAccountId),
    showTodaySpend: prefs.getBool(OverlayPrefsKeys.showTodaySpend) ?? true,
    showBalance: prefs.getBool(OverlayPrefsKeys.showBalance) ?? false,
    autoOffMinutes: () {
      final raw = prefs.getInt(OverlayPrefsKeys.autoOffMinutes);
      return (raw == null || raw < 0) ? null : raw;
    }(),
    bubbleSize: prefs.getDouble(OverlayPrefsKeys.bubbleSize) ?? 56.0,
  );
}

/// Persists [settings] to [SharedPreferences].
Future<void> saveOverlaySettings(
  SharedPreferences prefs,
  OverlaySettings settings,
) async {
  await prefs.setBool(OverlayPrefsKeys.enabled, settings.enabled);
  await prefs.setDouble(OverlayPrefsKeys.opacity, settings.opacity);
  await prefs.setString(OverlayPrefsKeys.colorHex, settings.colorHex);
  if (settings.defaultAccountId != null) {
    await prefs.setString(
      OverlayPrefsKeys.defaultAccountId,
      settings.defaultAccountId!,
    );
  } else {
    await prefs.remove(OverlayPrefsKeys.defaultAccountId);
  }
  await prefs.setBool(OverlayPrefsKeys.showTodaySpend, settings.showTodaySpend);
  await prefs.setBool(OverlayPrefsKeys.showBalance, settings.showBalance);
  await prefs.setInt(
    OverlayPrefsKeys.autoOffMinutes,
    settings.autoOffMinutes ?? -1,
  );
  await prefs.setDouble(OverlayPrefsKeys.bubbleSize, settings.bubbleSize);
}

// ---------------------------------------------------------------------------
// Riverpod notifier (main app isolate only)
// ---------------------------------------------------------------------------

class OverlaySettingsNotifier extends AsyncNotifier<OverlaySettings> {
  @override
  Future<OverlaySettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return overlaySettingsFromPrefs(prefs);
  }

  /// Saves [settings] to SharedPreferences and updates state.
  Future<void> save(OverlaySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await saveOverlaySettings(prefs, settings);
    state = AsyncData(settings);
  }

  Future<void> setEnabled(bool value) async {
    final current = state.value;
    if (current == null) return;
    await save(current.copyWith(enabled: value));
  }
}

final overlaySettingsProvider =
    AsyncNotifierProvider<OverlaySettingsNotifier, OverlaySettings>(
      OverlaySettingsNotifier.new,
    );
