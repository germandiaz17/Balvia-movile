import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/amount_formatter.dart';
import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models/budget.dart';
import '../../data/models/category.dart';
import '../../data/models/tracking_period.dart';
import '../../data/models/transaction.dart';
import '../../shared/category_avatar.dart';
import '../../shared/empty_state.dart';

// ---------------------------------------------------------------------------
// Decision: spent amount per category in the progress bars
//
// The summary JSONB breakdown (expense_by_category) is only populated for
// CLOSED periods; for the active period those fields are omitted (omitempty).
// Therefore we calculate the spent amount locally from the Drift-backed
// transaction stream (localTransactionsProvider). This is:
//   1. Offline-first — works without a network call.
//   2. Always current — updates live as transactions are added.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetsAsync = ref.watch(budgetsProvider);
    final periodAsync = ref.watch(activeTrackingPeriodProvider);
    final txsAsync = ref.watch(allTransactionsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(budgetsProvider);
          ref.invalidate(activeTrackingPeriodProvider);
          ref.invalidate(allTransactionsProvider);
        },
        child: _buildBody(
          context,
          ref,
          budgetsAsync: budgetsAsync,
          periodAsync: periodAsync,
          txsAsync: txsAsync,
          categoriesAsync: categoriesAsync,
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref, {
    required AsyncValue<List<Budget>> budgetsAsync,
    required AsyncValue<TrackingPeriod> periodAsync,
    required AsyncValue<List<Transaction>> txsAsync,
    required AsyncValue<List<Category>> categoriesAsync,
  }) {
    return budgetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorBody(message: apiErrorMessage(e)),
      data: (budgets) {
        final period = periodAsync.value;
        final txs = txsAsync.value ?? [];
        final categories = categoriesAsync.value ?? [];

        final spentMap = _buildSpentMap(txs);

        final global = budgets.where((b) => b.categoryId == null).firstOrNull;
        final catBudgets = budgets.where((b) => b.categoryId != null).toList();

        if (budgets.isEmpty) {
          return EmptyState(
            icon: Icons.pie_chart_outline,
            title: 'Sin presupuestos aún',
            subtitle:
                'Crea tu primer presupuesto para controlar tus gastos.\n'
                'Los presupuestos se copian automáticamente al siguiente seguimiento.',
            cta: 'Nuevo presupuesto',
            onCta: () => _showBudgetForm(context, ref, categories: categories),
          );
        }

        // Totals for the 3-stat header chips.
        var totalBudget = Decimal.zero;
        for (final b in budgets) {
          totalBudget += b.amount;
        }
        final totalSpent = spentMap[null] ?? Decimal.zero;
        final totalAvailable = totalBudget - totalSpent;

        return CustomScrollView(
          slivers: [
            // ---- Big title + period date range chip ----
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  BalviaTheme.spaceMd,
                  BalviaTheme.spaceLg,
                  BalviaTheme.spaceMd,
                  BalviaTheme.spaceMd,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Presupuestos',
                      style: BalviaTheme.headlineStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    if (period != null) _PeriodChip(period: period),
                  ],
                ),
              ),
            ),

            // ---- 3-stat chips row ----
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BalviaTheme.spaceMd,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        label: 'Presupuestado',
                        amount: totalBudget,
                        amountColor: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: BalviaTheme.spaceSm),
                    Expanded(
                      child: _StatChip(
                        label: 'Gastado',
                        amount: totalSpent,
                        amountColor: BalviaTheme.expense,
                      ),
                    ),
                    const SizedBox(width: BalviaTheme.spaceSm),
                    Expanded(
                      child: _StatChip(
                        label: 'Disponible',
                        amount: totalAvailable,
                        amountColor: totalAvailable >= Decimal.zero
                            ? BalviaTheme.income
                            : BalviaTheme.expense,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: BalviaTheme.spaceMd),
            ),

            // ---- PRESUPUESTO GLOBAL section ----
            if (global != null) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BalviaTheme.spaceMd,
                    0,
                    BalviaTheme.spaceMd,
                    BalviaTheme.spaceSm,
                  ),
                  child: Text(
                    'PRESUPUESTO GLOBAL',
                    style: BalviaTheme.overlineStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BalviaTheme.spaceMd,
                  ),
                  child: _GlobalBudgetCard(
                    budget: global,
                    spent: spentMap[null] ?? Decimal.zero,
                    onEdit: () => _showBudgetForm(
                      context,
                      ref,
                      existing: global,
                      categories: categories,
                    ),
                    onDelete: () => _confirmDelete(context, ref, global),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: BalviaTheme.spaceMd),
              ),
            ],

            // ---- POR CATEGORÍA section ----
            if (catBudgets.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BalviaTheme.spaceMd,
                    0,
                    BalviaTheme.spaceMd,
                    BalviaTheme.spaceSm,
                  ),
                  child: Text(
                    'POR CATEGORÍA',
                    style: BalviaTheme.overlineStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              SliverList.separated(
                itemCount: catBudgets.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: BalviaTheme.spaceSm),
                itemBuilder: (ctx, i) {
                  final b = catBudgets[i];
                  final cat = categories
                      .where((c) => c.id == b.categoryId)
                      .firstOrNull;
                  final spent = spentMap[b.categoryId] ?? Decimal.zero;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BalviaTheme.spaceMd,
                    ),
                    child: _CategoryBudgetCard(
                      budget: b,
                      category: cat,
                      spent: spent,
                      onEdit: () => _showBudgetForm(
                        ctx,
                        ref,
                        existing: b,
                        categories: categories,
                      ),
                      onDelete: () => _confirmDelete(ctx, ref, b),
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: BalviaTheme.spaceMd),
              ),
            ],

            // ---- Info banner ----
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BalviaTheme.spaceMd,
                ),
                child: _InfoBanner(
                  text:
                      'Los presupuestos se copian automáticamente al siguiente '
                      'seguimiento para que no tengas que configurarlos de nuevo.',
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: BalviaTheme.spaceMd),
            ),

            // ---- "Nuevo presupuesto" wide button ----
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BalviaTheme.spaceMd,
                ),
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo presupuesto'),
                  onPressed: () =>
                      _showBudgetForm(context, ref, categories: categories),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      },
    );
  }

  /// Builds a map of categoryId → total spent from expense transactions.
  /// null key = total of all expense transactions (for global budget).
  Map<String?, Decimal> _buildSpentMap(List<Transaction> txs) {
    final map = <String?, Decimal>{};
    Decimal globalTotal = Decimal.zero;
    for (final tx in txs) {
      if (tx.transactionType != 'expense') continue;
      globalTotal += tx.amount;
      final catId = tx.categoryId;
      map[catId] = (map[catId] ?? Decimal.zero) + tx.amount;
    }
    map[null] = globalTotal;
    return map;
  }

  void _showBudgetForm(
    BuildContext context,
    WidgetRef ref, {
    Budget? existing,
    required List<Category> categories,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetFormSheet(
        existing: existing,
        categories: categories,
        onSave: (amount, categoryId, warnPct, critPct, notes) async {
          final repo = ref.read(budgetRepositoryProvider);
          if (existing == null) {
            await repo.create(
              amount: amount,
              categoryId: categoryId,
              alertThresholdWarning: warnPct,
              alertThresholdCritical: critPct,
              notes: notes,
            );
          } else {
            await repo.update(
              existing.id,
              amount: amount,
              categoryId: categoryId,
              alertThresholdWarning: warnPct,
              alertThresholdCritical: critPct,
              notes: notes,
            );
          }
          ref.invalidate(budgetsProvider);
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Budget budget,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar presupuesto'),
        content: const Text(
          '¿Eliminar este presupuesto? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(budgetRepositoryProvider).delete(budget.id);
      ref.invalidate(budgetsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Presupuesto eliminado'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Period chip
// ---------------------------------------------------------------------------

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.period});
  final TrackingPeriod period;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Format "26 jun – 25 jul"
    final start = _shortDate(period.startDate);
    final end = _shortDate(period.endDate);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Text(
        '$start – $end',
        style: BalviaTheme.captionStyle(
          color: cs.onSurfaceVariant,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  String _shortDate(String yyyyMmDd) {
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

// ---------------------------------------------------------------------------
// Stat chip
// ---------------------------------------------------------------------------

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.amount,
    required this.amountColor,
  });

  final String label;
  final Decimal amount;
  final Color amountColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BalviaTheme.spaceSm,
        vertical: BalviaTheme.spaceSm,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            AmountFormatter.formatCOP(amount),
            style: BalviaTheme.bodyStyle(
              color: amountColor,
            ).copyWith(fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Global budget card — teal tint, "$" icon, % right, bar, footer labels
// ---------------------------------------------------------------------------

class _GlobalBudgetCard extends StatelessWidget {
  const _GlobalBudgetCard({
    required this.budget,
    required this.spent,
    required this.onEdit,
    required this.onDelete,
  });

  final Budget budget;
  final Decimal spent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pctDouble = budget.amount > Decimal.zero
        ? (spent / budget.amount).toDouble() * 100.0
        : 0.0;
    final fraction = (pctDouble / 100.0).clamp(0.0, 1.0);
    final barColor = cs.primary;

    return Card(
      color: BalviaTheme.surfaceTonal,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BalviaTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: icon + name + % + edit/delete
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: BalviaTheme.seed.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
                  ),
                  child: const Icon(
                    Icons.attach_money,
                    color: BalviaTheme.seed,
                    size: 20,
                  ),
                ),
                const SizedBox(width: BalviaTheme.spaceSm),
                Expanded(
                  child: Text(
                    'Global del seguimiento',
                    style: BalviaTheme.bodyStyle(
                      color: cs.onSurface,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${pctDouble.toStringAsFixed(0)}%',
                  style: BalviaTheme.bodyStyle(
                    color: cs.onSurface,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                _EditDeleteButtons(onEdit: onEdit, onDelete: onDelete),
              ],
            ),

            const SizedBox(height: BalviaTheme.spaceSm),

            // Progress bar.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),

            const SizedBox(height: BalviaTheme.spaceXs),

            // Footer labels.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${AmountFormatter.formatCOP(spent)} gastados',
                  style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
                ),
                Text(
                  '${AmountFormatter.formatCOP(budget.amount)} total',
                  style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
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
// Category budget card — with alert badge and colored right note
// ---------------------------------------------------------------------------

class _CategoryBudgetCard extends StatelessWidget {
  const _CategoryBudgetCard({
    required this.budget,
    required this.category,
    required this.spent,
    required this.onEdit,
    required this.onDelete,
  });

  final Budget budget;
  final Category? category;
  final Decimal spent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final pctDouble = budget.amount > Decimal.zero
        ? (spent / budget.amount).toDouble() * 100.0
        : 0.0;
    final fraction = (pctDouble / 100.0).clamp(0.0, 1.0);

    final warnDouble = budget.alertThresholdWarning.toDouble();
    final critDouble = budget.alertThresholdCritical.toDouble();

    final barColor = pctDouble >= critDouble
        ? BalviaTheme.budgetExceeded
        : pctDouble >= warnDouble
        ? BalviaTheme.budgetWarning
        : BalviaTheme.income;

    final available = budget.amount - spent;

    // Right note color and text based on threshold.
    final Color noteColor;
    final String noteText;
    if (pctDouble >= critDouble) {
      noteColor = BalviaTheme.expense;
      final over = spent - budget.amount;
      noteText = '-${AmountFormatter.formatCOP(over)} excedido';
    } else if (pctDouble >= warnDouble) {
      noteColor = BalviaTheme.budgetWarning;
      noteText = '${AmountFormatter.formatCOP(available)} restante';
    } else {
      noteColor = BalviaTheme.income;
      noteText = '${AmountFormatter.formatCOP(available)} disponible';
    }

    // Alert badge: only show if >= warning threshold.
    Widget? badge;
    if (pctDouble >= critDouble) {
      badge = _AlertBadge(
        icon: Icons.close,
        pct: pctDouble,
        color: BalviaTheme.expense,
      );
    } else if (pctDouble >= warnDouble) {
      badge = _AlertBadge(
        icon: Icons.arrow_upward,
        pct: pctDouble,
        color: BalviaTheme.budgetWarning,
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(BalviaTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: avatar + name + (optional badge) + % + edit/delete
            Row(
              children: [
                CategoryAvatar(category: category, radius: 18),
                const SizedBox(width: BalviaTheme.spaceSm),
                Expanded(
                  child: Text(
                    category?.name ?? 'Sin categoría',
                    style: BalviaTheme.bodyStyle(
                      color: cs.onSurface,
                    ).copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge != null) ...[badge, const SizedBox(width: 4)],
                Text(
                  '${pctDouble.toStringAsFixed(0)}%',
                  style: BalviaTheme.bodyStyle(
                    color: barColor,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                _EditDeleteButtons(onEdit: onEdit, onDelete: onDelete),
              ],
            ),

            const SizedBox(height: BalviaTheme.spaceSm),

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

            const SizedBox(height: BalviaTheme.spaceXs),

            // Footer.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${AmountFormatter.formatCOP(spent)} '
                  'de ${AmountFormatter.formatCOP(budget.amount)}',
                  style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
                ),
                Text(
                  noteText,
                  style: BalviaTheme.captionStyle(
                    color: noteColor,
                  ).copyWith(fontWeight: FontWeight.w600),
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
// Alert badge (▲85% amber / ✕110% red)
// ---------------------------------------------------------------------------

class _AlertBadge extends StatelessWidget {
  const _AlertBadge({
    required this.icon,
    required this.pct,
    required this.color,
  });

  final IconData icon;
  final double pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: BalviaTheme.captionStyle(
              color: color,
            ).copyWith(fontWeight: FontWeight.w700, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit/delete icon button row
// ---------------------------------------------------------------------------

class _EditDeleteButtons extends StatelessWidget {
  const _EditDeleteButtons({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Editar',
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: onEdit,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
        IconButton(
          tooltip: 'Eliminar',
          icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
          onPressed: onDelete,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Info banner (amber)
// ---------------------------------------------------------------------------

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BalviaTheme.spaceMd),
      decoration: BoxDecoration(
        color: BalviaTheme.budgetWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        border: Border.all(
          color: BalviaTheme.budgetWarning.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: BalviaTheme.budgetWarning,
            size: 18,
          ),
          const SizedBox(width: BalviaTheme.spaceSm),
          Expanded(
            child: Text(
              text,
              style: BalviaTheme.captionStyle(
                color: BalviaTheme.budgetWarning.withValues(alpha: 0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget form sheet (create / edit) — unchanged logic
// ---------------------------------------------------------------------------

typedef _BudgetSaveCallback =
    Future<void> Function(
      Decimal amount,
      String? categoryId,
      Decimal warningPct,
      Decimal criticalPct,
      String? notes,
    );

class _BudgetFormSheet extends StatefulWidget {
  const _BudgetFormSheet({
    required this.categories,
    required this.onSave,
    this.existing,
  });

  final Budget? existing;
  final List<Category> categories;
  final _BudgetSaveCallback onSave;

  @override
  State<_BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends State<_BudgetFormSheet> {
  late TextEditingController _amountCtrl;
  late TextEditingController _warningCtrl;
  late TextEditingController _criticalCtrl;
  late TextEditingController _notesCtrl;

  String? _selectedCategoryId;
  bool _isGlobal = false;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _amountCtrl = TextEditingController(
      text: b != null ? b.amount.truncate().toBigInt().toString() : '',
    );
    _warningCtrl = TextEditingController(
      text: b != null ? b.alertThresholdWarning.toStringAsFixed(0) : '80',
    );
    _criticalCtrl = TextEditingController(
      text: b != null ? b.alertThresholdCritical.toStringAsFixed(0) : '100',
    );
    _notesCtrl = TextEditingController(text: b?.notes ?? '');
    _selectedCategoryId = b?.categoryId;
    _isGlobal = _selectedCategoryId == null;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _warningCtrl.dispose();
    _criticalCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rawAmount = _amountCtrl.text.trim();
    if (rawAmount.isEmpty) {
      setState(() => _error = 'El monto es requerido');
      return;
    }
    final amount = Decimal.tryParse(rawAmount);
    if (amount == null || amount <= Decimal.zero) {
      setState(() => _error = 'Monto inválido (debe ser mayor a cero)');
      return;
    }

    final rawWarn = _warningCtrl.text.trim();
    final rawCrit = _criticalCtrl.text.trim();
    final warnPct = Decimal.tryParse(rawWarn.isEmpty ? '80' : rawWarn);
    final critPct = Decimal.tryParse(rawCrit.isEmpty ? '100' : rawCrit);
    if (warnPct == null || critPct == null) {
      setState(() => _error = 'Umbrales inválidos');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await widget.onSave(
        amount,
        _isGlobal ? null : _selectedCategoryId,
        warnPct,
        critPct,
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      final msg = apiErrorMessage(e);
      setState(() {
        _isLoading = false;
        _error = msg.contains('409') || msg.toLowerCase().contains('conflict')
            ? 'Ya existe un presupuesto para esta categoría'
            : msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final expenseCats =
        widget.categories.where((c) => c.categoryType == 'expense').toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(BalviaTheme.radiusXl),
        ),
      ),
      padding: EdgeInsets.only(
        left: BalviaTheme.spaceMd,
        right: BalviaTheme.spaceMd,
        top: BalviaTheme.spaceMd,
        bottom: MediaQuery.of(context).viewInsets.bottom + BalviaTheme.spaceLg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),
            Text(
              widget.existing == null
                  ? 'Nuevo presupuesto'
                  : 'Editar presupuesto',
              style: BalviaTheme.titleStyle(color: cs.onSurface),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            SwitchListTile(
              value: _isGlobal,
              onChanged: widget.existing != null
                  ? null
                  : (v) => setState(() {
                      _isGlobal = v;
                      if (v) _selectedCategoryId = null;
                    }),
              title: const Text('Presupuesto global'),
              subtitle: const Text(
                'Aplica al gasto total del periodo (sin categoría)',
              ),
              contentPadding: EdgeInsets.zero,
            ),

            if (!_isGlobal) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategoryId,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Seleccionar categoría'),
                items: expenseCats
                    .map(
                      (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                    )
                    .toList(),
                onChanged: widget.existing != null
                    ? null
                    : (v) => setState(() => _selectedCategoryId = v),
              ),
            ],
            const SizedBox(height: 12),

            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Monto (COP)',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                hintText: 'Ej: 500000',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _warningCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Alerta (%)',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                      hintText: '80',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _criticalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Excedido (%)',
                      suffixText: '%',
                      border: OutlineInputBorder(),
                      hintText: '100',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.error, fontSize: 13),
                ),
              ),

            FilledButton(
              onPressed: _isLoading ? null : _save,
              child: _isLoading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      widget.existing == null
                          ? 'Crear presupuesto'
                          : 'Guardar cambios',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error body
// ---------------------------------------------------------------------------

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
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
      ),
    );
  }
}
