import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../core/amount_formatter.dart';
import '../core/theme.dart';

/// Displays a COP amount with semantic color (income green / expense red /
/// transfer blue) and an optional +/- sign prefix.
///
/// [amount] must be the absolute value. [transactionType] drives the color and
/// sign. Pass [showSign] = false to suppress the prefix (e.g. budget bars).
class AmountText extends StatelessWidget {
  const AmountText({
    super.key,
    required this.amount,
    this.transactionType = 'expense',
    this.showSign = true,
    this.style,
    this.textAlign,
  });

  final Decimal amount;

  /// income | expense | transfer — controls color and sign.
  final String transactionType;
  final bool showSign;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final color = BalviaTheme.colorForType(transactionType);
    final sign = showSign ? BalviaTheme.signForType(transactionType) : '';
    final formatted = AmountFormatter.formatCOP(amount);
    final display = sign.isEmpty ? formatted : '$sign$formatted';

    final resolved = (style ?? Theme.of(context).textTheme.bodyMedium)
        ?.copyWith(
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return Text(display, style: resolved, textAlign: textAlign);
  }
}
