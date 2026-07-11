import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../core/amount_formatter.dart';
import '../core/theme.dart';

/// Horizontal progress bar for a budget item.
///
/// Shows the spent amount over the budget amount with threshold markers at
/// [warningPct] (default 80) and [criticalPct] (default 100).
/// Color follows design brief §3:
///   < warningPct → primary (teal)
///   ≥ warningPct && < criticalPct → amber warning
///   ≥ criticalPct → red (exceeded)
class BudgetProgressBar extends StatelessWidget {
  BudgetProgressBar({
    super.key,
    required this.spent,
    required this.budget,
    Decimal? warningPct,
    Decimal? criticalPct,
    this.showLabels = true,
  }) : warningPct = warningPct ?? _defaultWarning,
       criticalPct = criticalPct ?? _defaultCritical;

  static final _defaultWarning = Decimal.fromInt(80);
  static final _defaultCritical = Decimal.fromInt(100);

  final Decimal spent;
  final Decimal budget;
  final Decimal warningPct;
  final Decimal criticalPct;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Compute compliance percentage as double (Decimal / Decimal → Rational).
    final pctDouble = budget > Decimal.zero
        ? (spent / budget).toDouble() * 100.0
        : 0.0;

    // Progress fraction clamped to [0, 1] for the bar visual.
    final fraction = (pctDouble / 100.0).clamp(0.0, 1.0);

    final warnDouble = warningPct.toDouble();
    final critDouble = criticalPct.toDouble();

    final barColor = pctDouble >= critDouble
        ? BalviaTheme.budgetExceeded
        : pctDouble >= warnDouble
        ? BalviaTheme.budgetWarning
        : cs.primary;

    final pctText = '${pctDouble.toStringAsFixed(0)} %';
    final spentText = AmountFormatter.formatCOP(spent);
    final budgetText = AmountFormatter.formatCOP(budget);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bar.
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        if (showLabels) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$spentText de $budgetText',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                pctText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: barColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
