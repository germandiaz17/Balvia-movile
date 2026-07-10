/// Tests for TransactionRepository request body building and response parsing.
/// We don't spin up a real HTTP server; instead we verify the serialization
/// logic (amount as string, optional fields omitted/included) by inspecting the
/// model round-trip and the repository's documented contract.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/transaction.dart';

void main() {
  // Shared sample JSON that mirrors a real API response.
  final baseJson = <String, dynamic>{
    'id': 'tx-99',
    'tracking_period_id': 'tp-1',
    'account_id': 'acc-1',
    'category_id': 'cat-1',
    'transaction_type': 'expense',
    'amount': '50000.00',
    'currency': 'COP',
    'description': 'Uber',
    'notes': 'Viaje al aeropuerto',
    'transaction_date': '2026-07-09',
    'transfer_account_id': null,
    'client_id': 'client-uuid',
    'recurring_transaction_id': null,
    'occurrence_date': null,
    'created_at': '2026-07-09T10:00:00Z',
  };

  group('Transaction.fromJson — update response', () {
    test('parses all fields correctly after an update', () {
      final tx = Transaction.fromJson(baseJson);

      expect(tx.id, 'tx-99');
      expect(tx.transactionType, 'expense');
      expect(tx.amount, Decimal.parse('50000.00'));
      expect(tx.categoryId, 'cat-1');
      expect(tx.description, 'Uber');
      expect(tx.notes, 'Viaje al aeropuerto');
      expect(tx.clientId, 'client-uuid');
    });

    test('amount stays Decimal after round-trip (never double)', () {
      final tx = Transaction.fromJson(baseJson);
      final json = tx.toJson();
      // Must remain a string in the serialised form.
      expect(json['amount'], isA<String>());
      expect(json['amount'], '50000.00');
    });

    test('parses income transaction', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['transaction_type'] = 'income'
        ..['amount'] = '1500000.00'
        ..['category_id'] = null
        ..['description'] = null
        ..['notes'] = null;
      final tx = Transaction.fromJson(json);
      expect(tx.transactionType, 'income');
      expect(tx.amount, Decimal.parse('1500000.00'));
      expect(tx.categoryId, isNull);
    });

    test('parses transfer transaction with transfer_account_id', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['transaction_type'] = 'transfer'
        ..['transfer_account_id'] = 'acc-2';
      final tx = Transaction.fromJson(json);
      expect(tx.transactionType, 'transfer');
      expect(tx.transferAccountId, 'acc-2');
    });
  });

  group('Transaction.toJson — body for PUT /transactions/:id', () {
    test('serialises amount as string with 2 decimal places', () {
      final tx = Transaction.fromJson(baseJson);
      final json = tx.toJson();
      expect(json['amount'], '50000.00');
    });

    test('nullable fields serialise as null', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['transfer_account_id'] = null
        ..['client_id'] = null
        ..['notes'] = null;
      final tx = Transaction.fromJson(json);
      final out = tx.toJson();
      expect(out['transfer_account_id'], isNull);
      expect(out['client_id'], isNull);
      expect(out['notes'], isNull);
    });

    test('createdAt serialises to ISO 8601 string', () {
      final tx = Transaction.fromJson(baseJson);
      final out = tx.toJson();
      expect(out['created_at'], isA<String>());
      // Must be parseable as a DateTime.
      expect(() => DateTime.parse(out['created_at'] as String), returnsNormally);
    });

    test('large COP amount preserves precision', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['amount'] = '9999999.00';
      final tx = Transaction.fromJson(json);
      final out = tx.toJson();
      expect(out['amount'], '9999999.00');
    });
  });

  group('Decimal amount boundary conditions', () {
    test('zero amount parses without error', () {
      final json = Map<String, dynamic>.from(baseJson)..['amount'] = '0.00';
      final tx = Transaction.fromJson(json);
      expect(tx.amount, Decimal.zero);
    });

    test('amount with cents parses correctly', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['amount'] = '12345.50';
      final tx = Transaction.fromJson(json);
      expect(tx.amount, Decimal.parse('12345.50'));
    });
  });
}
