import 'package:flutter/services.dart';

import 'amount_formatter.dart';

/// [TextInputFormatter] for COP amounts typed with the system keyboard.
///
/// Keeps only digits, caps the raw value at [maxDigits] digits, and renders
/// with dots as thousand separators via [AmountFormatter.formatDisplay]
/// (e.g. typing "1500000" shows "1.500.000"). The cursor is pinned to the
/// end — amounts are always appended/deleted at the tail, which matches how
/// the previous in-card keypad behaved.
class CopAmountInputFormatter extends TextInputFormatter {
  const CopAmountInputFormatter({this.maxDigits = 10});

  final int maxDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Drop leading zeros ("0" alone is not a valid amount to submit anyway).
    digits = digits.replaceFirst(RegExp(r'^0+'), '');
    if (digits.length > maxDigits) {
      digits = digits.substring(0, maxDigits);
    }
    final formatted = digits.isEmpty
        ? ''
        : AmountFormatter.formatDisplay(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
