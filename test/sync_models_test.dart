// Tests for sync protocol models (PullResponse, PushItem, PushItemResult).
// Covers the contract requirements from docs/API_CONTRACT.md §Sync.

import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/sync/sync_models.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PullResponse
  // ---------------------------------------------------------------------------

  group('PullResponse.fromJson', () {
    final minimalPullJson = {
      'server_time': '2026-07-10T01:32:33Z',
      'has_more': false,
      'transactions': <dynamic>[],
      'accounts': <dynamic>[],
      'categories': <dynamic>[],
      'budgets': <dynamic>[],
      'savings_goals': <dynamic>[],
      'goal_contributions': <dynamic>[],
      'recurring_transactions': <dynamic>[],
      'tracking_periods': <dynamic>[],
    };

    test('parses server_time and has_more', () {
      final pull = PullResponse.fromJson(minimalPullJson);
      expect(pull.serverTime, '2026-07-10T01:32:33Z');
      expect(pull.hasMore, isFalse);
    });

    test('all collections are empty when empty arrays given', () {
      final pull = PullResponse.fromJson(minimalPullJson);
      expect(pull.transactions, isEmpty);
      expect(pull.accounts, isEmpty);
      expect(pull.categories, isEmpty);
      expect(pull.budgets, isEmpty);
      expect(pull.savingsGoals, isEmpty);
      expect(pull.goalContributions, isEmpty);
      expect(pull.recurringTransactions, isEmpty);
      expect(pull.trackingPeriods, isEmpty);
    });

    test('parses non-empty collections', () {
      final json = Map<String, dynamic>.from(minimalPullJson)
        ..['has_more'] = true
        ..['transactions'] = [
          {
            'id': 'tx-1',
            'updated_at': '2026-07-09T12:00:00Z',
            'user_id': 'u-1',
            'tracking_period_id': 'tp-1',
            'account_id': 'acc-1',
            'transaction_type': 'expense',
            'amount': '5000.00',
            'currency': 'COP',
            'transaction_date': '2026-07-09',
            'created_at': '2026-07-09T12:00:00Z',
            'deleted_at': null,
            'category_id': null,
            'description': null,
            'notes': null,
            'transfer_account_id': null,
            'client_id': null,
            'recurring_transaction_id': null,
            'occurrence_date': null,
          },
        ];
      final pull = PullResponse.fromJson(json);
      expect(pull.hasMore, isTrue);
      expect(pull.transactions, hasLength(1));
      expect(pull.transactions.first['id'], 'tx-1');
    });

    test('handles missing keys by returning empty list', () {
      final json = {
        'server_time': '2026-07-10T01:32:33Z',
        'has_more': false,
        // Missing all collection keys
      };
      final pull = PullResponse.fromJson(json);
      expect(pull.transactions, isEmpty);
      expect(pull.accounts, isEmpty);
    });
  });

  group('PullResponse.oldestLastUpdatedAt', () {
    test('returns null when all collections are empty', () {
      final pull = PullResponse(
        serverTime: '2026-07-10T00:00:00Z',
        hasMore: true,
        transactions: const [],
        accounts: const [],
        categories: const [],
        budgets: const [],
        savingsGoals: const [],
        goalContributions: const [],
        recurringTransactions: const [],
        trackingPeriods: const [],
      );
      expect(pull.oldestLastUpdatedAt(), isNull);
    });

    test('returns the oldest updated_at across collections', () {
      // transactions last row: 2026-07-09T10:00:00Z
      // accounts last row:    2026-07-09T08:00:00Z  ← oldest
      // categories last row:  2026-07-09T12:00:00Z
      final pull = PullResponse(
        serverTime: '2026-07-10T00:00:00Z',
        hasMore: true,
        transactions: [
          {'updated_at': '2026-07-09T05:00:00Z'},
          {'updated_at': '2026-07-09T10:00:00Z'},
        ],
        accounts: [
          {'updated_at': '2026-07-09T06:00:00Z'},
          {'updated_at': '2026-07-09T08:00:00Z'},
        ],
        categories: [
          {'updated_at': '2026-07-09T12:00:00Z'},
        ],
        budgets: const [],
        savingsGoals: const [],
        goalContributions: const [],
        recurringTransactions: const [],
        trackingPeriods: const [],
      );
      // oldest of (10:00, 08:00, 12:00) is 08:00
      expect(pull.oldestLastUpdatedAt(), '2026-07-09T08:00:00Z');
    });

    test('returns single value when only one collection is non-empty', () {
      final pull = PullResponse(
        serverTime: '2026-07-10T00:00:00Z',
        hasMore: true,
        transactions: [
          {'updated_at': '2026-07-09T15:30:00Z'},
        ],
        accounts: const [],
        categories: const [],
        budgets: const [],
        savingsGoals: const [],
        goalContributions: const [],
        recurringTransactions: const [],
        trackingPeriods: const [],
      );
      expect(pull.oldestLastUpdatedAt(), '2026-07-09T15:30:00Z');
    });
  });

  // ---------------------------------------------------------------------------
  // PushItem
  // ---------------------------------------------------------------------------

  group('PushItem.toJson', () {
    test('create serialises correctly with payload and no entity_id', () {
      final item = PushItem(
        clientRef: 'op-1',
        entityType: 'transaction',
        operation: 'create',
        transactionPayload: {
          'account_id': 'acc-1',
          'transaction_type': 'expense',
          'amount': '15000.00',
          'currency': 'COP',
          'client_id': 'mobile-abc',
        },
      );
      final json = item.toJson();
      expect(json['client_ref'], 'op-1');
      expect(json['entity_type'], 'transaction');
      expect(json['operation'], 'create');
      expect(json.containsKey('entity_id'), isFalse);
      expect(json.containsKey('client_updated_at'), isFalse);
      final payload = json['transaction_payload'] as Map<String, dynamic>;
      expect(payload['amount'], '15000.00');
      expect(payload['client_id'], 'mobile-abc');
    });

    test('update serialises entity_id and client_updated_at', () {
      final item = PushItem(
        clientRef: 'op-2',
        entityType: 'transaction',
        operation: 'update',
        entityId: 'tx-server-1',
        clientUpdatedAt: '2026-07-09T10:00:00Z',
        transactionPayload: {
          'account_id': 'acc-1',
          'transaction_type': 'expense',
          'amount': '20000.00',
          'currency': 'COP',
        },
      );
      final json = item.toJson();
      expect(json['entity_id'], 'tx-server-1');
      expect(json['client_updated_at'], '2026-07-09T10:00:00Z');
      expect(json['operation'], 'update');
    });

    test('delete serialises entity_id and no payload', () {
      final item = PushItem(
        clientRef: 'op-3',
        entityType: 'transaction',
        operation: 'delete',
        entityId: 'tx-server-2',
      );
      final json = item.toJson();
      expect(json['entity_id'], 'tx-server-2');
      expect(json.containsKey('transaction_payload'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // PushItemResult — status mapping per contract
  // ---------------------------------------------------------------------------

  group('PushItemResult.fromJson', () {
    test('applied status parses server_entity', () {
      final json = {
        'client_ref': 'op-1',
        'status': 'applied',
        'server_entity': {
          'id': 'tx-server-uuid',
          'updated_at': '2026-07-09T12:00:00Z',
        },
        'error': null,
      };
      final result = PushItemResult.fromJson(json);
      expect(result.status, 'applied');
      expect(result.serverEntity, isNotNull);
      expect(result.serverEntity!['id'], 'tx-server-uuid');
      expect(result.error, isNull);
    });

    test('skipped status parses server_entity (idempotency)', () {
      final json = {
        'client_ref': 'op-1',
        'status': 'skipped',
        'server_entity': {
          'id': 'existing-id',
          'updated_at': '2026-07-09T10:00:00Z',
        },
        'error': null,
      };
      final result = PushItemResult.fromJson(json);
      expect(result.status, 'skipped');
      expect(result.serverEntity!['id'], 'existing-id');
    });

    test('conflict status parses server_entity for LWW', () {
      final json = {
        'client_ref': 'op-2',
        'status': 'conflict',
        'server_entity': {'id': 'tx-1', 'updated_at': '2026-07-09T11:00:00Z'},
        'error': null,
      };
      final result = PushItemResult.fromJson(json);
      expect(result.status, 'conflict');
      expect(result.serverEntity, isNotNull);
    });

    test('rejected status parses error message', () {
      final json = {
        'client_ref': 'op-3',
        'status': 'rejected',
        'server_entity': null,
        'error': 'period is closed',
      };
      final result = PushItemResult.fromJson(json);
      expect(result.status, 'rejected');
      expect(result.serverEntity, isNull);
      expect(result.error, 'period is closed');
    });

    test('rejected for unsupported entity_type parses correctly', () {
      final json = {
        'client_ref': 'op-4',
        'status': 'rejected',
        'server_entity': null,
        'error': 'unsupported entity_type',
      };
      final result = PushItemResult.fromJson(json);
      expect(result.status, 'rejected');
      expect(result.error, contains('unsupported'));
    });
  });
}
