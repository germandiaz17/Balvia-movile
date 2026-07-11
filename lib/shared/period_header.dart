import 'package:flutter/material.dart';

import '../data/models/tracking_period.dart';

/// Compact header card for the active tracking period.
///
/// Shows: date range, progress bar, "Día X de Y" and remaining days.
/// Used at the top of the Budgets screen and in the Dashboard.
class PeriodHeader extends StatelessWidget {
  const PeriodHeader({super.key, required this.period});

  final TrackingPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Seguimiento #${period.sequenceNumber}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (period.isActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Activo',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_fmt(period.startDate)} – ${_fmt(period.endDate)}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: period.progressFraction,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Día ${period.daysElapsed} de ${period.durationDays}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  '${period.daysRemaining} días restantes',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _fmt(String yyyyMmDd) {
  final dt = DateTime.parse(yyyyMmDd);
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}
