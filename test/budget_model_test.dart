import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balvia_mobile/data/models/budget.dart';

void main() {
  group('Budget.fromJson', () {
    const fullJson = {
      'id': 'budget-1',
      'tracking_period_id': 'period-1',
      'category_id': 'cat-1',
      'amount': '300000.00',
      'currency': 'COP',
      'alert_threshold_warning': '80.00',
      'alert_threshold_critical': '100.00',
      'notes': 'Alimentación mensual',
    };

    test('parses all fields correctly', () {
      final b = Budget.fromJson(fullJson);
      expect(b.id, 'budget-1');
      expect(b.trackingPeriodId, 'period-1');
      expect(b.categoryId, 'cat-1');
      expect(b.amount, Decimal.parse('300000.00'));
      expect(b.currency, 'COP');
      expect(b.alertThresholdWarning, Decimal.parse('80.00'));
      expect(b.alertThresholdCritical, Decimal.parse('100.00'));
      expect(b.notes, 'Alimentación mensual');
    });

    test('parses global budget (category_id null)', () {
      final json = Map<String, dynamic>.from(fullJson);
      json['category_id'] = null;
      final b = Budget.fromJson(json);
      expect(b.categoryId, isNull);
    });

    test('defaults alert thresholds when absent', () {
      final json = {
        'id': 'b',
        'tracking_period_id': 'p',
        'category_id': null,
        'amount': '100000.00',
        'currency': 'COP',
        // alert fields absent
      };
      final b = Budget.fromJson(json);
      expect(b.alertThresholdWarning, Decimal.parse('80'));
      expect(b.alertThresholdCritical, Decimal.parse('100'));
    });

    test('amount parses as Decimal (never double)', () {
      final b = Budget.fromJson(fullJson);
      expect(b.amount, isA<Decimal>());
      // Decimal normalizes trailing zeros: 300000.00 → 300000.
      expect(b.amount, Decimal.parse('300000'));
    });

    test('toJson round-trips without data loss', () {
      final b = Budget.fromJson(fullJson);
      final json = b.toJson();
      final b2 = Budget.fromJson(json);
      expect(b2.id, b.id);
      expect(b2.amount, b.amount);
      expect(b2.alertThresholdWarning, b.alertThresholdWarning);
      expect(b2.alertThresholdCritical, b.alertThresholdCritical);
    });

    test('toJson serialises amount as string with 2 decimal places', () {
      final b = Budget.fromJson(fullJson);
      final json = b.toJson();
      expect(json['amount'], '300000.00');
    });
  });

  group('Budget.copyWith', () {
    final base = Budget(
      id: 'b1',
      trackingPeriodId: 'p1',
      amount: Decimal.parse('500000'),
      currency: 'COP',
      alertThresholdWarning: Decimal.fromInt(80),
      alertThresholdCritical: Decimal.fromInt(100),
    );

    test('changes only the specified field', () {
      final updated = base.copyWith(amount: Decimal.parse('750000'));
      expect(updated.amount, Decimal.parse('750000'));
      expect(updated.id, base.id);
      expect(updated.alertThresholdWarning, base.alertThresholdWarning);
    });
  });
}
