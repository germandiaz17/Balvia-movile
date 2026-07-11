// Drift table definitions for Balvia's local SQLite database.
//
// Design rules:
//  - Money stored as TEXT (Decimal serialised to string) — NEVER real/double.
//  - Every table mirroring a server entity has `updated_at` and `deleted_at`
//    columns for the sync pull protocol.
//  - The `transactions` table additionally has `client_id` (idempotency key for
//    push) and `sync_status` (synced | pending | conflict) for the outbox.
//  - UUIDs are stored as TEXT; primary keys are NOT auto-generated integers —
//    the server UUID is the canonical key.

import 'package:drift/drift.dart';

// ---------------------------------------------------------------------------
// sync_status values (stored as TEXT in the transactions table)
// ---------------------------------------------------------------------------

/// String constants for the sync_status column in the transactions table.
///
///  - [synced]  : row is in sync with the server (default after pull/push).
///  - [pending] : local mutation not yet pushed.
///  - [conflict]: server rejected the push with "conflict" or "rejected" status.
abstract final class SyncStatusValues {
  static const synced = 'synced';
  static const pending = 'pending';
  static const conflict = 'conflict';
}

// ---------------------------------------------------------------------------
// tracking_periods
// ---------------------------------------------------------------------------

class TrackingPeriods extends Table {
  // Server UUID.
  TextColumn get id => text()();

  TextColumn get userId => text().named('user_id')();
  IntColumn get sequenceNumber => integer().named('sequence_number')();

  // YYYY-MM-DD strings.
  TextColumn get startDate => text().named('start_date')();
  TextColumn get endDate => text().named('end_date')();

  // active | closed
  TextColumn get status => text()();

  IntColumn get configStartDay => integer().named('config_start_day')();
  IntColumn get configDurationDays =>
      integer().named('config_duration_days')();

  // RFC3339 nullable — null when active.
  TextColumn get closedAt => text().named('closed_at').nullable()();

  // Sync columns.
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// accounts
// ---------------------------------------------------------------------------

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get name => text()();

  // cash | checking | savings | credit_card | investment | other
  TextColumn get accountType => text().named('account_type')();

  TextColumn get currency => text()();

  // Money as TEXT — parsed to Decimal in the repository layer.
  TextColumn get initialBalance => text().named('initial_balance')();
  TextColumn get currentBalance => text().named('current_balance')();

  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()();
  IntColumn get displayOrder => integer().named('display_order').withDefault(const Constant(0))();
  BoolColumn get isArchived =>
      boolean().named('is_archived').withDefault(const Constant(false))();

  // Sync columns.
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// categories
// ---------------------------------------------------------------------------

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get parentId => text().named('parent_id').nullable()();
  TextColumn get name => text()();

  // income | expense | transfer
  TextColumn get categoryType => text().named('category_type')();

  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()();
  BoolColumn get isSystem =>
      boolean().named('is_system').withDefault(const Constant(false))();
  IntColumn get displayOrder =>
      integer().named('display_order').withDefault(const Constant(0))();

  // Sync columns.
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// transactions
// ---------------------------------------------------------------------------

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get trackingPeriodId => text().named('tracking_period_id')();
  TextColumn get accountId => text().named('account_id')();
  TextColumn get categoryId => text().named('category_id').nullable()();

  // income | expense | transfer
  TextColumn get transactionType => text().named('transaction_type')();

  // Money as TEXT.
  TextColumn get amount => text()();
  TextColumn get currency => text()();

  TextColumn get description => text().nullable()();
  TextColumn get notes => text().nullable()();

  // YYYY-MM-DD
  TextColumn get transactionDate => text().named('transaction_date')();

  TextColumn get transferAccountId =>
      text().named('transfer_account_id').nullable()();

  // Client-generated idempotency key (UUID). Set locally before push.
  TextColumn get clientId => text().named('client_id').nullable()();

  // Server-managed recurring fields.
  TextColumn get recurringTransactionId =>
      text().named('recurring_transaction_id').nullable()();
  TextColumn get occurrenceDate => text().named('occurrence_date').nullable()();

