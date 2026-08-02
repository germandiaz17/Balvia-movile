/// Tests for the SavingsGoal / GoalContribution models: parsing the backend's
/// goalResponse and contributionResponse, and the derived progress values the
/// cards render.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/savings_goal.dart';

void main() {
  Map<String, dynamic> goalJson({
    String targetAmount = '3000000.00',
    String currentAmount = '750000.00',
    String status = 'active',
    String targetDate = '2026-12-01',
    String? achievedAt,
    String? linkedAccountId,
    String? description,
  }) => <String, dynamic>{
    'id': 'goal-1',
    'name': 'Viaje a Cartagena',
    'description': description,
    'icon': null,
    'color': null,
    'target_amount': targetAmount,
    'current_amount': currentAmount,
    'currency': 'COP',
    'start_date': '2026-08-01',
    'target_date': targetDate,
    'status': status,
    'linked_account_id': linkedAccountId,
    'achieved_at': achievedAt,
  };

  group('SavingsGoal.fromJson', () {
    test('parses a fully populated goal', () {
      final g = SavingsGoal.fromJson(
        goalJson(linkedAccountId: 'acc-7', description: 'Ahorro vacaciones'),
      );

      expect(g.id, 'goal-1');
      expect(g.name, 'Viaje a Cartagena');
      expect(g.description, 'Ahorro vacaciones');
      expect(g.targetAmount, Decimal.parse('3000000.00'));
      expect(g.currentAmount, Decimal.parse('750000.00'));
      expect(g.currency, 'COP');
      expect(g.startDate, DateTime(2026, 8, 1));
      expect(g.targetDate, DateTime(2026, 12, 1));
      expect(g.status, 'active');
      expect(g.linkedAccountId, 'acc-7');
      expect(g.achievedAt, isNull);
    });

    test('nullable fields stay null', () {
      final g = SavingsGoal.fromJson(goalJson());
      expect(g.description, isNull);
      expect(g.icon, isNull);
      expect(g.color, isNull);
      expect(g.linkedAccountId, isNull);
      expect(g.achievedAt, isNull);
    });

    test('parses achieved_at when the goal is complete', () {
      final g = SavingsGoal.fromJson(
        goalJson(
          currentAmount: '3000000.00',
          status: 'achieved',
          achievedAt: '2026-11-02T14:30:00Z',
        ),
      );

      expect(g.isAchieved, isTrue);
      expect(g.achievedAt, isNotNull);
      expect(g.achievedAt!.toUtc(), DateTime.utc(2026, 11, 2, 14, 30));
    });

    test('falls back to COP when currency is absent', () {
      final json = goalJson()..remove('currency');
      expect(SavingsGoal.fromJson(json).currency, 'COP');
    });
  });

  group('SavingsGoal.toJson', () {
    test('amounts serialise as strings and dates as YYYY-MM-DD', () {
      final json = SavingsGoal.fromJson(goalJson()).toJson();

      expect(json['target_amount'], isA<String>());
      expect(json['target_amount'], '3000000.00');
      expect(json['current_amount'], '750000.00');
      expect(json['start_date'], '2026-08-01');
      expect(json['target_date'], '2026-12-01');
    });

    test('round-trips back to an equal goal', () {
      final original = SavingsGoal.fromJson(
        goalJson(linkedAccountId: 'acc-7', achievedAt: '2026-11-02T14:30:00Z'),
      );
      final restored = SavingsGoal.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.targetAmount, original.targetAmount);
      expect(restored.currentAmount, original.currentAmount);
      expect(restored.targetDate, original.targetDate);
      expect(restored.linkedAccountId, original.linkedAccountId);
      expect(restored.achievedAt!.toUtc(), original.achievedAt!.toUtc());
    });
  });

  group('progress', () {
    test('fraction is current / target', () {
      final g = SavingsGoal.fromJson(
        goalJson(targetAmount: '1000.00', currentAmount: '500.00'),
      );
      expect(g.progressFraction, closeTo(0.5, 1e-9));
      expect(g.progressPercent, closeTo(50, 1e-9));
    });

    test('fraction clamps at 1 when overshooting, percent does not', () {
      final g = SavingsGoal.fromJson(
        goalJson(targetAmount: '1000.00', currentAmount: '1200.00'),
      );
      expect(g.progressFraction, 1.0);
      expect(g.progressPercent, closeTo(120, 1e-9));
    });

    test('a zero target reads as 0 instead of dividing by zero', () {
      final g = SavingsGoal.fromJson(
        goalJson(targetAmount: '0.00', currentAmount: '500.00'),
      );
      expect(g.progressFraction, 0.0);
      expect(g.progressPercent, 0.0);
    });

    test('remainingAmount never goes negative', () {
      final over = SavingsGoal.fromJson(
        goalJson(targetAmount: '1000.00', currentAmount: '1200.00'),
      );
      expect(over.remainingAmount, Decimal.zero);

      final under = SavingsGoal.fromJson(
        goalJson(targetAmount: '1000.00', currentAmount: '400.00'),
      );
      expect(under.remainingAmount, Decimal.parse('600.00'));
    });
  });

  group('daysRemaining', () {
    test('is positive for a future target', () {
      final future = DateTime.now().add(const Duration(days: 10));
      final g = SavingsGoal.fromJson(
        goalJson(targetDate: formatDateOnly(future)),
      );
      expect(g.daysRemaining, 10);
      expect(g.isOverdue, isFalse);
    });

    test('is negative once the target date has passed', () {
      final past = DateTime.now().subtract(const Duration(days: 3));
      final g = SavingsGoal.fromJson(
        goalJson(targetDate: formatDateOnly(past)),
      );
      expect(g.daysRemaining, -3);
      expect(g.isOverdue, isTrue);
    });

    test('an achieved goal is never overdue', () {
      final past = DateTime.now().subtract(const Duration(days: 3));
      final g = SavingsGoal.fromJson(
        goalJson(
          targetDate: formatDateOnly(past),
          status: 'achieved',
          achievedAt: '2026-07-01T00:00:00Z',
        ),
      );
      expect(g.daysRemaining, -3);
      expect(g.isOverdue, isFalse);
    });
  });

  group('GoalContribution', () {
    final contributionJson = <String, dynamic>{
      'id': 'contrib-1',
      'savings_goal_id': 'goal-1',
      'tracking_period_id': 'tp-1',
      'amount': '250000.00',
      'contribution_date': '2026-08-15',
      'notes': 'Prima',
      'created_at': '2026-08-15T09:00:00Z',
    };

    test('parses all fields', () {
      final c = GoalContribution.fromJson(contributionJson);
      expect(c.id, 'contrib-1');
      expect(c.savingsGoalId, 'goal-1');
      expect(c.trackingPeriodId, 'tp-1');
      expect(c.amount, Decimal.parse('250000.00'));
      expect(c.contributionDate, DateTime(2026, 8, 15));
      expect(c.notes, 'Prima');
    });

    test('notes may be null', () {
      final json = Map<String, dynamic>.from(contributionJson)
        ..['notes'] = null;
      expect(GoalContribution.fromJson(json).notes, isNull);
    });

    test('serialises amount as a string and the date as YYYY-MM-DD', () {
      final json = GoalContribution.fromJson(contributionJson).toJson();
      expect(json['amount'], '250000.00');
      expect(json['contribution_date'], '2026-08-15');
    });
  });

  group('goalStatusLabel', () {
    test('translates every status the backend accepts', () {
      expect(goalStatusLabel('active'), 'Activa');
      expect(goalStatusLabel('achieved'), 'Lograda');
      expect(goalStatusLabel('abandoned'), 'Abandonada');
      expect(goalStatusLabel('paused'), 'Pausada');
    });

    test('falls back to the raw value for anything unknown', () {
      expect(goalStatusLabel('mistery'), 'mistery');
    });
  });

  group('formatDateOnly', () {
    test('zero-pads month and day', () {
      expect(formatDateOnly(DateTime(2026, 1, 5)), '2026-01-05');
      expect(formatDateOnly(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });
}
