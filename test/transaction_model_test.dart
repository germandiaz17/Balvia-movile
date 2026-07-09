import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/transaction.dart';

void main() {
  final sampleJson = {
    'id': 'tx-1',
    'tracking_period_id': 'tp-1',
    'account_id': 'acc-1',
    'category_id': null,
    'transaction_type': 'expense',
    'amount': '15000.00',
    'currency': 'COP',
    'description': 'Almuerzo',
    'notes': null,
    'transaction_date': '2026-07-08',
    'transfer_account_id': null,
    'client_id': null,
    'recurring_transaction_id': null,
    'occurrence_date': null,
    'created_at': '2026-07-08T14:30:00Z',
  };

  group('Transaction.fromJson', () {
    test('parses amount as Decimal (never double)', () {
      final tx = Transaction.fromJson(sampleJson);
      expect(tx.amount, isA<Decimal>());
      expect(tx.amount, Decimal.parse('15000.00'));
    });

    test('parses basic fields correctly', () {
      final tx = Transaction.fromJson(sampleJson);
      expect(tx.id, 'tx-1');
      expect(tx.accountId, 'acc-1');
      expect(tx.transactionType, 'expense');
      expect(tx.currency, 'COP');
      expect(tx.description, 'Almuerzo');
      expect(tx.categoryId, isNull);
    });

    test('nullable fields are null when absent from JSON', () {
      final tx = Transaction.fromJson(sampleJson);
      expect(tx.notes, isNull);
      expect(tx.transferAccountId, isNull);
      expect(tx.clientId, isNull);
      expect(tx.recurringTransactionId, isNull);
      expect(tx.occurrenceDate, isNull);
    });

    test('parses recurring fields when present', () {
      final json = Map<String, dynamic>.from(sampleJson)
        ..['recurring_transaction_id'] = 'rec-1'
        ..['occurrence_date'] = '2026-07-01';
      final tx = Transaction.fromJson(json);
      expect(tx.recurringTransactionId, 'rec-1');
      expect(tx.occurrenceDate, '2026-07-01');
    });

    test('parses createdAt as DateTime', () {
      final tx = Transaction.fromJson(sampleJson);
      expect(tx.createdAt, isA<DateTime>());
      expect(tx.createdAt.year, 2026);
    });

    test('parses income transaction', () {
      final json = Map<String, dynamic>.from(sampleJson)
        ..['transaction_type'] = 'income'
        ..['amount'] = '3000000.00';
      final tx = Transaction.fromJson(json);
      expect(tx.transactionType, 'income');
      expect(tx.amount, Decimal.parse('3000000.00'));
    });
  });

  group('Transaction.toJson', () {
    test('serialises amount as string', () {
      final tx = Transaction.fromJson(sampleJson);
      final json = tx.toJson();
      expect(json['amount'], isA<String>());
      expect(json['amount'], '15000.00');
    });

    test('null fields serialise as null', () {
      final tx = Transaction.fromJson(sampleJson);
      final json = tx.toJson();
      expect(json['category_id'], isNull);
      expect(json['notes'], isNull);
    });
  });
}
