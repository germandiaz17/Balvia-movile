// Tests for CopAmountInputFormatter (system-keyboard COP amount entry).

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balvia_mobile/core/amount_input_formatter.dart';

TextEditingValue _fmt(String oldText, String newText) {
  const formatter = CopAmountInputFormatter();
  return formatter.formatEditUpdate(
    TextEditingValue(text: oldText),
    TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    ),
  );
}

void main() {
  group('CopAmountInputFormatter', () {
    test('formats plain digits with thousand separators', () {
      expect(_fmt('', '1500000').text, '1.500.000');
    });

    test('typing one digit at a time re-groups separators', () {
      expect(_fmt('1.234', '1.2345').text, '12.345');
    });

    test('deleting across a separator re-groups', () {
      expect(_fmt('12.345', '12.34').text, '1.234');
    });

    test('strips non-digit characters (paste)', () {
      expect(_fmt('', r'$ 1,500.000 COP').text, '1.500.000');
    });

    test('strips leading zeros', () {
      expect(_fmt('', '007').text, '7');
    });

    test('all zeros collapses to empty', () {
      expect(_fmt('', '000').text, '');
    });

    test('caps at 10 raw digits', () {
      expect(_fmt('', '123456789012').text, '1.234.567.890');
    });

    test('empty input stays empty', () {
      expect(_fmt('5', '').text, '');
    });

    test('cursor pinned to end', () {
      final v = _fmt('', '1500000');
      expect(v.selection.baseOffset, v.text.length);
    });
  });
}
