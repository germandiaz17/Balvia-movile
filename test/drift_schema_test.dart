// Drift schema and DAO tests — use an in-memory SQLite database so no file
// system access is needed and tests run fast everywhere.
//
// Covers:
//  - Upsert / conflict update semantics
//  - soft-delete of transactions
//  - markSynced (including id replacement)
//  - getPending outbox query
//  - SyncMetadataDao cursor persistence
//  - watchByPeriod only returns non-deleted rows

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balvia_mobile/data/local/app_database.dart' as dblib;

// In-memory database helper.
dblib.AppDatabase _openTestDb() => dblib.AppDatabase(NativeDatabase.memory());

void main() {
  late dblib.AppDatabase db;

  setUp(() {
    db = _openTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // SyncMetadataDao
  // ---------------------------------------------------------------------------

  group('SyncMetadataDao', () {
    test('get returns null when table is empty', () async {
      expect(await db.syncMetadataDao.get(), isNull);
    });

    test('setLastSyncedAt inserts and get returns the value', () async {
      await db.syncMetadataDao.setLastSyncedAt('2026-07-10T01:32:33Z');
      final meta = await db.syncMetadataDao.get();
      expect(meta, isNotNull);
      expect(meta!.lastSyncedAt, '2026-07-10T01:32:33Z');
    });

    test('setLastSyncedAt updates existing row (upsert)', () async {
      await db.syncMetadataDao.setLastSyncedAt('2026-07-01T00:00:00Z');
      await db.syncMetadataDao.setLastSyncedAt('2026-07-10T01:32:33Z');
      final meta = await db.syncMetadataDao.get();
      expect(meta!.lastSyncedAt, '2026-07-10T01:32:33Z');
      // Only one row in the table.
      final all = await db.select(db.syncMetadata).get();
      expect(all, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // TransactionsDao
  // ---------------------------------------------------------------------------

  group('TransactionsDao', () {
    dblib.TransactionsCompanion makeTxn({
      required String id,
      String status = 'synced',
      String? deletedAt,
      String trackingPeriodId = 'tp-1',
      String? clientId,
    }) => dblib.TransactionsCompanion.insert(
      id: id,
      userId: 'u-1',
      trackingPeriodId: trackingPeriodId,
      accountId: 'acc-1',
      transactionType: 'expense',
      amount: '5000.00',
      currency: 'COP',
      transactionDate: '2026-07-09',
      createdAt: '2026-07-09T12:00:00Z',
      updatedAt: '2026-07-09T12:00:00Z',
      syncStatus: drift.Value(status),
      deletedAt: drift.Value(deletedAt),
      clientId: drift.Value(clientId),
    );

    test('upsert inserts a new row', () async {
      await db.transactionsDao.upsert(makeTxn(id: 'tx-1'));
      final rows = await db.select(db.transactions).get();
      expect(rows, hasLength(1));
      expect(rows.first.id, 'tx-1');
    });

    test('upsert replaces an existing row (idempotent)', () async {
      await db.transactionsDao.upsert(makeTxn(id: 'tx-1', status: 'pending'));
      await db.transactionsDao.upsert(makeTxn(id: 'tx-1', status: 'synced'));
      final rows = await db.select(db.transactions).get();
      expect(rows, hasLength(1));
      expect(rows.first.syncStatus, 'synced');
    });

    test('getByPeriod excludes deleted rows', () async {
      await db.transactionsDao.upsert(makeTxn(id: 'tx-1'));
      await db.transactionsDao.upsert(
        makeTxn(id: 'tx-2', deletedAt: '2026-07-09T13:00:00Z'),
      );
      final rows = await db.transactionsDao.getByPeriod('tp-1');
      expect(rows, hasLength(1));
      expect(rows.first.id, 'tx-1');
    });

    test('getByPeriod only returns rows for the given period', () async {
      await db.transactionsDao.upsert(
        makeTxn(id: 'tx-1', trackingPeriodId: 'tp-1'),
      );
      await db.transactionsDao.upsert(
        makeTxn(id: 'tx-2', trackingPeriodId: 'tp-2'),
      );
      expect(await db.transactionsDao.getByPeriod('tp-1'), hasLength(1));
      expect(await db.transactionsDao.getByPeriod('tp-2'), hasLength(1));
    });

    test('getPending returns only rows with sync_status = pending', () async {
      await db.transactionsDao.upsert(makeTxn(id: 'tx-1', status: 'synced'));
      await db.transactionsDao.upsert(makeTxn(id: 'tx-2', status: 'pending'));
      await db.transactionsDao.upsert(makeTxn(id: 'tx-3', status: 'conflict'));
      final pending = await db.transactionsDao.getPending();
      expect(pending, hasLength(1));
      expect(pending.first.id, 'tx-2');
    });

    test('softDelete sets deleted_at and marks pending', () async {
      await db.transactionsDao.upsert(makeTxn(id: 'tx-1', status: 'synced'));
      await db.transactionsDao.softDelete('tx-1', '2026-07-09T13:00:00Z');
      final row = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals('tx-1'))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(row.syncStatus, 'pending');
    });

    test('markSynced updates sync_status to synced', () async {
      await db.transactionsDao.upsert(makeTxn(id: 'tx-1', status: 'pending'));
      await db.transactionsDao.markSynced(
        'tx-1',
        serverId: 'tx-1',
        updatedAt: '2026-07-09T12:01:00Z',
      );
      final row = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals('tx-1'))).getSingle();
      expect(row.syncStatus, 'synced');
    });

    test('markSynced with different serverId replaces the row id', () async {
      // Simulate: a local-only row gets a server UUID after push applied.
      await db.transactionsDao.upsert(
        makeTxn(id: 'local-abc', status: 'pending'),
      );
      await db.transactionsDao.markSynced(
        'local-abc',
        serverId: 'server-uuid-1',
        updatedAt: '2026-07-09T12:01:00Z',
      );
      // Old id should be gone.
      final old = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals('local-abc'))).getSingleOrNull();
      expect(old, isNull);
      // New id should exist and be synced.
      final newRow = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals('server-uuid-1'))).getSingleOrNull();
      expect(newRow, isNotNull);
      expect(newRow!.syncStatus, 'synced');
    });
  });

  // ---------------------------------------------------------------------------
  // AccountsDao
  // ---------------------------------------------------------------------------

  group('AccountsDao', () {
    dblib.AccountsCompanion makeAccount(String id, {bool archived = false}) =>
        dblib.AccountsCompanion.insert(
          id: id,
          userId: 'u-1',
          name: 'Cuenta $id',
          accountType: 'cash',
          currency: 'COP',
          initialBalance: '0.00',
          currentBalance: '50000.00',
          updatedAt: '2026-07-09T12:00:00Z',
          isArchived: drift.Value(archived),
        );

    test('getAll excludes archived accounts', () async {
      await db.accountsDao.upsert(makeAccount('a-1'));
      await db.accountsDao.upsert(makeAccount('a-2', archived: true));
      final all = await db.accountsDao.getAll();
      expect(all, hasLength(1));
      expect(all.first.id, 'a-1');
    });

    test('getAll excludes soft-deleted accounts', () async {
      await db.accountsDao.upsert(makeAccount('a-1'));
      await db.accountsDao.upsert(
        makeAccount(
          'a-2',
        ).copyWith(deletedAt: const drift.Value('2026-07-09T12:00:00Z')),
      );
      final all = await db.accountsDao.getAll();
      expect(all, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // CategoriesDao
  // ---------------------------------------------------------------------------

  group('CategoriesDao', () {
    dblib.CategoriesCompanion makeCategory(String id) =>
        dblib.CategoriesCompanion.insert(
          id: id,
          userId: 'u-1',
          name: 'Cat $id',
          categoryType: 'expense',
          updatedAt: '2026-07-09T12:00:00Z',
        );

    test('getAll returns non-deleted categories', () async {
      await db.categoriesDao.upsert(makeCategory('cat-1'));
      await db.categoriesDao.upsert(
        makeCategory(
          'cat-2',
        ).copyWith(deletedAt: const drift.Value('2026-07-09T12:00:00Z')),
      );
      final all = await db.categoriesDao.getAll();
      expect(all, hasLength(1));
      expect(all.first.id, 'cat-1');
    });
  });

  // ---------------------------------------------------------------------------
  // TrackingPeriodsDao
  // ---------------------------------------------------------------------------

  group('TrackingPeriodsDao', () {
    dblib.TrackingPeriodsCompanion makePeriod(String id, String status) =>
        dblib.TrackingPeriodsCompanion.insert(
          id: id,
          userId: 'u-1',
          sequenceNumber: 1,
          startDate: '2026-07-04',
          endDate: '2026-08-02',
          status: status,
          configStartDay: 4,
          configDurationDays: 30,
          updatedAt: '2026-07-09T12:00:00Z',
        );

    test('getActive returns the active period', () async {
      await db.trackingPeriodsDao.upsert(makePeriod('tp-active', 'active'));
      await db.trackingPeriodsDao.upsert(makePeriod('tp-closed', 'closed'));
      final active = await db.trackingPeriodsDao.getActive();
      expect(active, isNotNull);
      expect(active!.id, 'tp-active');
    });

    test('getActive returns null when no active period exists', () async {
      await db.trackingPeriodsDao.upsert(makePeriod('tp-closed', 'closed'));
      final active = await db.trackingPeriodsDao.getActive();
      expect(active, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // AI auto-categorization metadata
  // ---------------------------------------------------------------------------

  group('AI categorization metadata columns', () {
    test(
      'defaults: ai_categorized false, confidence + suggested id null',
      () async {
        await db.transactionsDao.upsert(
          dblib.TransactionsCompanion.insert(
            id: 'tx-ai-default',
            userId: 'u-1',
            trackingPeriodId: 'tp-1',
            accountId: 'acc-1',
            transactionType: 'expense',
            amount: '1000.00',
            currency: 'COP',
            transactionDate: '2026-07-09',
            createdAt: '2026-07-09T12:00:00Z',
            updatedAt: '2026-07-09T12:00:00Z',
          ),
        );
        final row = await (db.select(
          db.transactions,
        )..where((t) => t.id.equals('tx-ai-default'))).getSingle();
        expect(row.aiCategorized, isFalse);
        expect(row.aiConfidence, isNull);
        expect(row.aiSuggestedCategoryId, isNull);
      },
    );

    test('round-trips ai metadata (confidence as TEXT decimal)', () async {
      await db.transactionsDao.upsert(
        dblib.TransactionsCompanion.insert(
          id: 'tx-ai-1',
          userId: 'u-1',
          trackingPeriodId: 'tp-1',
          accountId: 'acc-1',
          transactionType: 'expense',
          amount: '1000.00',
          currency: 'COP',
          transactionDate: '2026-07-09',
          createdAt: '2026-07-09T12:00:00Z',
          updatedAt: '2026-07-09T12:00:00Z',
          aiCategorized: const drift.Value(true),
          aiConfidence: const drift.Value('0.7200'),
          aiSuggestedCategoryId: const drift.Value('cat-food'),
        ),
      );
      final row = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals('tx-ai-1'))).getSingle();
      expect(row.aiCategorized, isTrue);
      expect(row.aiConfidence, '0.7200');
      expect(Decimal.parse(row.aiConfidence!), Decimal.parse('0.72'));
      expect(row.aiSuggestedCategoryId, 'cat-food');
    });
  });

  // ---------------------------------------------------------------------------
  // Money precision
  // ---------------------------------------------------------------------------

  group('Money stored as TEXT — no float rounding', () {
    test('amount round-trips exactly as string (never double)', () async {
      final companion = dblib.TransactionsCompanion.insert(
        id: 'tx-money',
        userId: 'u-1',
        trackingPeriodId: 'tp-1',
        accountId: 'acc-1',
        transactionType: 'expense',
        amount: '999999.99', // large COP amount
        currency: 'COP',
        transactionDate: '2026-07-09',
        createdAt: '2026-07-09T12:00:00Z',
        updatedAt: '2026-07-09T12:00:00Z',
      );
      await db.transactionsDao.upsert(companion);
      final row = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals('tx-money'))).getSingle();
      // Verify the text value survived unchanged.
      expect(row.amount, '999999.99');
      // Parse to Decimal — must be exact.
      expect(Decimal.parse(row.amount), Decimal.parse('999999.99'));
    });
  });
}
