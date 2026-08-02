/// Regression tests for pulling recurring transactions into Drift.
///
/// The backend nulls next_due_date once a template runs past its end_date
/// (recurring_engine.go sets `NextDueDate: pgtype.Date{}`), and the wire type is
/// `*string` with omitempty, so the key is simply absent from the JSON. The
/// Drift column is NOT NULL. A raw cast used to throw; _applyPull swallows the
/// exception per row, so the template was silently dropped and never came back —
/// the cursor advances past it regardless.
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balvia_mobile/data/local/app_database.dart' as dblib;
import 'package:balvia_mobile/data/sync/sync_engine.dart';

import 'fake_http_adapter.dart';

void main() {
  late dblib.AppDatabase db;

  setUp(() => db = dblib.AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Map<String, dynamic> recurringRow({
    String id = 'rec-1',
    required bool withNextDueDate,
    bool isActive = true,
  }) => <String, dynamic>{
    'id': id,
    'user_id': 'user-1',
    'account_id': 'acc-1',
    'category_id': 'cat-1',
    'name': 'Arriendo',
    'transaction_type': 'expense',
    'amount': '1500000.00',
    'currency': 'COP',
    'description': null,
    'frequency': 'monthly',
    'custom_interval_days': null,
    'day_of_month': 5,
    'day_of_week': null,
    'start_date': '2026-01-05',
    'end_date': '2026-07-05',
    // omitempty: the key is absent, not null, when the engine has exhausted it.
    if (withNextDueDate) 'next_due_date': '2026-08-05',
    'is_active': isActive,
    'updated_at': '2026-08-01T10:00:00Z',
    'deleted_at': null,
  };

  Map<String, dynamic> pullBody(List<Map<String, dynamic>> recurring) => {
    'server_time': '2026-08-01T12:00:00Z',
    'has_more': false,
    'transactions': <dynamic>[],
    'accounts': <dynamic>[],
    'categories': <dynamic>[],
    'budgets': <dynamic>[],
    'savings_goals': <dynamic>[],
    'goal_contributions': <dynamic>[],
    'recurring_transactions': recurring,
    'tracking_periods': <dynamic>[],
  };

  SyncEngine buildEngine(List<Map<String, dynamic>> recurring) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))
      ..httpClientAdapter = FakeHttpAdapter([
        FakeResponse(body: pullBody(recurring)),
      ]);
    return SyncEngine(db: db, dio: dio);
  }

  test(
    'an exhausted template (no next_due_date) still lands in Drift',
    () async {
      final engine = buildEngine([recurringRow(withNextDueDate: false)]);

      final upserted = await engine.pullOnly();

      expect(upserted, 1, reason: 'the row must not be skipped');

      final rows = await db.select(db.recurringTransactions).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'rec-1');
      // Falls back to start_date; the UI reads is_active, not this date, to know
      // the template is finished.
      expect(rows.single.nextDueDate, '2026-01-05');
    },
  );

  test('a live template keeps its real next_due_date', () async {
    final engine = buildEngine([recurringRow(withNextDueDate: true)]);

    await engine.pullOnly();

    final rows = await db.select(db.recurringTransactions).get();
    expect(rows.single.nextDueDate, '2026-08-05');
  });

  test(
    'an explicit null next_due_date is handled like an absent one',
    () async {
      final row = recurringRow(withNextDueDate: false)
        ..['next_due_date'] = null;
      final engine = buildEngine([row]);

      expect(await engine.pullOnly(), 1);
      final rows = await db.select(db.recurringTransactions).get();
      expect(rows.single.nextDueDate, '2026-01-05');
    },
  );

  test('a mix of live and exhausted templates all persist', () async {
    final engine = buildEngine([
      recurringRow(id: 'rec-live', withNextDueDate: true),
      recurringRow(id: 'rec-done', withNextDueDate: false, isActive: false),
    ]);

    expect(await engine.pullOnly(), 2);

    final rows = await db.select(db.recurringTransactions).get()
      ..sort((a, b) => a.id.compareTo(b.id));
    expect(rows.map((r) => r.id), ['rec-done', 'rec-live']);
    expect(rows.first.isActive, isFalse);
    expect(rows.first.nextDueDate, '2026-01-05');
    expect(rows.last.nextDueDate, '2026-08-05');
  });
}
