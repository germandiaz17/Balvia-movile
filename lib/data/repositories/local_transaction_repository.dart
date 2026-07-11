// Local-first transaction repository backed by Drift.
//
// All reads come from SQLite (streams or one-shot queries).
// Writes go to the local DB first (outbox pattern):
//   1. Insert/update/delete the row in Drift with sync_status = 'pending'.
//   2. Generate a client_id for creates (idempotency key for the push).
//   3. The SyncEngine drains the outbox on the next sync trigger.

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

// Use prefix 'db' for all Drift-generated types to avoid collision with the
// domain models (which share names: Transaction, Account, etc.).
import '../local/app_database.dart' as db;
import '../sync/sync_engine.dart' show generateClientId, generateLocalId;
import '../../data/models/transaction.dart';

// ---------------------------------------------------------------------------
// Mapper: Drift row → domain model
// ---------------------------------------------------------------------------

/// Converts a Drift [db.Transaction] row to the domain [Transaction].
Transaction _rowToModel(db.Transaction row) => Transaction(
  id: row.id,
  trackingPeriodId: row.trackingPeriodId,
  accountId: row.accountId,
  transactionType: row.transactionType,
  amount: Decimal.parse(row.amount),
  currency: row.currency,
  transactionDate: row.transactionDate,
  createdAt: DateTime.parse(row.createdAt),
  categoryId: row.categoryId,
  description: row.description,
  notes: row.notes,
  transferAccountId: row.transferAccountId,
  clientId: row.clientId,
  recurringTransactionId: row.recurringTransactionId,
  occurrenceDate: row.occurrenceDate,
);

// ---------------------------------------------------------------------------
// LocalTransactionRepository
// ---------------------------------------------------------------------------

class LocalTransactionRepository {
  LocalTransactionRepository(this._db);

  final db.AppDatabase _db;

  // -----------------------------------------------------------------------
  // Reads (from Drift — offline-first)
  // -----------------------------------------------------------------------

  /// Stream of all non-deleted transactions for [trackingPeriodId], sorted
  /// newest first. Use this in providers via StreamProvider.
  Stream<List<Transaction>> watchByPeriod(String trackingPeriodId) => _db
      .transactionsDao
      .watchByPeriod(trackingPeriodId)
      .map((rows) => rows.map(_rowToModel).toList());

  /// One-shot query (for contexts that cannot use a stream).
  Future<List<Transaction>> getByPeriod(String trackingPeriodId) async {
    final rows = await _db.transactionsDao.getByPeriod(trackingPeriodId);
    return rows.map(_rowToModel).toList();
  }

  // -----------------------------------------------------------------------
  // Writes (outbox — sets sync_status = pending)
  // -----------------------------------------------------------------------

  /// Creates a transaction locally and queues it for push.
  /// Returns the local domain model immediately (UX <5s, no network wait).
  Future<Transaction> create({
    required String trackingPeriodId,
    required String accountId,
    required String transactionType,
    required Decimal amount,
    String currency = 'COP',
    String? categoryId,
    String? description,
    String? notes,
    String? transactionDate,
    String? transferAccountId,
    String userId = '',
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final date =
        transactionDate ??
        DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD

    final localId = generateLocalId();
    final clientId = generateClientId();

    final companion = db.TransactionsCompanion.insert(
      id: localId,
      userId: userId,
      trackingPeriodId: trackingPeriodId,
      accountId: accountId,
      transactionType: transactionType,
      amount: amount.toStringAsFixed(2),
      currency: currency,
      transactionDate: date,
      createdAt: now,
      updatedAt: now,
      categoryId: Value(categoryId),
      description: Value(description),
      notes: Value(notes),
      transferAccountId: Value(transferAccountId),
      clientId: Value(clientId),
      syncStatus: const Value('pending'),
    );

    await _db.transactionsDao.upsert(companion);

    final row = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(localId))).getSingle();
    return _rowToModel(row);
  }

  /// Updates a transaction locally and marks it pending for push.
  Future<Transaction> update(
    String id, {
    required String accountId,
    required String transactionType,
    required Decimal amount,
    String currency = 'COP',
    String? categoryId,
    String? description,
    String? notes,
    String? transactionDate,
    String? transferAccountId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      db.TransactionsCompanion(
        accountId: Value(accountId),
        transactionType: Value(transactionType),
        amount: Value(amount.toStringAsFixed(2)),
        currency: Value(currency),
        categoryId: Value(categoryId),
        description: Value(description),
        notes: Value(notes),
        transactionDate: Value(
          transactionDate ?? DateTime.now().toIso8601String().substring(0, 10),
        ),
        transferAccountId: Value(transferAccountId),
        updatedAt: Value(now),
        syncStatus: const Value('pending'),
      ),
    );

    final row = await (_db.select(
      _db.transactions,
    )..where((t) => t.id.equals(id))).getSingle();
    return _rowToModel(row);
  }

  /// Soft-deletes a transaction locally and marks it pending for push.
  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.transactionsDao.softDelete(id, now);
  }
}
