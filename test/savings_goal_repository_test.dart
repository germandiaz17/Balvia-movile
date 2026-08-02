/// Tests for SavingsGoalRepository against a fake Dio adapter: the exact
/// request each method builds, and how it parses the response.
///
/// The PUT case matters most — the backend treats it as a full replace, so a
/// body that silently drops a field would wipe it.
library;

import 'package:decimal/decimal.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/repositories/savings_goal_repository.dart';

import 'fake_http_adapter.dart';

void main() {
  Map<String, dynamic> goalPayload({
    String id = 'goal-1',
    String currentAmount = '0.00',
    String status = 'active',
  }) => <String, dynamic>{
    'id': id,
    'name': 'Viaje a Cartagena',
    'description': null,
    'icon': null,
    'color': null,
    'target_amount': '3000000.00',
    'current_amount': currentAmount,
    'currency': 'COP',
    'start_date': '2026-08-01',
    'target_date': '2026-12-01',
    'status': status,
    'linked_account_id': null,
    'achieved_at': null,
  };

  (SavingsGoalRepository, FakeHttpAdapter) build(List<FakeResponse> responses) {
    final adapter = FakeHttpAdapter(responses);
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'))
      ..httpClientAdapter = adapter;
    return (SavingsGoalRepository(dio), adapter);
  }

  group('list', () {
    test('reads the savings_goals envelope', () async {
      final (repo, adapter) = build([
        FakeResponse(
          body: {
            'savings_goals': [goalPayload(), goalPayload(id: 'goal-2')],
            'count': 2,
          },
        ),
      ]);

      final goals = await repo.list();

      expect(goals, hasLength(2));
      expect(goals.first.id, 'goal-1');
      expect(adapter.request.method, 'GET');
      expect(adapter.request.path, '/savings-goals');
    });

    test('an empty list is not an error', () async {
      final (repo, _) = build([
        FakeResponse(body: {'savings_goals': <dynamic>[], 'count': 0}),
      ]);
      expect(await repo.list(), isEmpty);
    });
  });

  group('create', () {
    test(
      'sends amounts as strings, dates as YYYY-MM-DD and defaults COP',
      () async {
        final (repo, adapter) = build([
          FakeResponse(body: goalPayload(), statusCode: 201),
        ]);

        await repo.create(
          name: 'Viaje a Cartagena',
          targetAmount: Decimal.parse('3000000'),
          startDate: DateTime(2026, 8, 1),
          targetDate: DateTime(2026, 12, 1),
        );

        final req = adapter.request;
        expect(req.method, 'POST');
        expect(req.path, '/savings-goals');
        expect(req.body!['name'], 'Viaje a Cartagena');
        expect(req.body!['target_amount'], '3000000.00');
        expect(req.body!['start_date'], '2026-08-01');
        expect(req.body!['target_date'], '2026-12-01');
        expect(req.body!['currency'], 'COP');
      },
    );

    test('passes the linked account through when given', () async {
      final (repo, adapter) = build([
        FakeResponse(body: goalPayload(), statusCode: 201),
      ]);

      await repo.create(
        name: 'Carro',
        targetAmount: Decimal.parse('50000000'),
        startDate: DateTime(2026, 8, 1),
        targetDate: DateTime(2028, 1, 1),
        linkedAccountId: 'acc-7',
      );

      expect(adapter.request.body!['linked_account_id'], 'acc-7');
    });
  });

  group('update', () {
    test('sends every field the full-replace PUT requires', () async {
      final (repo, adapter) = build([FakeResponse(body: goalPayload())]);

      await repo.update(
        'goal-1',
        name: 'Viaje a Cartagena',
        targetAmount: Decimal.parse('4000000'),
        targetDate: DateTime(2027, 1, 15),
        status: 'paused',
        description: 'Con los niños',
        icon: 'beach',
        color: '#00AA88',
        linkedAccountId: 'acc-7',
      );

      final req = adapter.request;
      expect(req.method, 'PUT');
      expect(req.path, '/savings-goals/goal-1');
      // goalUpdateRequest marks these four as required.
      expect(req.body!['name'], 'Viaje a Cartagena');
      expect(req.body!['target_amount'], '4000000.00');
      expect(req.body!['target_date'], '2027-01-15');
      expect(req.body!['status'], 'paused');
      // Optional-but-replaced fields must travel too, or they get wiped.
      expect(req.body!['description'], 'Con los niños');
      expect(req.body!['icon'], 'beach');
      expect(req.body!['color'], '#00AA88');
      expect(req.body!['linked_account_id'], 'acc-7');
    });

    test('never sends start_date — the backend rejects editing it', () async {
      final (repo, adapter) = build([FakeResponse(body: goalPayload())]);

      await repo.update(
        'goal-1',
        name: 'Viaje',
        targetAmount: Decimal.parse('1000'),
        targetDate: DateTime(2027, 1, 15),
        status: 'active',
      );

      expect(adapter.request.body!.containsKey('start_date'), isFalse);
    });
  });

  group('delete', () {
    test('hits DELETE on the goal path', () async {
      final (repo, adapter) = build([
        FakeResponse(body: <String, dynamic>{}, statusCode: 204),
      ]);

      await repo.delete('goal-1');

      expect(adapter.request.method, 'DELETE');
      expect(adapter.request.path, '/savings-goals/goal-1');
    });
  });

  group('addContribution', () {
    test('parses the {goal, contribution} pair the backend returns', () async {
      final (repo, adapter) = build([
        FakeResponse(
          statusCode: 201,
          body: {
            'goal': goalPayload(currentAmount: '500000.00'),
            'contribution': {
              'id': 'contrib-1',
              'savings_goal_id': 'goal-1',
              'tracking_period_id': 'tp-1',
              'amount': '500000.00',
              'contribution_date': '2026-08-15',
              'notes': 'Prima',
              'created_at': '2026-08-15T09:00:00Z',
            },
          },
        ),
      ]);

      final result = await repo.addContribution(
        'goal-1',
        amount: Decimal.parse('500000'),
        contributionDate: DateTime(2026, 8, 15),
        notes: 'Prima',
      );

      expect(result.goal.currentAmount, Decimal.parse('500000.00'));
      expect(result.contribution.id, 'contrib-1');
      expect(result.contribution.amount, Decimal.parse('500000.00'));

      final req = adapter.request;
      expect(req.method, 'POST');
      expect(req.path, '/savings-goals/goal-1/contributions');
      expect(req.body!['amount'], '500000.00');
      expect(req.body!['contribution_date'], '2026-08-15');
      expect(req.body!['notes'], 'Prima');
    });

    test(
      'omits contribution_date so the server defaults it to today',
      () async {
        final (repo, adapter) = build([
          FakeResponse(
            statusCode: 201,
            body: {
              'goal': goalPayload(currentAmount: '100.00'),
              'contribution': {
                'id': 'contrib-2',
                'savings_goal_id': 'goal-1',
                'tracking_period_id': 'tp-1',
                'amount': '100.00',
                'contribution_date': '2026-08-20',
                'notes': null,
                'created_at': '2026-08-20T09:00:00Z',
              },
            },
          ),
        ]);

        await repo.addContribution('goal-1', amount: Decimal.parse('100'));

        expect(adapter.request.body!.containsKey('contribution_date'), isFalse);
      },
    );

    test('surfaces the backend 422 when there is no active period', () async {
      final (repo, _) = build([
        FakeResponse(
          statusCode: 422,
          body: {'error': 'no active tracking period'},
        ),
      ]);

      expect(
        () => repo.addContribution('goal-1', amount: Decimal.parse('100')),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'statusCode',
            422,
          ),
        ),
      );
    });
  });

  group('listContributions', () {
    test('reads the contributions envelope', () async {
      final (repo, adapter) = build([
        FakeResponse(
          body: {
            'contributions': [
              {
                'id': 'contrib-1',
                'savings_goal_id': 'goal-1',
                'tracking_period_id': 'tp-1',
                'amount': '250000.00',
                'contribution_date': '2026-08-15',
                'notes': null,
                'created_at': '2026-08-15T09:00:00Z',
              },
            ],
            'count': 1,
          },
        ),
      ]);

      final contributions = await repo.listContributions('goal-1');

      expect(contributions, hasLength(1));
      expect(contributions.first.amount, Decimal.parse('250000.00'));
      expect(adapter.request.path, '/savings-goals/goal-1/contributions');
    });
  });
}
