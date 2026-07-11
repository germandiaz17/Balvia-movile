import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../core/amount_formatter.dart';
import '../core/theme.dart';
import '../data/models/tracking_period.dart';

/// Teal hero card for the active tracking period (mockup 12 / design system §3).
///
/// Shows:
///   - "Seguimiento activo" label + date range
///   - "Día X de Y" + progress % + linear bar
///   - Hero amount (gasto total) in large white text
///   - Row: Ingresos / Gastos / Balance with semantic colors
///
/// [totalExpense], [totalIncome], [balance] are passed in so the card stays
/// a pure display widget (data comes from DashboardScreen providers).
class PeriodHeroCard extends StatelessWidget {
  const PeriodHeroCard({
    super.key,
    required this.period,
    required this.totalExpense,
    required this.totalIncome,
    required this.balance,
    this.onViewSelector,
    this.selectedView = 'full',
  });

  final TrackingPeriod period;
  final Decimal totalExpense;
  final Decimal totalIncome;
  final Decimal balance;

  /// Callback when the view selector (Completa/Quincenal/Semanal) changes.
  final ValueChanged<String>? onViewSelector;
  final String selectedView;

  @override
  Widget build(BuildContext context) {
    final progress = period.progressFraction;
    final pctText = '${(progress * 100).round()}%';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: BalviaTheme.spaceMd),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14B8A6), Color(0xFF0F9D8C)],
        ),
        borderRadius: BorderRadius.circular(BalviaTheme.radiusLg),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F9D8C).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(BalviaTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: label + "Seguimiento activo" chip
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(
                  'Seguimiento activo',
                  style: BalviaTheme.captionStyle(color: Colors.white70),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BalviaTheme.spaceSm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
                  ),
                  child: Text(
                    _viewLabel(selectedView),
                    style: BalviaTheme.captionStyle(
                      color: Colors.white,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BalviaTheme.spaceXs),
            Text(
              '${_fmtDate(period.startDate)} – ${_fmtDate(period.endDate)}',
              style: BalviaTheme.bodyStyle(
                color: Colors.white,
              ).copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: BalviaTheme.spaceSm),

            // Progress row
            Row(
              children: [
                Text(
                  'Día ${period.daysElapsed} de ${period.durationDays}',
                  style: BalviaTheme.captionStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),
                Text(
                  pctText,
                  style: BalviaTheme.captionStyle(
                    color: Colors.white,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(BalviaTheme.radiusXs),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                color: Colors.white,
              ),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            // Hero amount
            Text(
              '\$${AmountFormatter.formatDisplay(totalExpense.truncate().toBigInt().toString())}',
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              'Gasto total del periodo',
              style: BalviaTheme.captionStyle(
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            // Ingresos / Gastos / Balance row
            Row(
              children: [
                Expanded(
                  child: _HeroMetric(
                    label: 'Ingresos',
                    amount: totalIncome,
                    sign: '+',
                    color: const Color(0xFF81C784),
                  ),
                ),
                Expanded(
                  child: _HeroMetric(
                    label: 'Gastos',
                    amount: totalExpense,
                    sign: '-',
                    color: const Color(0xFFEF9A9A),
                  ),
                ),
                Expanded(
                  child: _HeroMetric(
                    label: 'Balance',
                    amount: balance,
                    sign: balance >= Decimal.zero ? '+' : '',
                    color: const Color(0xFF80DEEA),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _viewLabel(String view) => switch (view) {
    'biweekly' => 'Quincenal',
    'weekly' => 'Semanal',
    _ => 'Completa',
  };

  String _fmtDate(String yyyyMmDd) {
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
    return '${dt.day} ${months[dt.month - 1]}';
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.amount,
    required this.sign,
    required this.color,
  });

  final String label;
  final Decimal amount;
  final String sign;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$sign${AmountFormatter.formatCOP(amount)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          label,
          style: BalviaTheme.captionStyle(
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
