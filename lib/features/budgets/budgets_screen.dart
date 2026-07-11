import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../data/models/budget.dart';
import '../../data/models/category.dart';
import '../../data/models/tracking_period.dart';
import '../../data/models/transaction.dart';
import '../../shared/budget_progress_bar.dart';
import '../../shared/empty_state.dart';
import '../../shared/period_header.dart';

// ---------------------------------------------------------------------------
// Decision: spent amount per category in the progress bars
//
// The summary JSONB breakdown (expense_by_category) is only populated for
// CLOSED periods; for the active period those fields are omitted (omitempty).
// Therefore we calculate the spent amount locally from the Drift-backed
// transaction stream (localTransactionsProvider). This is:
//   1. Offline-first — works without a network call.
//   2. Always current — updates live as transactions are added.
// We import allTransactionsProvider (which falls back to Drift).
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
      appBar: AppBar(
        title: const Text('Presupuestos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(budgetsProvider);
              ref.invalidate(activeTrackingPeriodProvider);
              ref.invalidate(allTransactionsProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_new_budget',
        icon: const Icon(Icons.add),
        label: const Text('Nuevo presupuesto'),
        onPressed: () {
          final categories = categoriesAsync.value ?? [];
          _showBudgetForm(context, ref, categories: categories);
        },
      ),
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

        // Compute spent per category_id from local transactions.
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
            onCta: () {
              _showBudgetForm(context, ref, categories: categories);
            },
          );
        }

        return ListView(
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: 100,
          ),
          children: [
            // Period header.
            if (period != null) ...[
              PeriodHeader(period: period),
              const SizedBox(height: 16),
            ],

            // Summary row: total presupuestado vs gastado.
            if (budgets.isNotEmpty) ...[
              _PeriodBudgetSummary(budgets: budgets, spentMap: spentMap),
              const SizedBox(height: 16),
            ],

            // Global budget (category_id: null).
            if (global != null) ...[
              _SectionLabel(label: 'Presupuesto global'),
              _BudgetCard(
                budget: global,
                spent: spentMap[null] ?? Decimal.zero,
                categoryName: 'Global (todo el periodo)',
                onEdit: () => _showBudgetForm(
                  context,
                  ref,
                  existing: global,
                  categories: categories,
                ),
                onDelete: () => _confirmDelete(context, ref, global),
              ),
              const SizedBox(height: 16),
            ],

            // Per-category budgets.
            if (catBudgets.isNotEmpty) ...[
              _SectionLabel(label: 'Por categoría'),
              ...catBudgets.map((b) {
                final cat = categories
                    .where((c) => c.id == b.categoryId)
                    .firstOrNull;
                return _BudgetCard(
                  budget: b,
                  spent: spentMap[b.categoryId] ?? Decimal.zero,
                  categoryName: cat?.name ?? 'Sin categoría',
                  onEdit: () => _showBudgetForm(
                    context,
                    ref,
                    existing: b,
                    categories: categories,
                  ),
                  onDelete: () => _confirmDelete(context, ref, b),
                );
              }),
            ],
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
// Period budget summary row
// ---------------------------------------------------------------------------

class _PeriodBudgetSummary extends StatelessWidget {
  const _PeriodBudgetSummary({required this.budgets, required this.spentMap});

  final List<Budget> budgets;
  final Map<String?, Decimal> spentMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Total budgeted = sum of all budget amounts.
    var totalBudget = Decimal.zero;
    for (final b in budgets) {
      totalBudget += b.amount;
    }

    // Total spent (use global total from spent map).
    final totalSpent = spentMap[null] ?? Decimal.zero;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total presupuestado',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmt(totalBudget),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 40, color: cs.outlineVariant),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total gastado',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fmt(totalSpent),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: totalSpent > totalBudget ? cs.error : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Decimal v) {
    // Simple COP format without importing AmountFormatter to keep this widget
    // self-contained; use the formatter's logic inline.
    final s = v.truncate().toBigInt().toString();
    final buf = StringBuffer('\$');
    buf.write(' ');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget card
// ---------------------------------------------------------------------------

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.budget,
    required this.spent,
    required this.categoryName,
    required this.onEdit,
    required this.onDelete,
  });

  final Budget budget;
  final Decimal spent;
  final String categoryName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    categoryName,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: onDelete,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            BudgetProgressBar(
              spent: spent,
              budget: budget.amount,
              warningPct: budget.alertThresholdWarning,
              criticalPct: budget.alertThresholdCritical,
            ),
            if (budget.notes != null && budget.notes!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                budget.notes!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget form sheet (create / edit)
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

  /// null means global (no category).
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
      // HTTP 409 = duplicate category budget.
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

    // Only expense categories (budgets are for expenses).
    final expenseCats =
        widget.categories.where((c) => c.categoryType == 'expense').toList()
          ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle.
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
            const SizedBox(height: 16),
            Text(
              widget.existing == null
                  ? 'Nuevo presupuesto'
                  : 'Editar presupuesto',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Global toggle.
            SwitchListTile(
              value: _isGlobal,
              onChanged: widget.existing != null
                  ? null // can't change global/category on edit
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

            // Category picker (only when not global).
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
                    ? null // can't change category on edit
                    : (v) => setState(() => _selectedCategoryId = v),
              ),
            ],
            const SizedBox(height: 12),

            // Amount.
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

            // Alert thresholds.
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

            // Notes.
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: 16),

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
