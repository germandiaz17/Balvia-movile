import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync_providers.dart';

/// Visual state of the sync indicator.
enum SyncStatus { synced, pending, offline }

/// Icon reflecting the current sync state, driven by [syncControllerProvider].
///
/// - synced  : cloud_done (primary color)
/// - pending : cloud_upload (amber) — sync in progress or rejected items
/// - offline : cloud_off (grey) — last sync ended with a network/server error
///
/// Can also be driven directly via [status] for testing / overrides.
class SyncStatusIcon extends ConsumerWidget {
  const SyncStatusIcon({super.key, this.status});

  /// Override the auto-detected status. Null = infer from sync state.
  final SyncStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final syncState = ref.watch(syncControllerProvider);

    final resolved = status ?? _infer(syncState);

    return switch (resolved) {
      SyncStatus.synced => Tooltip(
        message: 'Sincronizado',
        child: Icon(Icons.cloud_done_outlined, color: cs.primary, size: 20),
      ),
      SyncStatus.pending => Tooltip(
        message: syncState.isSyncing
            ? 'Sincronizando…'
            : 'Sincronización pendiente',
        child: Icon(
          Icons.cloud_upload_outlined,
          color: Colors.amber.shade700,
          size: 20,
        ),
      ),
      SyncStatus.offline => Tooltip(
        message: 'Sin conexión — tus datos se sincronizarán',
        child: Icon(
          Icons.cloud_off_outlined,
          color: cs.onSurfaceVariant,
          size: 20,
        ),
      ),
    };
  }

  SyncStatus _infer(SyncState syncState) {
    if (syncState.isSyncing) return SyncStatus.pending;
    final result = syncState.lastResult;
    if (result == null) return SyncStatus.synced;
    if (result.isError) return SyncStatus.offline;
    if (result.hasRejected) return SyncStatus.pending;
    return SyncStatus.synced;
  }
}
