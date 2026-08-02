// Offline-first sync engine for Balvia.
//
// Pull protocol (GET /sync/pull):
//   1. Read cursor (last_synced_at) from SyncMetadata.
//   2. Pull since that cursor (epoch on first run).
//   3. Upsert every row into the local DB; rows with deleted_at != null are
//      soft-deleted locally.
//   4. If has_more, advance since to the oldest last updated_at among truncated
//      collections and repeat.
//   5. On success (has_more == false), persist server_time as the new cursor.
//
// Push protocol (POST /sync/push):
//   - Reads all transactions with sync_status == 'pending' from the outbox.
//   - Groups them into a single batch (or chunked if large).
//   - For each result:
//       applied / skipped → markSynced (adopt server id).
//       conflict → apply server_entity (LWW: server wins).
//       rejected → mark conflict status so the UI can surface it.
//
// Triggering:
//   - On app start (post-login).
//   - On pull-to-refresh (called by UI).
//   - After every local mutation if the network call succeeded;
//     if offline (DioException with no response), the outbox row stays 'pending'
//     and will be pushed on the next trigger.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:uuid/uuid.dart';

import '../local/app_database.dart' as drift;
import 'sync_models.dart';

const _epoch = '1970-01-01T00:00:00Z';
const _defaultPageSize = 200;
// Maximum items per push batch to avoid oversized requests.
const _pushBatchSize = 50;

/// Result of a sync operation for the UI to react to.
class SyncResult {
  const SyncResult({
    this.pullCount = 0,
    this.pushApplied = 0,
    this.pushConflicts = 0,
    this.pushRejected = 0,
    this.error,
  });

  final int pullCount; // total rows upserted
  final int pushApplied;
  final int pushConflicts;
  final int pushRejected;
  final String? error; // non-null if the sync failed (network/server error)

  bool get hasConflicts => pushConflicts > 0;
  bool get hasRejected => pushRejected > 0;
  bool get isError => error != null;
}

class SyncEngine {
  SyncEngine({required drift.AppDatabase db, required this.dio})
    : _database = db;

  final drift.AppDatabase _database;
  final Dio dio;

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Runs a full sync cycle: pull + push.
  Future<SyncResult> sync() async {
    try {
      final pullCount = await _pull();
      final pushResult = await _push();
      return SyncResult(
        pullCount: pullCount,
        pushApplied: pushResult.pushApplied,
        pushConflicts: pushResult.pushConflicts,
        pushRejected: pushResult.pushRejected,
      );
    } on DioException catch (e) {
      // Network error — outbox rows stay pending; will retry on next trigger.
      return SyncResult(error: _dioError(e));
    } catch (e) {
      return SyncResult(error: e.toString());
    }
  }

  /// Executes only the pull half (e.g., after pull-to-refresh with no local
  /// mutations).
  Future<int> pullOnly() async => _pull();

  // -------------------------------------------------------------------------
  // Pull
  // -------------------------------------------------------------------------

  Future<int> _pull() async {
    final meta = await _database.syncMetadataDao.get();
    var since = meta?.lastSyncedAt ?? _epoch;
    var totalUpserted = 0;

    // Paginate: repeat until has_more == false.
    while (true) {
      final response = await dio.get<Map<String, dynamic>>(
        '/sync/pull',
        queryParameters: {'since': since, 'page_size': _defaultPageSize},
      );
      final pull = PullResponse.fromJson(response.data!);

      totalUpserted += await _applyPull(pull);

      if (!pull.hasMore) {
        // Persist the cursor only on the final page.
        await _database.syncMetadataDao.setLastSyncedAt(pull.serverTime);
        break;
      }

      // Advance since to oldest last updated_at of truncated collections.
      final nextSince = pull.oldestLastUpdatedAt();
      if (nextSince == null) break; // safety valve
      since = nextSince;
    }

    return totalUpserted;
  }

