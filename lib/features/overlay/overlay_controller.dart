// Controller that manages the lifecycle of the floating bubble from the
// main app isolate.
//
// Responsibilities:
//   - Request SYSTEM_ALERT_WINDOW permission with guided onboarding.
//   - Show / hide the overlay via FlutterOverlayWindow API.
//   - Detect app lifecycle changes for auto-off timer.
//   - Notify the overlay of settings changes via shareData.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'overlay_logic.dart';
import 'overlay_settings.dart';

// ---------------------------------------------------------------------------
// Platform guard
// ---------------------------------------------------------------------------

/// True only on Android — the overlay feature is Android-only.
bool get _isAndroid => Platform.isAndroid;

// ---------------------------------------------------------------------------
// OverlayController
// ---------------------------------------------------------------------------

class OverlayController extends AsyncNotifier<bool>
    with WidgetsBindingObserver {
  /// State = true when the bubble is currently visible.
  @override
  Future<bool> build() async {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() => WidgetsBinding.instance.removeObserver(this));
    return _isOverlayActive();
  }

  DateTime? _backgroundedAt;

  // ---- Lifecycle ----

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now().toUtc();
    } else if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  void _onAppResumed() {
    final settings = ref.read(overlaySettingsProvider).value;
    if (settings == null) return;

    // Check auto-off: if backgrounded long enough, hide the bubble.
    if (shouldAutoOff(
      backgroundedAt: _backgroundedAt,
      autoOffMinutes: settings.autoOffMinutes,
    )) {
      _hideOverlay();
    }
    _backgroundedAt = null;
  }

  // ---- Public API ----

  /// Enables the overlay (requests permission if needed, then shows it).
  /// Returns true if the overlay was successfully shown.
  // ignore: use_build_context_synchronously
  Future<bool> enable(BuildContext context) async {
    if (!_isAndroid) return false;

    final hasPermission = await FlutterOverlayWindow.isPermissionGranted();
    if (!hasPermission) {
      if (!context.mounted) return false;
      // ignore: use_build_context_synchronously
      final granted = await _requestPermissionWithOnboarding(context);
      if (!granted) return false;
    }

    await _showOverlay();
    state = const AsyncData(true);
    // The overlay engine loaded its data snapshot when the app process
    // started; anything synced since then (accounts, categories) would be
    // invisible to the bubble. Ask it to reload now that it is visible.
    await pushSettings();
    return true;
  }

  /// Disables (hides) the overlay.
  Future<void> disable() async {
    await _hideOverlay();
    state = const AsyncData(false);
  }

  /// Toggle with onboarding if needed.
  Future<bool> toggle(BuildContext context) async {
    final isActive = state.value ?? false;
    if (isActive) {
      await disable();
      return false;
    } else {
      return enable(context);
    }
  }

  /// Push updated settings to the live overlay (shareData → overlayListener).
  Future<void> pushSettings() async {
    if (!(state.value ?? false)) return;
    try {
      await FlutterOverlayWindow.shareData('refresh');
    } catch (_) {}
  }

  // ---- Private ----

  Future<bool> _isOverlayActive() async {
    if (!_isAndroid) return false;
    try {
      return await FlutterOverlayWindow.isActive();
    } catch (_) {
      return false;
    }
  }

  Future<void> _showOverlay() async {
    final settings = await ref.read(overlaySettingsProvider.future);
    final size = clampBubbleSize(settings.bubbleSize);
    await FlutterOverlayWindow.showOverlay(
      height: collapsedWindowHeight(size),
      width: collapsedWindowWidth(size),
      alignment: OverlayAlignment.centerRight,
      flag: OverlayFlag.defaultFlag,
      enableDrag: true,
      overlayTitle: 'Balvia',
      overlayContent: 'Captura rápida de gastos',
      visibility: NotificationVisibility.visibilityPublic,
      // Snap to the nearest left/right edge after each drag; the bubble
      // mirrors its half-pill shape to keep the flat side on the edge.
      positionGravity: PositionGravity.auto,
    );
  }

  Future<void> _hideOverlay() async {
    if (!_isAndroid) return;
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (_) {}
  }

  Future<bool> _requestPermissionWithOnboarding(BuildContext context) async {
    // Show explanation dialog before sending the user to system settings.
    if (!context.mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permiso necesario'),
        content: const Text(
          'La burbuja flotante necesita el permiso "Mostrar sobre otras apps" '
          'para aparecer encima de cualquier aplicación.\n\n'
          'Toca "Continuar" y activa el permiso para Balvia en la pantalla de ajustes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );

    if (proceed != true) return false;

    await FlutterOverlayWindow.requestPermission();

    // Brief delay for the user to toggle the permission and return.
    await Future.delayed(const Duration(seconds: 1));
    return FlutterOverlayWindow.isPermissionGranted();
  }
}

final overlayControllerProvider =
    AsyncNotifierProvider<OverlayController, bool>(OverlayController.new);
