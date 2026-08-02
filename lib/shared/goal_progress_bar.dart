import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../core/amount_formatter.dart';
import '../core/theme.dart';

/// Progress bar for a savings goal.
///
/// Deliberately NOT BudgetProgressBar: there the colour scale is a warning
/// (amber near the limit, red past it), because spending your whole budget is
/// bad. Here reaching 100% is the win, so the bar goes teal → green and never
/// turns red.
class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar({
    super.key,
    required this.current,
    required this.target,
    this.showLabels = true,
  });

  final Decimal current;
  final Decimal target;

  /// Whether to render the "saved / target" row under the bar.
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pct = target > Decimal.zero
        ? (current / target).toDouble() * 100.0
        : 0.0;
    final fraction = (pct / 100.0).clamp(0.0, 1.0);
    final reached = pct >= 100.0;
    final barColor = reached ? BalviaTheme.income : cs.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        if (showLabels) ...[
          const SizedBox(height: BalviaTheme.spaceXs),
          Row(
            children: [
              Text(
                AmountFormatter.formatCOP(current),
                style: BalviaTheme.captionStyle(
                  color: barColor,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                ' de ${AmountFormatter.formatCOP(target)}',
                style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: BalviaTheme.captionStyle(
                  color: reached ? BalviaTheme.income : cs.onSurface,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