  /// Upserts all rows from a pull page into the local DB atomically.
  ///
  /// Individual malformed rows are logged and skipped rather than aborting
  /// the whole page: one bad row must never wedge the entire sync forever
  /// (the pull cursor only advances when the page applies).
  Future<int> _applyPull(PullResponse pull) async {
    int count = 0;

    Future<void> applyAll(
      String entity,
      List<Map<String, dynamic>> rows,
      Future<void> Function(Map<String, dynamic>) upsert,
    ) async {
      for (final row in rows) {
        try {
          await upsert(row);
          count++;
        } catch (e) {
          debugPrint('Sync: skipping bad $entity row ${row['id']}: $e');
        }
      }
    }

    await _database.transaction(() async {
      await applyAll(
        'tracking_period',
        pull.trackingPeriods,
        _upsertTrackingPeriod,
      );
      await applyAll('account', pull.accounts, _upsertAccount);
      await applyAll('category', pull.categories, _upsertCategory);
      await applyAll('transaction', pull.transactions, _upsertTransaction);
      await applyAll('budget', pull.budgets, _upsertBudget);
      await applyAll('savings_goal', pull.savingsGoals, _upsertSavingsGoal);
      await applyAll(
        'goal_contribution',
        pull.goalContributions,
        _upsertGoalContribution,
      );
      await applyAll(
        'recurring_transaction',
        pull.recurringTransactions,
        _upsertRecurringTransaction,
      );
    });

    return count;
  }

  // -------------------------------------------------------------------------
  // Per-entity upsert helpers
  // -------------------------------------------------------------------------

