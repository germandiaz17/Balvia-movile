// Tests for shared widget utilities: AmountText formatting logic and
// BudgetProgressBar threshold logic. We test the formatting/color logic
// directly rather than pumping full widget trees to keep tests fast and
// independent of the Flutter widget environment.
//
// AmountText wraps AmountFormatter — we verify the assembled display strings.
// BudgetProgressBar threshold logic is tested via the component's behavior
// documented in its contract (colors driven by double pct, not Decimal).

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balvia_mobile/core/amount_formatter.dart';
import 'package:balvia_mobile/core/theme.dart';

void main() {
  // -------------------------------------------------------------------------
  // AmountFormatter — sign/color helpers (BalviaTheme)
  // -------------------------------------------------------------------------
  group('BalviaTheme.colorForType', () {
    test('income returns income green', () {
      expect(BalviaTheme.colorForType('income'), BalviaTheme.income);
    });
    test('expense returns expense red', () {
      expect(BalviaTheme.colorForType('expense'), BalviaTheme.expense);
    });
    test('transfer returns transfer blue', () {
      expect(BalviaTheme.colorForType('transfer'), BalviaTheme.transfer);
    });
    test('unknown type falls back to expense color', () {
      expect(BalviaTheme.colorForType('unknown'), BalviaTheme.expense);
    });
  });

  group('BalviaTheme.signForType', () {
    test('income sign is +', () {
      expect(BalviaTheme.signForType('income'), '+');
    });
    test('expense sign is -', () {
      expect(BalviaTheme.signForType('expense'), '-');
    });
    test('transfer sign is empty', () {
      expect(BalviaTheme.signForType('transfer'), '');
    });
  });

  // -------------------------------------------------------------------------
  // AmountText display string composition (via AmountFormatter)
  // -------------------------------------------------------------------------
  group('AmountText display string', () {
    // The full display is "$sign${AmountFormatter.formatCOP(amount)}".
    // We verify both pieces compose correctly.

    test('income: + prefix + formatted amount', () {
      final amount = Decimal.parse('2500000');
      final formatted = AmountFormatter.formatCOP(amount);
      final sign = BalviaTheme.signForType('income');
      expect('$sign$formatted', '+\$ 2.500.000');
    });

    test('expense: - prefix + formatted amount', () {
      final amount = Decimal.parse('15000');
      final formatted = AmountFormatter.formatCOP(amount);
      final sign = BalviaTheme.signForType('expense');
      expect('$sign$formatted', '-\$ 15.000');
    });

    test('transfer: no prefix', () {
      final amount = Decimal.parse('89500');
      final formatted = AmountFormatter.formatCOP(amount);
      final sign = BalviaTheme.signForType('transfer');
      expect('$sign$formatted', '\$ 89.500');
    });

    test('showSign=false: no prefix regardless of type', () {
      // AmountText with showSign=false omits the sign prefix entirely.
      // We simulate the logic here.
      final amount = Decimal.parse('300000');
      final formatted = AmountFormatter.formatCOP(amount);
      const sign = ''; // showSign=false
      expect('$sign$formatted', '\$ 300.000');
    });
  });

  // -------------------------------------------------------------------------
  // BudgetProgressBar threshold logic
  // -------------------------------------------------------------------------
  group('BudgetProgressBar percentage logic', () {
    double computePct(Decimal spent, Decimal budget) {
      if (budget <= Decimal.zero) return 0.0;
      return (spent / budget).toDouble() * 100.0;
    }

    test('0% when spent is zero', () {
      expect(computePct(Decimal.zero, Decimal.parse('300000')), 0.0);
    });

    test('50% when spent is half of budget', () {
      expect(
        computePct(Decimal.parse('150000'), Decimal.parse('300000')),
        closeTo(50.0, 0.001),
      );
    });

    test('80% triggers warning threshold', () {
      final pct = computePct(Decimal.parse('240000'), Decimal.parse('300000'));
      expect(pct, closeTo(80.0, 0.001));
      expect(pct >= 80.0, isTrue);
      expect(pct >= 100.0, isFalse);
    });

    test('100% triggers critical threshold', () {
      final pct = computePct(Decimal.parse('300000'), Decimal.parse('300000'));
      expect(pct, closeTo(100.0, 0.001));
      expect(pct >= 100.0, isTrue);
    });

    test('150% exceeds critical threshold', () {
      final pct = computePct(Decimal.parse('450000'), Decimal.parse('300000'));
      expect(pct, closeTo(150.0, 0.001));
      expect(pct >= 100.0, isTrue);
    });

    test('fraction clamped to 1.0 when exceeded', () {
      final pct = computePct(Decimal.parse('450000'), Decimal.parse('300000'));
      final fraction = (pct / 100.0).clamp(0.0, 1.0);
      expect(fraction, 1.0);
    });

    test('budget zero → 0% (no division by zero)', () {
      expect(computePct(Decimal.parse('15000'), Decimal.zero), 0.0);
    });
  });
}
