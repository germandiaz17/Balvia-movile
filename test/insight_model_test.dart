import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/insight.dart';
import 'package:balvia_mobile/shared/insight_card.dart';

void main() {
  group('Insight.fromJson', () {
    test('parses a full object', () {
      final json = {
        'id': 'ins-1',
        'insight_type': 'budget_warning',
        'calculation_phase': 'during',
        'severity': 'warning',
        'title': 'Presupuesto en riesgo',
        'message': 'Vas gastando más rápido de lo ideal.',
        'action_label': 'Ver presupuesto',
        'action_target': '/budgets',
        'data': {'category_id': 'cat-1', 'pct': 85},
        'related_category_id': 'cat-1',
        'related_account_id': 'acc-1',
        'related_goal_id': 'goal-1',
        'created_at': '2026-07-26T10:30:00Z',
      };

      final insight = Insight.fromJson(json);

      expect(insight.id, 'ins-1');
      expect(insight.insightType, 'budget_warning');
      expect(insight.calculationPhase, 'during');
      expect(insight.severity, 'warning');
      expect(insight.title, 'Presupuesto en riesgo');
      expect(insight.message, 'Vas gastando más rápido de lo ideal.');
      expect(insight.actionLabel, 'Ver presupuesto');
      expect(insight.actionTarget, '/budgets');
      expect(insight.data, isNotNull);
      expect(insight.data!['pct'], 85);
      expect(insight.relatedCategoryId, 'cat-1');
      expect(insight.relatedAccountId, 'acc-1');
      expect(insight.relatedGoalId, 'goal-1');
      expect(insight.createdAt.year, 2026);
      expect(insight.createdAt.month, 7);
    });

    test('parses a minimal object with nulls', () {
      final json = {
        'id': 'ins-2',
        'insight_type': 'spending_pace',
        'calculation_phase': 'during',
        'severity': 'info',
        'title': 'Ritmo de gasto',
        'message': 'Vas al día con tu presupuesto.',
        'action_label': null,
        'action_target': null,
        'data': null,
        'related_category_id': null,
        'related_account_id': null,
        'related_goal_id': null,
        'created_at': '2026-07-26T10:30:00Z',
      };

      final insight = Insight.fromJson(json);

      expect(insight.id, 'ins-2');
      expect(insight.actionLabel, isNull);
      expect(insight.actionTarget, isNull);
      expect(insight.data, isNull);
      expect(insight.relatedCategoryId, isNull);
      expect(insight.relatedAccountId, isNull);
      expect(insight.relatedGoalId, isNull);
    });
  });

  group('insightSeverityFromString', () {
    test('maps all four known severities', () {
      expect(insightSeverityFromString('info'), InsightSeverity.info);
      expect(insightSeverityFromString('success'), InsightSeverity.success);
      expect(insightSeverityFromString('warning'), InsightSeverity.warning);
      expect(insightSeverityFromString('critical'), InsightSeverity.critical);
    });

    test('defaults unknown values to info', () {
      expect(insightSeverityFromString('bogus'), InsightSeverity.info);
      expect(insightSeverityFromString(''), InsightSeverity.info);
    });
  });
}
