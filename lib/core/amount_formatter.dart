import 'package:decimal/decimal.dart';

/// Utilities for formatting and parsing COP amounts in the quick-capture flow.
///
/// The user types raw digits (e.g. "50000"); we format them with thousand
/// separators ("50.000") for display and convert to Decimal for the API
/// ("50000.00").
class AmountFormatter {
  const AmountFormatter._();

  /// Formats an integer-cents string (digits only, no separator) as a
  /// Colombian-peso display string using dots as thousand separators.
  /// E.g.: "1500000" → "1.500.000"
  static String formatDisplay(String rawDigits) {
    if (rawDigits.isEmpty) return '0';
    // Strip leading zeros but keep at least one digit.
    final stripped = rawDigits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final s = stripped.isEmpty ? '0' : stripped;
    // Insert dot every 3 digits from the right.
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// Converts a raw digit string (no separators) to a Decimal suitable for
  /// the API. Colombian pesos have no decimals in practice, but we send
  /// ".00" as required by the contract.
  /// Returns null if the string is empty or zero.
  static Decimal? toDecimal(String rawDigits) {
    if (rawDigits.isEmpty) return null;
    final value = int.tryParse(rawDigits);
    if (value == null || value == 0) return null;
    return Decimal.parse('$value');
  }

  /// Returns a Decimal from a raw digit string; throws if invalid.
  static Decimal parseRequired(String rawDigits) {
    final d = toDecimal(rawDigits);
    if (d == null) throw ArgumentError('Amount must be positive');
    return d;
  }
}
