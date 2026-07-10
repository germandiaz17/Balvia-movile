import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/amount_formatter.dart';
import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../data/models/period_summary.dart';
import '../../data/models/tracking_period.dart';
import '../../data/models/transaction.dart';

/// Formats a YYYY-MM-DD string as "4 jul. 2026" (es-CO abbreviated).
String _formatDate(String yyyyMmDd) {
  final dt = DateTime.parse(yyyyMmDd);
  // Day / abbreviated month / year in Spanish.
  const months = [
    'ene.',
    'feb.',
    'mar.',
    'abr.',
    'may.',
    'jun.',
    'jul.',
    'ago.',
    'sep.',
    'oct.',
    'nov.',
    'dic.',
  ];
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

// ---------------------------------------------------------------------------
// Dashboard screen
// ---------------------------------------------------------------------------

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodAsync = ref.watch(activeTrackingPeriodProvider);
    final summaryAsync = ref.watch(periodSummaryProvider);
    final recentAsync = ref.watch(recentTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguimiento'),
        actions: [
          // Manual refresh button.
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Period header.
            periodAsync.when(
              loading: () => const _SectionSkeleton(height: 120),
              error: (e, _) => _ErrorCard(message: apiErrorMessage(e)),
              data: (period) => _PeriodHeader(period: period),
            ),
            const SizedBox(height: 16),

            // View selector.
            const _ViewSelector(),
            const SizedBox(height: 16),

            // Summary totals.
            summaryAsync.when(
              loading: () => const _SectionSkeleton(height: 180),
              error: (e, _) => _ErrorCard(message: apiErrorMessage(e)),
              data: (summary) => _SummaryCard(summary: summary),
            ),
            const SizedBox(height: 16),

            // Sub-periods (biweekly / weekly only).
            summaryAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (e, st) => const SizedBox.shrink(),
              data: (summary) {
                final subs = summary.subPeriods;
                if (subs == null || subs.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bloques del periodo',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...subs.map((s) => _SubPeriodCard(sub: s)),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),

            // Recent transactions.
            Text(
              'Transacciones recientes',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            recentAsync.when(
              loading: () => const _SectionSkeleton(height: 200),
              error: (e, _) => _ErrorCard(message: apiErrorMessage(e)),
              data: (txs) => txs.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Aún no hay transacciones este periodo.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : _RecentTransactionsList(transactions: txs),
            ),
          ],
        ),
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(activeTrackingPeriodProvider);
    ref.invalidate(periodSummaryProvider);
    ref.invalidate(recentTransactionsProvider);
  }
}

// ---------------------------------------------------------------------------
// Period header
// ---------------------------------------------------------------------------

class _PeriodHeader extends StatelessWidget {
  const _PeriodHeader({required this.period});
  final TrackingPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period number badge + status.
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Seguimiento #${period.sequenceNumber}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (period.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Activo',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Date range.
            Text(
              '${_formatDate(period.startDate)} – ${_formatDate(period.endDate)}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),

            // Progress bar.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: period.progressFraction,
                minHeight: 8,
                backgroundColor: cs.surfaceContainerHighest,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 6),

            // Day counters.
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

// ---------------------------------------------------------------------------
// View selector (Completa / Quincenal / Semanal)
// ---------------------------------------------------------------------------

class _ViewSelector extends ConsumerWidget {
  const _ViewSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentView = ref.watch(dashboardViewProvider);

    const views = [
      ('full', 'Completa'),
      ('biweekly', 'Quincenal'),
      ('weekly', 'Semanal'),
    ];

    return SegmentedButton<String>(
      segments: views
          .map((v) => ButtonSegment<String>(value: v.$1, label: Text(v.$2)))
          .toList(),
      selected: {currentView},
      onSelectionChanged: (selection) {
        ref.read(dashboardViewProvider.notifier).setView(selection.first);
      },
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});
  final PeriodSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final savingsPositive = summary.netSavings >= Decimal.zero;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Net savings (highlight).
            Text('Ahorro neto', style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              AmountFormatter.formatCOP(summary.netSavings),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: savingsPositive ? cs.primary : cs.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${summary.savingsRate.toStringAsFixed(1)} % del ingreso',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // Income / Expenses row.
            Row(
              children: [
                Expanded(
                  child: _MetricCell(
                    label: 'Ingresos',
                    amount: summary.totalIncome,
                    color: cs.primary,
                    icon: Icons.arrow_downward,
                  ),
                ),
                Container(width: 1, height: 56, color: cs.outlineVariant),
                Expanded(
                  child: _MetricCell(
                    label: 'Gastos',
                    amount: summary.totalExpenses,
                    color: cs.error,
                    icon: Icons.arrow_upward,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Transaction count.
            Text(
              '${summary.transactionCount} transacciones '
              '(${summary.incomeTransactionCount} ing. · '
              '${summary.expenseTransactionCount} gas.)',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  final String label;
  final Decimal amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          AmountFormatter.formatCOP(amount),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-period card
// ---------------------------------------------------------------------------

class _SubPeriodCard extends StatelessWidget {
  const _SubPeriodCard({required this.sub});
  final SubPeriod sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isCurrent = sub.isCurrent;

    return Card(
      color: isCurrent ? cs.primaryContainer.withValues(alpha: 0.35) : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Bloque ${sub.index}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isCurrent ? cs.primary : null,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Actual',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '${_formatDate(sub.from)} – ${_formatDate(sub.to)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SubMetric(
                    label: 'Ingresos',
                    value: AmountFormatter.formatCOP(sub.totalIncome),
                  ),
                ),
                Expanded(
                  child: _SubMetric(
                    label: 'Gastos',
                    value: AmountFormatter.formatCOP(sub.totalExpenses),
                  ),
                ),
                Expanded(
                  child: _SubMetric(
                    label: 'Ahorro',
                    value: AmountFormatter.formatCOP(sub.netSavings),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SubMetric extends StatelessWidget {
  const _SubMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recent transactions list
// ---------------------------------------------------------------------------

class _RecentTransactionsList extends StatelessWidget {
  const _RecentTransactionsList({required this.transactions});
  final List<Transaction> transactions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: transactions.map((tx) => _TransactionTile(tx: tx)).toList(),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});
  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isExpense = tx.transactionType == 'expense';
    final isTransfer = tx.transactionType == 'transfer';
    final amountColor = isExpense
        ? cs.error
        : isTransfer
        ? cs.secondary
        : cs.primary;
    final sign = isExpense
        ? '-'
        : isTransfer
        ? ''
        : '+';
    final amountText = '$sign ${AmountFormatter.formatCOP(tx.amount)}';

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: amountColor.withValues(alpha: 0.15),
          child: Icon(
            isExpense
                ? Icons.arrow_upward
                : isTransfer
                ? Icons.swap_horiz
                : Icons.arrow_downward,
            size: 16,
            color: amountColor,
          ),
        ),
        title: Text(
          tx.description ?? _typeLabel(tx.transactionType),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _formatDate(tx.transactionDate),
          style: theme.textTheme.bodySmall,
        ),
        trailing: Text(
          amountText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: amountColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeletons & error helpers
// ---------------------------------------------------------------------------

class _SectionSkeleton extends StatelessWidget {
  const _SectionSkeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: cs.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

const _txTypeLabels = {
  'expense': 'Gasto',
  'income': 'Ingreso',
  'transfer': 'Transferencia',
};

String _typeLabel(String type) => _txTypeLabels[type] ?? type;
