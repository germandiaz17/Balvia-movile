// Drift database definition. Run `dart run build_runner build` to generate
// app_database.g.dart.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

// ---------------------------------------------------------------------------
// DAOs
// ---------------------------------------------------------------------------

/// DAO for the `transactions` table — the primary table for offline-first reads
/// and the outbox push queue.
@DriftAccessor(tables: [Transactions])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  /// Upsert a transaction row (insert or replace). Used by pull and by local
  /// mutations before push.
  Future<void> upsert(TransactionsCompanion row) =>
      into(transactions).insertOnConflictUpdate(row);

  /// Returns a stream of all non-deleted transactions for a tracking period,
  /// ordered by transaction_date DESC, created_at DESC.
  Stream<List<Transaction>> watchByPeriod(String trackingPeriodId) =>
      (select(transactions)
            ..where(
              (t) =>
                  t.trackingPeriodId.equals(trackingPeriodId) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([
              (t) => OrderingTerm.desc(t.transactionDate),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch();

  /// Returns a one-shot query of all non-deleted transactions for a period.
  Future<List<Transaction>> getByPeriod(String trackingPeriodId) =>
      (select(transactions)
            ..where(
              (t) =>
                  t.trackingPeriodId.equals(trackingPeriodId) &
                  t.deletedAt.isNull(),
            )
            ..orderBy([
              (t) => OrderingTerm.desc(t.transactionDate),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .get();

  /// Returns all pending rows (outbox) ordered by created_at ASC so older
  /// mutations are pushed first.
  Future<List<Transaction>> getPending() =>
      (select(transactions)
            ..where((t) => t.syncStatus.equals('pending'))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// Soft-delete a transaction locally (marks deleted_at + pending).
  Future<void> softDelete(String id, String deletedAt) =>
      (update(transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(
          deletedAt: Value(deletedAt),
          syncStatus: const Value('pending'),
          updatedAt: Value(deletedAt),
        ),
      );

  /// Mark a transaction as synced and update its id/server fields.
  /// Used when push returns `applied` or `skipped`.
  Future<void> markSynced(
    String localId, {
    required String serverId,
    required String updatedAt,
  }) async {
    // If the server assigned a different id (rare for creates via client_id),
    // we replace the row.
    if (localId != serverId) {
      final existing = await (select(
        transactions,
      )..where((t) => t.id.equals(localId))).getSingleOrNull();
      if (existing != null) {
        await (delete(transactions)..where((t) => t.id.equals(localId))).go();
        await upsert(
          existing
              .toCompanion(true)
              .copyWith(
                id: Value(serverId),
                syncStatus: const Value('synced'),
                updatedAt: Value(updatedAt),
              ),
        );
        return;
      }
    }
    await (update(transactions)..where((t) => t.id.equals(localId))).write(
      TransactionsCompanion(
        syncStatus: const Value('synced'),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  /// Mark a transaction as conflicted (pull/push conflict resolution applies
  /// the server_entity; this just updates the local row).
  Future<void> applyServerEntity(TransactionsCompanion row) =>
      into(transactions).insertOnConflictUpdate(row);
}

/// DAO for accounts.
@DriftAccessor(tables: [Accounts])
class AccountsDao extends DatabaseAccessor<AppDatabase>
    with _$AccountsDaoMixin {
  AccountsDao(super.db);

  Future<void> upsert(AccountsCompanion row) =>
      into(accounts).insertOnConflictUpdate(row);

  /// Stream of all non-archived, non-deleted accounts.
  Stream<List<Account>> watchAll() =>
      (select(accounts)
            ..where((a) => a.deletedAt.isNull() & a.isArchived.equals(false))
            ..orderBy([(a) => OrderingTerm.asc(a.displayOrder)]))
          .watch();

  Future<List<Account>> getAll() =>
      (select(accounts)
            ..where((a) => a.deletedAt.isNull() & a.isArchived.equals(false))
            ..orderBy([(a) => OrderingTerm.asc(a.displayOrder)]))
          .get();
}

/// DAO for categories.
@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  Future<void> upsert(CategoriesCompanion row) =>
      into(categories).insertOnConflictUpdate(row);

  /// Stream of all non-deleted categories (system + own).
  Stream<List<Category>> watchAll() =>
      (select(categories)
            ..where((c) => c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm.asc(c.displayOrder)]))
          .watch();

  Future<List<Category>> getAll() =>
      (select(categories)
            ..where((c) => c.deletedAt.isNull())
            ..orderBy([(c) => OrderingTerm.asc(c.displayOrder)]))
          .get();
}

/// DAO for tracking periods (read-only client-side).
@DriftAccessor(tables: [TrackingPeriods])
class TrackingPeriodsDao extends DatabaseAccessor<AppDatabase>
    with _$TrackingPeriodsDaoMixin {
  TrackingPeriodsDao(super.db);

  Future<void> upsert(TrackingPeriodsCompanion row) =>
      into(trackingPeriods).insertOnConflictUpdate(row);

  Future<TrackingPeriod?> getActive() =>
      (select(trackingPeriods)
            ..where((t) => t.status.equals('active') & t.deletedAt.isNull()))
          .getSingleOrNull();

  Stream<TrackingPeriod?> watchActive() =>
      (select(trackingPeriods)
            ..where((t) => t.status.equals('active') & t.deletedAt.isNull()))
          .watchSingleOrNull();
}

/// DAO for sync metadata (cursor).
@DriftAccessor(tables: [SyncMetadata])
class SyncMetadataDao extends DatabaseAccessor<AppDatabase>
    with _$SyncMetadataDaoMixin {
  SyncMetadataDao(super.db);

  Future<SyncMetadataData?> get() =>
      (select(syncMetadata)..where((m) => m.id.equals(1))).getSingleOrNull();

  Future<void> setLastSyncedAt(String serverTime) =>
      into(syncMetadata).insertOnConflictUpdate(
        SyncMetadataCompanion(
          id: const Value(1),
          lastSyncedAt: Value(serverTime),
        ),
      );
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(
  tables: [
    Accounts,
    Categories,
    Transactions,
    Budgets,
    SavingsGoals,
    GoalContributions,
    RecurringTransactions,
    TrackingPeriods,
    SyncMetadata,
  ],
  daos: [
    AccountsDao,
    CategoriesDao,
    TransactionsDao,
    TrackingPeriodsDao,
    SyncMetadataDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;
}

/// Opens a connection to the app's SQLite file.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'balvia.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