  /// For transactions pulled from the server: rows with a pending local
  /// mutation are left untouched (the push reconciles them); server-side
  /// soft-deletes always win. Everything else is upserted as 'synced'.
  Future<void> _upsertTransaction(Map<String, dynamic> row) async {
    final id = row['id'] as String;
    final deletedAt = row['deleted_at'] as String?;

    if (deletedAt != null) {
      // Server soft-deleted this row → mark deleted locally.
      await _database.transactionsDao.upsert(
        drift.TransactionsCompanion(
          id: Value(id),
          userId: Value(row['user_id'] as String),
          trackingPeriodId: Value(row['tracking_period_id'] as String),
          accountId: Value(row['account_id'] as String),
          transactionType: Value(row['transaction_type'] as String),
          amount: Value(row['amount'] as String),
          currency: Value(row['currency'] as String),
          transactionDate: Value(row['transaction_date'] as String),
          createdAt: Value(row['created_at'] as String),
          updatedAt: Value(row['updated_at'] as String),
          deletedAt: Value(deletedAt),
          syncStatus: const Value('synced'),
          categoryId: Value(row['category_id'] as String?),
          description: Value(row['description'] as String?),
          notes: Value(row['notes'] as String?),
          transferAccountId: Value(row['transfer_account_id'] as String?),
          clientId: Value(row['client_id'] as String?),
          recurringTransactionId: Value(
            row['recurring_transaction_id'] as String?,
          ),
          occurrenceDate: Value(row['occurrence_date'] as String?),
          aiCategorized: Value(row['ai_categorized'] as bool? ?? false),
          aiConfidence: Value(row['ai_confidence'] as String?),
          aiSuggestedCategoryId: Value(
            row['ai_suggested_category_id'] as String?,
          ),
        ),
      );
      return;
    }

    // For non-deleted rows: if a pending local mutation exists, keep the local
    // version untouched — overwriting it with server values would silently
    // discard the unsynced edit. The next push reconciles it (applied, or
    // conflict returning the server_entity).
    final existing = await (_database.select(
      _database.transactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing?.syncStatus == 'pending') return;

    await _database.transactionsDao.upsert(
      drift.TransactionsCompanion(
        id: Value(id),
        userId: Value(row['user_id'] as String),
        trackingPeriodId: Value(row['tracking_period_id'] as String),
        accountId: Value(row['account_id'] as String),
        transactionType: Value(row['transaction_type'] as String),
        amount: Value(row['amount'] as String),
        currency: Value(row['currency'] as String),
        transactionDate: Value(row['transaction_date'] as String),
        createdAt: Value(row['created_at'] as String),
        updatedAt: Value(row['updated_at'] as String),
        deletedAt: const Value(null),
        syncStatus: const Value('synced'),
        categoryId: Value(row['category_id'] as String?),
        description: Value(row['description'] as String?),
        notes: Value(row['notes'] as String?),
        transferAccountId: Value(row['transfer_account_id'] as String?),
        clientId: Value(row['client_id'] as String?),
        recurringTransactionId: Value(
          row['recurring_transaction_id'] as String?,
        ),
        occurrenceDate: Value(row['occurrence_date'] as String?),
        aiCategorized: Value(row['ai_categorized'] as bool? ?? false),
        aiConfidence: Value(row['ai_confidence'] as String?),
        aiSuggestedCategoryId: Value(
          row['ai_suggested_category_id'] as String?,
        ),
      ),
    );
  }

  Future<void> _upsertAccount(Map<String, dynamic> row) async {
    await _database.accountsDao.upsert(
      drift.AccountsCompanion(
        id: Value(row['id'] as String),
        userId: Value(row['user_id'] as String),
        name: Value(row['name'] as String),
        accountType: Value(row['account_type'] as String),
        currency: Value(row['currency'] as String),
        initialBalance: Value(row['initial_balance'] as String),
        currentBalance: Value(row['current_balance'] as String),
        icon: Value(row['icon'] as String?),
        color: Value(row['color'] as String?),
        displayOrder: Value(row['display_order'] as int? ?? 0),
        isArchived: Value(row['is_archived'] as bool? ?? false),
        updatedAt: Value(row['updated_at'] as String),
        deletedAt: Value(row['deleted_at'] as String?),
      ),
    );
  }

  Future<void> _upsertCategory(Map<String, dynamic> row) async {
    await _database.categoriesDao.upsert(
      drift.CategoriesCompanion(
        id: Value(row['id'] as String),
        // System categories belong to no user (user_id is null on the wire);
        // the local column is NOT NULL, so store them under ''.
        userId: Value(row['user_id'] as String? ?? ''),
        parentId: Value(row['parent_id'] as String?),
        name: Value(row['name'] as String),
        categoryType: Value(row['category_type'] as String),
        icon: Value(row['icon'] as String?),
        color: Value(row['color'] as String?),
        isSystem: Value(row['is_system'] as bool? ?? false),
        displayOrder: Value(row['display_order'] as int? ?? 0),
        updatedAt: Value(row['updated_at'] as String),
        deletedAt: Value(row['deleted_at'] as String?),
      ),
    );
  }

  Future<void> _upsertBudget(Map<String, dynamic> row) async {
    await _database
        .into(_database.budgets)
        .insertOnConflictUpdate(
          drift.BudgetsCompanion(
            id: Value(row['id'] as String),
            userId: Value(row['user_id'] as String),
            trackingPeriodId: Value(row['tracking_period_id'] as String),
            categoryId: Value(row['category_id'] as String?),
            amount: Value(row['amount'] as String),
            currency: Value(row['currency'] as String),
            alertThresholdWarning: Value(
              row['alert_threshold_warning'] as String,
            ),
            alertThresholdCritical: Value(
              row['alert_threshold_critical'] as String,
            ),
            notes: Value(row['notes'] as String?),
            updatedAt: Value(row['updated_at'] as String),
            deletedAt: Value(row['deleted_at'] as String?),
          ),
        );
  }

  Future<void> _upsertSavingsGoal(Map<String, dynamic> row) async {
    await _database
        .into(_database.savingsGoals)
        .insertOnConflictUpdate(
          drift.SavingsGoalsCompanion(
            id: Value(row['id'] as String),
            userId: Value(row['user_id'] as String),
            name: Value(row['name'] as String),
            description: Value(row['description'] as String?),
            icon: Value(row['icon'] as String?),
            color: Value(row['color'] as String?),
            targetAmount: Value(row['target_amount'] as String),
            currentAmount: Value(row['current_amount'] as String),
            currency: Value(row['currency'] as String),
            startDate: Value(row['start_date'] as String),
            targetDate: Value(row['target_date'] as String),
            status: Value(row['status'] as String),
            linkedAccountId: Value(row['linked_account_id'] as String?),
            achievedAt: Value(row['achieved_at'] as String?),
            updatedAt: Value(row['updated_at'] as String),
            deletedAt: Value(row['deleted_at'] as String?),
          ),
        );
  }

  Future<void> _upsertGoalContribution(Map<String, dynamic> row) async {
    await _database
        .into(_database.goalContributions)
        .insertOnConflictUpdate(
          drift.GoalContributionsCompanion(
            id: Value(row['id'] as String),
            userId: Value(row['user_id'] as String),
            savingsGoalId: Value(row['savings_goal_id'] as String),
            trackingPeriodId: Value(row['tracking_period_id'] as String),
            amount: Value(row['amount'] as String),
            contributionDate: Value(row['contribution_date'] as String),
            notes: Value(row['notes'] as String?),
            createdAt: Value(row['created_at'] as String),
            updatedAt: Value(row['updated_at'] as String),
            deletedAt: Value(row['deleted_at'] as String?),
          ),
        );
  }

  Future<void> _upsertRecurringTransaction(Map<String, dynamic> row) async {
    await _database
        .into(_database.recurringTransactions)
        .insertOnConflictUpdate(
          drift.RecurringTransactionsCompanion(
            id: Value(row['id'] as String),
            userId: Value(row['user_id'] as String),
            accountId: Value(row['account_id'] as String),
            categoryId: Value(row['category_id'] as String?),
            name: Value(row['name'] as String),
            transactionType: Value(row['transaction_type'] as String),
            amount: Value(row['amount'] as String),
            currency: Value(row['currency'] as String),
            description: Value(row['description'] as String?),
            frequency: Value(row['frequency'] as String),
            customIntervalDays: Value(row['custom_interval_days'] as int?),
            dayOfMonth: Value(row['day_of_month'] as int?),
            dayOfWeek: Value(row['day_of_week'] as int?),
            startDate: Value(row['start_date'] as String),
            endDate: Value(row['end_date'] as String?),
            // next_due_date is nullable server-side: the engine sets it to NULL
            // once a template runs past its end_date, and the wire type is
            // *string with omitempty, so the key is simply absent. The Drift
            // column is NOT NULL, so a raw cast here would throw and take the
            // whole pull down with it — not just recurring transactions.
            // Exhausted templates arrive with is_active = false and the UI
            // renders them as finished without reading this date, so falling
            // back to start_date is safe and avoids a schema migration.
            nextDueDate: Value(
              row['next_due_date'] as String? ?? row['start_date'] as String,
            ),
            isActive: Value(row['is_active'] as bool? ?? true),
            updatedAt: Value(row['updated_at'] as String),
            deletedAt: Value(row['deleted_at'] as String?),
          ),
        );
  }

  Future<void> _upsertTrackingPeriod(Map<String, dynamic> row) async {
    await _database.trackingPeriodsDao.upsert(
      drift.TrackingPeriodsCompanion(
        id: Value(row['id'] as String),
        userId: Value(row['user_id'] as String),
        sequenceNumber: Value(row['sequence_number'] as int),
        startDate: Value(row['start_date'] as String),
        endDate: Value(row['end_date'] as String),
        status: Value(row['status'] as String),
        configStartDay: Value(row['config_start_day'] as int),
        configDurationDays: Value(row['config_duration_days'] as int),
        closedAt: Value(row['closed_at'] as String?),
        updatedAt: Value(row['updated_at'] as String),
        deletedAt: Value(row['deleted_at'] as String?),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Push
  // -------------------------------------------------------------------------

  Future<SyncResult> _push() async {
    final allPending = await _database.transactionsDao.getPending();

    // A row created AND deleted locally before ever syncing never reached the
    // server — pushing a delete with its local-only id would be rejected.
    // Just drop it from the local DB.
    final pending = <drift.Transaction>[];
    for (final t in allPending) {
      if (_isLocalOnly(t) && t.deletedAt != null) {
        await (_database.delete(
          _database.transactions,
        )..where((r) => r.id.equals(t.id))).go();
        continue;
      }
      pending.add(t);
    }
    if (pending.isEmpty) return const SyncResult();

    int applied = 0;
    int conflicts = 0;
    int rejected = 0;

    // Process in chunks of _pushBatchSize.
    for (var i = 0; i < pending.length; i += _pushBatchSize) {
      final chunk = pending.skip(i).take(_pushBatchSize).toList();
      final items = chunk.map(_buildPushItem).toList();

      final response = await dio.post<Map<String, dynamic>>(
        '/sync/push',
        data: {'items': items.map((item) => item.toJson()).toList()},
      );
      final push = PushResponse.fromJson(response.data!);

      // Map client_ref back to the local transaction row.
      final refToRow = {for (final t in chunk) _clientRef(t): t};

      for (final result in push.results) {
        final localRow = refToRow[result.clientRef];
        if (localRow == null) continue;

        switch (result.status) {
          case 'applied':
          case 'skipped':
            final se = result.serverEntity;
            if (se != null) {
              final serverId = se['id'] as String;
              final serverUpdatedAt = se['updated_at'] as String;
              await _database.transactionsDao.markSynced(
                localRow.id,
                serverId: serverId,
                updatedAt: serverUpdatedAt,
              );
            } else {
              // Delete results carry no server_entity — mark the soft-deleted
              // local row as synced so it leaves the outbox instead of being
              // re-pushed forever.
              await (_database.update(
                _database.transactions,
              )..where((t) => t.id.equals(localRow.id))).write(
                const drift.TransactionsCompanion(syncStatus: Value('synced')),
              );
            }
            applied++;

          case 'conflict':
            // LWW: server wins — apply server_entity to the local row.
            final se = result.serverEntity;
            if (se != null) {
              await _upsertTransaction(se);
            }
            conflicts++;

          case 'rejected':
            // Cannot be retried as-is; mark the row as conflict so the UI
            // can surface the error message.
            await (_database.update(
              _database.transactions,
            )..where((t) => t.id.equals(localRow.id))).write(
              const drift.TransactionsCompanion(syncStatus: Value('conflict')),
            );
            rejected++;
        }
      }
    }

    return SyncResult(
      pushApplied: applied,
      pushConflicts: conflicts,
      pushRejected: rejected,
    );
  }

  /// Builds a PushItem from a local drift.Transaction row.
  PushItem _buildPushItem(drift.Transaction t) {
    final String operation;
    if (t.deletedAt != null) {
      operation = 'delete';
    } else if (_isLocalOnly(t)) {
      operation = 'create';
    } else {
      operation = 'update';
    }

    Map<String, dynamic>? payload;
    if (operation != 'delete') {
      payload = {
        'account_id': t.accountId,
        'transaction_type': t.transactionType,
        'amount': t.amount,
        'currency': t.currency,
        if (t.categoryId != null) 'category_id': t.categoryId,
        if (t.description != null) 'description': t.description,
        if (t.notes != null) 'notes': t.notes,
        'transaction_date': t.transactionDate,
        if (t.transferAccountId != null)
          'transfer_account_id': t.transferAccountId,
        if (t.clientId != null) 'client_id': t.clientId,
        // AI auto-categorization metadata. Confidence is the stored TEXT
        // decimal; nulls are omitted consistently with the other fields.
        'ai_categorized': t.aiCategorized,
        if (t.aiConfidence != null) 'ai_confidence': t.aiConfidence,
        if (t.aiSuggestedCategoryId != null)
          'ai_suggested_category_id': t.aiSuggestedCategoryId,
      };
    }

    return PushItem(
      clientRef: _clientRef(t),
      entityType: 'transaction',
      operation: operation,
      entityId: operation != 'create' ? t.id : null,
      clientUpdatedAt: operation == 'update' ? t.updatedAt : null,
      transactionPayload: payload,
    );
  }

  /// A "local-only" transaction has a locally-generated id — i.e. anything
  /// that is not a server-assigned UUID. The app generates `local-<uuid>` ids
  /// and older overlay builds generated `ov-<millis>`. Classifying these as
  /// updates would send a non-UUID entity_id to the server; before the
  /// per-item tolerance fix that 400'd the WHOLE batch and wedged the outbox.
  bool _isLocalOnly(drift.Transaction t) =>
      t.id.startsWith('local-') || t.id.startsWith('ov-');

  /// Stable client_ref for a row — used to correlate push results.
  String _clientRef(drift.Transaction t) => 'tx-${t.id}';
}

// ---------------------------------------------------------------------------
// Outbox helpers — called by LocalTransactionRepository before push
// ---------------------------------------------------------------------------

/// Generates a new client_id for a transaction that will be pushed.
String generateClientId() => 'mobile-${const Uuid().v4()}';

/// Generates a local-only id used while the transaction is in the outbox
/// before the server assigns a real UUID.
String generateLocalId() => 'local-${const Uuid().v4()}';

// ---------------------------------------------------------------------------
// Error formatting
// ---------------------------------------------------------------------------

String _dioError(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic> && data['error'] is String) {
    return data['error'] as String;
  }
  return e.message ?? e.type.name;
}
