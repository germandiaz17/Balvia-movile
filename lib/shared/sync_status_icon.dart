import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync_providers.dart';
import '../core/theme.dart';

/// Visual state of the sync indicator.
enum SyncStatus { synced, pending, offline }

/// Pill-shaped sync status indicator with icon + text (design system §6 / mockup 06).
///
/// States:
///   synced  : green pill "Sincronizado"
///   pending : amber pill "Pendiente"
///   offline : grey pill "Sin conexión"
///
/// Can be driven via [status] for testing / overrides; otherwise inferred from
/// [syncControllerProvider].
///
/// [compact] renders only the icon (for use in AppBar where space is limited).
class SyncStatusIcon extends ConsumerWidget {
  const SyncStatusIcon({super.key, this.status, this.compact = true});

  /// Override the auto-detected status. Null = infer from sync state.
  final SyncStatus? status;

  /// When true, renders only a small icon (for AppBar). When false, renders
  /// the full pill with text (for dashboard header).
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncControllerProvider);
    final resolved = status ?? _infer(syncState);

    final colors = _colors(resolved, context);

    if (compact) {
      return Tooltip(
        message: _tooltip(resolved, syncState),
        child: Icon(colors.icon, color: colors.iconColor, size: 20),
      );
    }

    // Full pill
    return Tooltip(
      message: _tooltip(resolved, syncState),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BalviaTheme.spaceSm,
          vertical: BalviaTheme.spaceXs,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(colors.icon, color: colors.iconColor, size: 14),
            const SizedBox(width: BalviaTheme.spaceXs),
            Text(
              _label(resolved),
              style: BalviaTheme.captionStyle(
                color: colors.iconColor,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  SyncStatus _infer(SyncState syncState) {
    if (syncState.isSyncing) return SyncStatus.pending;
    final result = syncState.lastResult;
    if (result == null) return SyncStatus.synced;
    if (result.isError) return SyncStatus.offline;
    if (result.hasRejected) return SyncStatus.pending;
    return SyncStatus.synced;
  }

  String _label(SyncStatus s) => switch (s) {
    SyncStatus.synced => 'Sincronizado',
    SyncStatus.pending => 'Pendiente',
    SyncStatus.offline => 'Sin conexión',
  };

  String _tooltip(SyncStatus s, SyncState syncState) => switch (s) {
    SyncStatus.synced => 'Sincronizado',
    SyncStatus.pending =>
      syncState.isSyncing ? 'Sincronizando…' : 'Sincronización pendiente',
    SyncStatus.offline =>
      'Sin conexión — tus datos se sincronizarán al reconectar',
  };

  _SyncColors _colors(SyncStatus status, BuildContext context) =>
      switch (status) {
        SyncStatus.synced => _SyncColors(
          icon: Icons.cloud_done_outlined,
          iconColor: const Color(0xFF2E7D32),
          background: const Color(0xFFE8F5E9),
          border: const Color(0xFFA5D6A7),
        ),
        SyncStatus.pending => _SyncColors(
          icon: Icons.cloud_sync_outlined,
          iconColor: Colors.amber.shade800,
          background: const Color(0xFFFFF8E1),
          border: const Color(0xFFFFD54F),
        ),
        SyncStatus.offline => _SyncColors(
          icon: Icons.cloud_off_outlined,
          iconColor: Colors.grey.shade600,
          background: Colors.grey.shade100,
          border: Colors.grey.shade300,
        ),
      };
}

class _SyncColors {
  const _SyncColors({
    required this.icon,
    required this.iconColor,
    required this.background,
    required this.border,
  });

  final IconData icon;
  final Color iconColor;
  final Color background;
  final Color border;
}
