import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/period_summary.dart';

void main() {
  // Minimal JSON for the "full" view (active period — no JSONB breakdowns).
  final fullViewJson = {
    'period_id': 'tp-1',
    'view': 'full',
    'total_income': '500000',
    'total_expenses': '350000',
    'total_transfers': '0',
    'net_savings': '150000',
    'savings_rate': '30',
    'transaction_count': 2,
    'expense_transaction_count': 1,
    'income_transaction_count': 1,
    'top_expense_category_id': null,
    'top_expense_category_total': null,
    'sub_periods': null,
  };

  group('PeriodSummary.fromJson — full view', () {
    test('parses all numeric fields as Decimal', () {
      final s = PeriodSummary.fromJson(fullViewJson);
      expect(s.totalIncome, isA<Decimal>());
      expect(s.totalIncome, Decimal.parse('500000'));
      expect(s.totalExpenses, Decimal.parse('350000'));
      expect(s.totalTransfers, Decimal.zero);
      expect(s.netSavings, Decimal.parse('150000'));
      expect(s.savingsRate, Decimal.parse('30'));
    });

    test('parses metadata fields', () {
      final s = PeriodSummary.fromJson(fullViewJson);
      expect(s.periodId, 'tp-1');
      expect(s.view, 'full');
      expect(s.transactionCount, 2);
      expect(s.expenseTransactionCount, 1);
      expect(s.incomeTransactionCount, 1);
    });

    test('sub_periods is null for full view', () {
      final s = PeriodSummary.fromJson(fullViewJson);
      expect(s.subPeriods, isNull);
    });

    test('top expense fields are null when absent', () {
      final s = PeriodSummary.fromJson(fullViewJson);
      expect(s.topExpenseCategoryId, isNull);
      expect(s.topExpenseCategoryTotal, isNull);
    });

    test('parses top expense fields when present', () {
      final json = Map<String, dynamic>.from(fullViewJson)
        ..['top_expense_category_id'] = 'cat-1'
        ..['top_expense_category_total'] = '200000';
      final s = PeriodSummary.fromJson(json);
      expect(s.topExpenseCategoryId, 'cat-1');
      expect(s.topExpenseCategoryTotal, Decimal.parse('200000'));
    });

    test('handles zero income without errors', () {
      final json = Map<String, dynamic>.from(fullViewJson)
        ..['total_income'] = '0'
        ..['net_savings'] = '-350000'
        ..['savings_rate'] = '0';
      final s = PeriodSummary.fromJson(json);
      expect(s.totalIncome, Decimal.zero);
      expect(s.netSavings, Decimal.parse('-350000'));
      expect(s.savingsRate, Decimal.zero);
    });
  });

  group('PeriodSummary.fromJson — biweekly view with sub_periods', () {
    final biweeklyJson = {
      'period_id': 'tp-1',
      'view': 'biweekly',
      'total_income': '500000',
      'total_expenses': '350000',
      'total_transfers': '0',
      'net_savings': '150000',
      'savings_rate': '30',
      'transaction_count': 4,
      'expense_transaction_count': 3,
      'income_transaction_count': 1,
      'top_expense_category_id': null,
      'top_expense_category_total': null,
      'sub_periods': [
        {
          'index': 1,
          'from': '2026-07-04',
          'to': '2026-07-18',
          'total_income': '500000',
          'total_expenses': '200000',
          'total_transfers': '0',
          'net_savings': '300000',
          'savings_rate': '60',
          'transaction_count': 2,
          'expense_transaction_count': 1,
          'income_transaction_count': 1,
        },
        {
          'index': 2,
          'from': '2026-07-19',
          'to': '2026-08-02',
          'total_income': '0',
          'total_expenses': '150000',
          'total_transfers': '0',
          'net_savings': '-150000',
          'savings_rate': '0',
          'transaction_count': 2,
          'expense_transaction_count': 2,
          'income_transaction_count': 0,
        },
      ],
    };

    test('parses two sub_periods correctly', () {
      final s = PeriodSummary.fromJson(biweeklyJson);
      expect(s.subPeriods, isNotNull);
      expect(s.subPeriods!.length, 2);
    });

    test('first sub_period fields are correct', () {
      final s = PeriodSummary.fromJson(biweeklyJson);
      final sub1 = s.subPeriods![0];
      expect(sub1.index, 1);
      expect(sub1.from, '2026-07-04');
      expect(sub1.to, '2026-07-18');
      expect(sub1.totalIncome, Decimal.parse('500000'));
      expect(sub1.totalExpenses, Decimal.parse('200000'));
      expect(sub1.netSavings, Decimal.parse('300000'));
      expect(sub1.savingsRate, Decimal.parse('60'));
      expect(sub1.transactionCount, 2);
    });

    test('second sub_period has negative net_savings', () {
      final s = PeriodSummary.fromJson(biweeklyJson);
      final sub2 = s.subPeriods![1];
      expect(sub2.index, 2);
      expect(sub2.netSavings, Decimal.parse('-150000'));
      expect(sub2.incomeTransactionCount, 0);
    });

    test('summary root totals are for the full period regardless of view', () {
      final s = PeriodSummary.fromJson(biweeklyJson);
      expect(s.totalIncome, Decimal.parse('500000'));
      expect(s.totalExpenses, Decimal.parse('350000'));
    });
  });

  group('PeriodSummary.fromJson — weekly view with 4 sub_periods', () {
    List<Map<String, dynamic>> makeSubPeriods(int count) {
      return List.generate(
        count,
        (i) => {
          'index': i + 1,
          'from': '2026-07-04',
          'to': '2026-07-11',
          'total_income': '100000',
          'total_expenses': '80000',
          'total_transfers': '0',
          'net_savings': '20000',
          'savings_rate': '20',
          'transaction_count': 1,
          'expense_transaction_count': 1,
          'income_transaction_count': 0,
        },
      );
    }

    test('parses 4 sub_periods for weekly view', () {
      final json = {
        'period_id': 'tp-1',
        'view': 'weekly',
        'total_income': '400000',
        'total_expenses': '320000',
        'total_transfers': '0',
        'net_savings': '80000',
        'savings_rate': '20',
        'transaction_count': 4,
        'expense_transaction_count': 4,
        'income_transaction_count': 0,
        'top_expense_category_id': null,
        'top_expense_category_total': null,
        'sub_periods': makeSubPeriods(4),
      };
      final s = PeriodSummary.fromJson(json);
      expect(s.view, 'weekly');
      expect(s.subPeriods!.length, 4);
      expect(s.subPeriods![3].index, 4);
    });
  });

  group('SubPeriod helpers', () {
    // Build a sub-period covering a date range far in the past so isCurrent is false.
    final pastSub = SubPeriod.fromJson({
      'index': 1,
      'from': '2020-01-01',
      'to': '2020-01-15',
      'total_income': '0',
      'total_expenses': '0',
      'total_transfers': '0',
      'net_savings': '0',
      'savings_rate': '0',
      'transaction_count': 0,
      'expense_transaction_count': 0,
      'income_transaction_count': 0,
    });

    // Build a sub-period covering a very wide range so isCurrent is true.
    final currentSub = SubPeriod.fromJson({
      'index': 1,
      'from': '2000-01-01',
      'to': '2099-12-31',
      'total_income': '0',
      'total_expenses': '0',
      'total_transfers': '0',
      'net_savings': '0',
      'savings_rate': '0',
      'transaction_count': 0,
      'expense_transaction_count': 0,
      'income_transaction_count': 0,
    });

    test('isCurrent is false for a past sub-period', () {
      expect(pastSub.isCurrent, isFalse);
    });

    test('isCurrent is true when today is within the range', () {
      expect(currentSub.isCurrent, isTrue);
    });
  });
}
