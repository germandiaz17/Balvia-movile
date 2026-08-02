/// Tests for RecurringTransactionRepository request bodies.
///
/// The important behaviour is that frequency-specific hints only travel when
/// the chosen frequency uses them — switching monthly → weekly must not leave a
/// stale day_of_month behind, since the PUT is a full replace.
library;

import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/repositories/recurring_transaction_repository.dart';

import 'fake_http_adapter.dart';

void main() {
  Map<String, dynamic> payload({
    String id = 'rec-1',
    String frequency = 'monthly',
    int? dayOfMonth = 5,
    int? dayOfWeek,
    int? customIntervalDays,
    bool includeNextDueDate = true,
  }) => <String, dynamic>{
    'id': id,
    'account_id': 'acc-1',
    'category_id': null,
    'name': 'Arriendo',
    'transaction_type': 'expense',
    'amount': '1500000.00',
    'currency': 'COP',
    'description': null,
    'frequency': frequency,
    'custom_interval_days': customIntervalDays,
    'day_of_month': dayOfMonth,
    'day_of_week': dayOfWeek,
    'start_date': '2026-01-05',
    'end_date': null,
    if (includeNextDueDate) 'next_due_date': '2026-08-05',
    'is_active': true,
  };

  (RecurringTransactionRepository, FakeHttpAdapter) build(
    List<FakeResponse> responses,
  ) {
    final adapter = FakeHttpAdapter(responses);
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))
      ..httpClientAdapter = adapter;
    return (RecurringTransactionRepository(dio), adapter);
  }

  group('list', () {
    test('reads the recurring_transactions envelope', () async {
      final (repo, adapter) = build([
        FakeResponse(
          body: {
            'recurring_transactions': [payload(), payload(id: 'rec-2')],
            'count': 2,
          },
        ),
      ]);

      final items = await repo.list();

      expect(items, hasLength(2));
      expect(items.first.name, 'Arriendo');
      expect(adapter.request.method, 'GET');
      expect(adapter.request.path, '/recurring-transactions');
    });

    test('parses an exhausted template with no next_due_date', () async {
      final (repo, _) = build([
        FakeResponse(
          body: {
            'recurring_transactions': [payload(includeNextDueDate: false)],
            'count': 1,
          },
        ),
      ]);

      final items = await repo.list();
      expect(items.single.nextDueDate, isNull);
      expect(items.single.isFinished, isTrue);
    });
  });

  group('create body', () {
    test('monthly sends day_of_month and nothing else', () async {
      final (repo, adapter) = build([
        FakeResponse(body: payload(), statusCode: 201),
      ]);

      await repo.create(
        accountId: 'acc-1',
        name: 'Arriendo',
        transactionType: 'expense',
        amount: Decimal.parse('1500000'),
        frequency: 'monthly',
        startDate: DateTime(2026, 1, 5),
        dayOfMonth: 5,
        // Deliberately passed too — they must be dropped for this frequency.
        dayOfWeek: 3,
        customIntervalDays: 10,
      );

      final body = adapter.request.body!;
      expect(adapter.request.method, 'POST');
      expect(body['frequency'], 'monthly');
      expect(body['day_of_month'], 5);
      expect(body['day_of_week'], isNull);
      expect(body['custom_interval_days'], isNull);
      expect(body['amount'], '1500000.00');
      expect(body['start_date'], '2026-01-05');
      expect(body['currency'], 'COP');
      expect(body['is_active'], isTrue);
    });

    test('weekly sends day_of_week and drops day_of_month', () async {
      final (repo, adapter) = build([
        FakeResponse(body: payload(), statusCode: 201),
      ]);

      await repo.create(
        accountId: 'acc-1',
        name: 'Mercado',
        transactionType: 'expense',
        amount: Decimal.parse('200000'),
        frequency: 'weekly',
        startDate: DateTime(2026, 1, 5),
        dayOfMonth: 5,
        dayOfWeek: 1,
      );

      final body = adapter.request.body!;
      expect(body['day_of_week'], 1);
      expect(body['day_of_month'], isNull);
    });

    test(
      'day_of_week 0 (Sunday) survives — it is not treated as unset',
      () async {
        final (repo, adapter) = build([
          FakeResponse(body: payload(), statusCode: 201),
        ]);

        await repo.create(
          accountId: 'acc-1',
          name: 'Domingo',
          transactionType: 'expense',
          amount: Decimal.parse('1000'),
          frequency: 'biweekly',
          startDate: DateTime(2026, 1, 4),
          dayOfWeek: 0,
        );

        expect(adapter.request.body!['day_of_week'], 0);
      },
    );

    test('custom sends the interval and drops the day hints', () async {
      final (repo, adapter) = build([
        FakeResponse(body: payload(), statusCode: 201),
      ]);

      await repo.create(
        accountId: 'acc-1',
        name: 'Cada 10 días',
        transactionType: 'expense',
        amount: Decimal.parse('50000'),
        frequency: 'custom',
        startDate: DateTime(2026, 1, 5),
        customIntervalDays: 10,
        dayOfMonth: 5,
        dayOfWeek: 3,
      );

      final body = adapter.request.body!;
      expect(body['custom_interval_days'], 10);
      expect(body['day_of_month'], isNull);
      expect(body['day_of_week'], isNull);
    });

    test('daily sends no frequency hints at all', () async {
      final (repo, adapter) = build([
        FakeResponse(body: payload(), statusCode: 201),
      ]);

      await repo.create(
        accountId: 'acc-1',
        name: 'Café',
        transactionType: 'expense',
        amount: Decimal.parse('5000'),
        frequency: 'daily',
        startDate: DateTime(2026, 1, 5),
        dayOfMonth: 5,
        dayOfWeek: 3,
        customIntervalDays: 10,
      );

      final body = adapter.request.body!;
      expect(body['day_of_month'], isNull);
      expect(body['day_of_week'], isNull);
      expect(body['custom_interval_days'], isNull);
    });

    test('an end_date travels as YYYY-MM-DD, and null when absent', () async {
      final (repo, adapter) = build([
        FakeResponse(body: payload(), statusCode: 201),
        FakeResponse(body: payload(), statusCode: 201),
      ]);

      await repo.create(
        accountId: 'acc-1',
        name: 'Con fin',
        transactionType: 'expense',
        amount: Decimal.parse('1000'),
        frequency: 'monthly',
        startDate: DateTime(2026, 1, 5),
        endDate: DateTime(2027, 1, 5),
      );
      expect(adapter.requests.first.body!['end_date'], '2027-01-05');

      await repo.create(
        accountId: 'acc-1',
        name: 'Sin fin',
        transactionType: 'expense',
        amount: Decimal.parse('1000'),
        frequency: 'monthly',
        startDate: DateTime(2026, 1, 5),
      );
      expect(adapter.requests.last.body!['end_date'], isNull);
    });
  });

  group('update', () {
    test('sends the full replace body the backend requires', () async {
      final (repo, adapter) = build([FakeResponse(body: payload())]);

      await repo.update(
        'rec-1',
        accountId: 'acc-1',
        name: 'Arriendo',
        transactionType: 'expense',
        amount: Decimal.parse('1600000'),
        frequency: 'monthly',
        startDate: DateTime(2026, 1, 5),
        dayOfMonth: 5,
        isActive: false,
      );

      final req = adapter.request;
      expect(req.method, 'PUT');
      expect(req.path, '/recurring-transactions/rec-1');
      // recurringRequest marks these as required.
      expect(req.body!['account_id'], 'acc-1');
      expect(req.body!['name'], 'Arriendo');
      expect(req.body!['transaction_type'], 'expense');
      expect(req.body!['amount'], '1600000.00');
      expect(req.body!['frequency'], 'monthly');
      expect(req.body!['start_date'], '2026-01-05');
      expect(req.body!['is_active'], isFalse);
    });

    test('never sends next_due_date — the engine owns it', () async {
      final (repo, adapter) = build([FakeResponse(body: payload())]);

      await repo.update(
        'rec-1',
        accountId: 'acc-1',
        name: 'Arriendo',
        transactionType: 'expense',
        amount: Decimal.parse('1000'),
        frequency: 'monthly',
        startDate: DateTime(2026, 1, 5),
      );

      expect(adapter.request.body!.containsKey('next_due_date'), isFalse);
    });
  });

  group('delete', () {
    test('hits DELETE on the template path', () async {
      final (repo, adapter) = build([
        FakeResponse(body: <String, dynamic>{}, statusCode: 204),
      ]);

      await repo.delete('rec-1');

      expect(adapter.request.method, 'DELETE');
      expect(adapter.request.path, '/recurring-transactions/rec-1');
    });
  });
}