  // RFC3339.
  TextColumn get createdAt => text().named('created_at')();

  // Sync columns.
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();

  // Outbox state: synced | pending | conflict
  TextColumn get syncStatus =>
      text().named('sync_status').withDefault(const Constant('synced'))();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// budgets
// ---------------------------------------------------------------------------

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get trackingPeriodId => text().named('tracking_period_id')();
  TextColumn get categoryId => text().named('category_id').nullable()();

  // Money as TEXT.
  TextColumn get amount => text()();
  TextColumn get currency => text()();

  // Alert thresholds stored as TEXT (percentage string).
  TextColumn get alertThresholdWarning =>
      text().named('alert_threshold_warning')();
  TextColumn get alertThresholdCritical =>
      text().named('alert_threshold_critical')();

  TextColumn get notes => text().nullable()();

  // Sync columns.
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// savings_goals
// ---------------------------------------------------------------------------

class SavingsGoals extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get icon => text().nullable()();
  TextColumn get color => text().nullable()();

  // Money as TEXT.
  TextColumn get targetAmount => text().named('target_amount')();
  TextColumn get currentAmount => text().named('current_amount')();

  TextColumn get currency => text()();

  // YYYY-MM-DD.
  TextColumn get startDate => text().named('start_date')();
  TextColumn get targetDate => text().named('target_date')();

  // active | achieved | abandoned | paused
  TextColumn get status => text()();

  TextColumn get linkedAccountId =>
      text().named('linked_account_id').nullable()();

  // RFC3339 nullable.
  TextColumn get achievedAt => text().named('achieved_at').nullable()();

  // Sync columns.
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// goal_contributions
// ---------------------------------------------------------------------------

class GoalContributions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get savingsGoalId => text().named('savings_goal_id')();
  TextColumn get trackingPeriodId => text().named('tracking_period_id')();

  // Money as TEXT.
  TextColumn get amount => text()();

  // YYYY-MM-DD.
  TextColumn get contributionDate => text().named('contribution_date')();

  TextColumn get notes => text().nullable()();

  // RFC3339.
  TextColumn get createdAt => text().named('created_at')();

  // Sync columns.
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// recurring_transactions
// ---------------------------------------------------------------------------

class RecurringTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().named('user_id')();
  TextColumn get accountId => text().named('account_id')();
  TextColumn get categoryId => text().named('category_id').nullable()();
  TextColumn get name => text()();

  // income | expense
  TextColumn get transactionType => text().named('transaction_type')();

  // Money as TEXT.
  TextColumn get amount => text()();
  TextColumn get currency => text()();

  TextColumn get description => text().nullable()();

  // daily | weekly | biweekly | monthly | yearly | custom
  TextColumn get frequency => text()();

  IntColumn get customIntervalDays =>
      integer().named('custom_interval_days').nullable()();
  IntColumn get dayOfMonth => integer().named('day_of_month').nullable()();
  IntColumn get dayOfWeek => integer().named('day_of_week').nullable()();

  // YYYY-MM-DD.
  TextColumn get startDate => text().named('start_date')();
  TextColumn get endDate => text().named('end_date').nullable()();
  TextColumn get nextDueDate => text().named('next_due_date')();

  BoolColumn get isActive =>
      boolean().named('is_active').withDefault(const Constant(true))();

  // Sync columns.
  TextColumn get updatedAt => text().named('updated_at')();
  TextColumn get deletedAt => text().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// sync_metadata — single-row table to persist the sync cursor.
// ---------------------------------------------------------------------------

/// Stores the sync cursor (server_time from the last successful pull) and
/// any app-wide sync state. The table always has exactly one row with key = 1.
class SyncMetadata extends Table {
  // Singleton row — always key = 1.
  IntColumn get id => integer()();

  // RFC3339 string of the last successful full pull's server_time.
  // null on first launch (triggers a full sync from epoch).
  TextColumn get lastSyncedAt => text().named('last_synced_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
