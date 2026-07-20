// Widget that listens for overlay messages (shareData) in the main app
// and triggers a sync + provider refresh when the overlay saves a transaction.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../core/providers.dart';
import '../../core/sync_providers.dart';

/// Wraps a child widget tree and subscribes to FlutterOverlayWindow messages.
/// When the overlay notifies "refresh", fires a background sync.
///
/// Safe to use on any platform — the listen call is guarded by platform check.
class OverlayAppListener extends ConsumerStatefulWidget {
  const OverlayAppListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<OverlayAppListener> createState() => _OverlayAppListenerState();
}

class _OverlayAppListenerState extends ConsumerState<OverlayAppListener> {
  bool _isAndroid = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    if (isAndroid && !_isAndroid) {
      _isAndroid = true;
      _subscribe();
    }
  }

  void _subscribe() {
    FlutterOverlayWindow.overlayListener.listen(_onMessage);
  }

  void _onMessage(dynamic message) {
    if (message is String && message == 'refresh') {
      // Trigger a background sync so the pending overlay transaction
      // gets pushed to the server, and pull fresh data.
      ref.read(syncControllerProvider.notifier).syncInBackground();
      // Invalidate key providers so the UI refreshes on next read. The
      // Drift-backed streams must be invalidated explicitly: the overlay
      // writes through its OWN database connection, so the main engine's
      // watch() queries never see those inserts on their own.
      ref.invalidate(activeTrackingPeriodProvider);
      ref.invalidate(localActiveTrackingPeriodProvider);
      ref.invalidate(localTransactionsProvider);
      ref.invalidate(localAccountsProvider);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
