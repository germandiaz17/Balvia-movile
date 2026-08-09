// Riverpod providers for the offline-first layer:
//  - AppDatabase (singleton Drift DB)
//  - SyncEngine (singleton)
//  - Local repositories (accounts, categories, transactions)
//  - Offline-first read providers that replace the former network providers
//  - SyncController — triggers pull/push; tracks last result

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Use 'db' prefix to avoid name collisions with domain model classes
// (Drift generates Account, Category, Transaction, TrackingPeriod with the
// same names as our domain models).
import '../data/local/app_database.dart' as db;
import '../data/repositories/local_account_repository.dart';
import '../data/repositories/local_category_repository.dart';
import '../data/repositories/local_transaction_repository.dart';
import '../data/sync/sync_engine.dart';
import '../data/models/account.dart';
import '../data/models/category.dart';
import '../data/models/tracking_period.dart' as model;
import '../data/models/transaction.dart';
import 'providers.dart' show dioProvider, activeTrackingPeriodProvider;

// ---------------------------------------------------------------------------
// Database + engine singletons
// ---------------------------------------------------------------------------

/// The Drift database instance. Opened lazily; one per app lifetime.
final appDatabaseProvider = Provider<db.AppDatabase>((_) => db.AppDatabase());

/// The sync engine, shared across all providers.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    db: ref.watch(appDatabaseProvider),
    dio: ref.watch(dioProvider),
  );
});

// ---------------------------------------------------------------------------
// Local repositories
// ---------------------------------------------------------------------------

final localAccountRepoProvider = Provider<LocalAccountRepository>(
  (ref) => LocalAccountRepository(ref.watch(appDatabaseProvider)),
);

final localCategoryRepoProvider = Provider<LocalCategoryRepository>(
  (ref) => LocalCategoryRepository(ref.watch(appDatabaseProvider)),
);

final localTransactionRepoProvider = Provider<LocalTransactionRepository>(
  (ref) => LocalTransactionRepository(ref.watch(appDatabaseProvider)),
);

// ---------------------------------------------------------------------------
// Offline-first read providers (replace network-only FutureProviders)
// ---------------------------------------------------------------------------

/// Stream of accounts from Drift. Replaces the network accountsProvider.
/// Updates automatically when a pull upserts new data.
final localAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(localAccountRepoProvider).watchAll(),
);

/// Stream of categories from Drift. Replaces the network categoriesProvider.
final localCategoriesProvider = StreamProvider<List<Category>>(
  (ref) => ref.watch(localCategoryRepoProvider).watchAll(),
);

/// Active tracking period read from Drift. Falls back to network if the local
/// DB has no period yet (first launch before the first pull).
final localActiveTrackingPeriodProvider = StreamProvider<model.TrackingPeriod?>(
  (ref) {
    // Convert Drift TrackingPeriod rows to domain TrackingPeriod.
    return ref.watch(appDatabaseProvider).trackingPeriodsDao.watchActive().map((
      row,
    ) {
      if (row == null) return null;
      return model.TrackingPeriod(
        id: row.id,
        sequenceNumber: row.sequenceNumber,
        startDate: row.startDate,
        endDate: row.endDate,
        status: row.status,
        configStartDay: row.configStartDay,
        configDurationDays: row.configDurationDays,
        configPeriodMode: row.configPeriodMode,
        isTransition: row.isTransition,
        closedAt: row.closedAt != null ? DateTime.parse(row.closedAt!) : null,
      );
    });
  },
);

/// Stream of transactions for the active period from Drift.
/// Replaces allTransactionsProvider and recentTransactionsProvider.
/// Uses the local Drift period first (works offline); falls back to the
/// network provider if the local DB has no period yet.
final localTransactionsProvider = StreamProvider<List<Transaction>>((
  ref,
) async* {
  final localPeriod = ref.watch(localActiveTrackingPeriodProvider);

  String? periodId;
  if (localPeriod.hasValue && localPeriod.value != null) {
    periodId = localPeriod.value!.id;
  } else {
    // Try the network provider as fallback.
    final netPeriod = ref.watch(activeTrackingPeriodProvider);
    if (netPeriod.hasValue) {
      periodId = netPeriod.value!.id;
    }
  }

  if (periodId == null) {
    yield const <Transaction>[];
    return;
  }

  yield* ref.watch(localTransactionRepoProvider).watchByPeriod(periodId);
});

/// Recent transactions (last 10) from Drift — for the home dashboard widget.
final localRecentTransactionsProvider = Provider<AsyncValue<List<Transaction>>>(
  (ref) {
    final all = ref.watch(localTransactionsProvider);
    return all.whenData(
      (txs) => txs.take(10).toList(), // already sorted newest-first
    );
  },
);

// ---------------------------------------------------------------------------
// Sync controller
// ---------------------------------------------------------------------------

/// Exposes the last sync result so the UI can show badges or error toasts.
class SyncState {
  const SyncState({this.isSyncing = false, this.lastResult});

  final bool isSyncing;
  final SyncResult? lastResult;

  SyncState copyWith({bool? isSyncing, SyncResult? lastResult}) => SyncState(
    isSyncing: isSyncing ?? this.isSyncing,
    lastResult: lastResult ?? this.lastResult,
  );
}

class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  /// Triggers a full pull + push cycle. Called:
  ///  - on app start (post-login, from main.dart or auth controller)
  ///  - on pull-to-refresh in the UI
  ///  - after each local mutation (fire-and-forget)
  Future<SyncResult> sync() async {
    if (state.isSyncing) return const SyncResult();
    state = state.copyWith(isSyncing: true);
    try {
      final engine = ref.read(syncEngineProvider);
      final result = await engine.sync();
      // Sync failures are otherwise only visible as a status icon — always
      // leave a trace in the log so they can be diagnosed.
      if (result.isError) {
        debugPrint('Sync failed: ${result.error}');
      } else if (result.pullCount > 0) {
        // The overlay bubble runs in a separate engine with its own data
        // snapshot — tell it to reload whenever a pull landed new rows.
        await _notifyOverlay();
      }
      state = state.copyWith(isSyncing: false, lastResult: result);
      return result;
    } catch (e) {
      debugPrint('Sync crashed: $e');
      final result = SyncResult(error: e.toString());
      state = state.copyWith(isSyncing: false, lastResult: result);
      return result;
    }
  }

  /// Fire-and-forget sync. Used after local mutations so the UI call returns
  /// instantly without awaiting the network round-trip.
  void syncInBackground() {
    sync(); // intentionally not awaited
  }

  /// Best-effort 'refresh' message to the overlay bubble's engine. No-op when
  /// the overlay is not showing or the platform has no overlay support.
  Future<void> _notifyOverlay() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.shareData('refresh');
      }
    } catch (_) {}
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);
