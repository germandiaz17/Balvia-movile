import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/core/amount_formatter.dart';

void main() {
  group('AmountFormatter.formatCOP', () {
    test('positive amount with separators', () {
      expect(
        AmountFormatter.formatCOP(Decimal.parse('1500000')),
        r'$ 1.500.000',
      );
    });

    test('negative amount', () {
      expect(AmountFormatter.formatCOP(Decimal.parse('-50000')), r'- $ 50.000');
    });

    test('zero', () {
      expect(AmountFormatter.formatCOP(Decimal.zero), r'$ 0');
    });

    test('truncates fractional cents', () {
      expect(AmountFormatter.formatCOP(Decimal.parse('12000.99')), r'$ 12.000');
    });
  });

  group('AmountFormatter.formatDisplay', () {
    test('empty string returns "0"', () {
      expect(AmountFormatter.formatDisplay(''), '0');
    });

    test('single digit', () {
      expect(AmountFormatter.formatDisplay('5'), '5');
    });

    test('three digits - no separator', () {
      expect(AmountFormatter.formatDisplay('500'), '500');
    });

    test('four digits - one separator', () {
      expect(AmountFormatter.formatDisplay('5000'), '5.000');
    });

    test('seven digits - two separators', () {
      expect(AmountFormatter.formatDisplay('1500000'), '1.500.000');
    });

    test('typical COP amount', () {
      expect(AmountFormatter.formatDisplay('50000'), '50.000');
    });

    test('large amount', () {
      expect(AmountFormatter.formatDisplay('1000000000'), '1.000.000.000');
    });

    test('strips leading zeros', () {
      expect(AmountFormatter.formatDisplay('0050'), '50');
    });
  });

  group('AmountFormatter.toDecimal', () {
    test('empty string returns null', () {
      expect(AmountFormatter.toDecimal(''), isNull);
    });

    test('"0" returns null', () {
      expect(AmountFormatter.toDecimal('0'), isNull);
    });

    test('valid amount returns Decimal', () {
      expect(AmountFormatter.toDecimal('15000'), Decimal.parse('15000'));
    });

    test('returns Decimal type (never double)', () {
      expect(AmountFormatter.toDecimal('5000'), isA<Decimal>());
    });
  });

  group('AmountFormatter.parseRequired', () {
    test('throws on empty', () {
      expect(
        () => AmountFormatter.parseRequired(''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws on zero', () {
      expect(
        () => AmountFormatter.parseRequired('0'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('returns correct Decimal for valid input', () {
      expect(AmountFormatter.parseRequired('99000'), Decimal.parse('99000'));
    });
  });
}
