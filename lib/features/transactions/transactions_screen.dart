import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/amount_formatter.dart';
import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../core/sync_providers.dart';
import '../../core/theme.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
import '../../shared/category_avatar.dart';
import '../../shared/sync_status_icon.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns "Hoy", "Ayer", or "4 jul" for a YYYY-MM-DD string (es-CO).
String _formatDayHeader(String yyyyMmDd) {
  final dt = DateTime.parse(yyyyMmDd);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final day = DateTime(dt.year, dt.month, dt.day);

  const months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  if (day == today) return 'Hoy · ${dt.day} ${months[dt.month - 1]}';
  if (day == yesterday) return 'Ayer · ${dt.day} ${months[dt.month - 1]}';
  return '${dt.day} ${months[dt.month - 1]}';
}

/// Groups a list of transactions by their [transactionDate] (YYYY-MM-DD).
/// Resulting map is ordered newest date first (insertion order preserved).
Map<String, List<Transaction>> _groupByDay(List<Transaction> txs) {
  final map = <String, List<Transaction>>{};
  for (final tx in txs) {
    map.putIfAbsent(tx.transactionDate, () => []).add(tx);
  }
  return map;
}

const _txTypeLabels = {
  'expense': 'Gasto',
  'income': 'Ingreso',
  'transfer': 'Transferencia',
};

String _typeLabel(String type) => _txTypeLabels[type] ?? type;

String _categoryName(String? categoryId, List<Category> categories) {
  if (categoryId == null) return 'Sin categoría';
  try {
    return categories.firstWhere((c) => c.id == categoryId).name;
  } catch (_) {
    return 'Sin categoría';
  }
}

String _accountName(String accountId, List<Account> accounts) {
  try {
    return accounts.firstWhere((a) => a.id == accountId).name;
  } catch (_) {
    return 'Cuenta';
  }
}

// ---------------------------------------------------------------------------
// Filter type enum
// ---------------------------------------------------------------------------

enum _TxFilter { all, expense, income, transfer }

// ---------------------------------------------------------------------------
// TransactionsScreen
// ---------------------------------------------------------------------------

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  _TxFilter _filter = _TxFilter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // Offline-first: read from Drift (same source as Home) so locally saved
    // expenses — including ones still pending push — show up immediately.
    final txsAsync = ref.watch(localTransactionsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final accountsAsync = ref.watch(accountsForTransactionsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refresh(ref),
          child: CustomScrollView(
            slivers: [
              // ---- Big title + sync status pill ----
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BalviaTheme.spaceMd,
                    BalviaTheme.spaceLg,
                    BalviaTheme.spaceMd,
                    BalviaTheme.spaceSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transacciones',
                        style: BalviaTheme.headlineStyle(color: cs.onSurface),
                      ),
                      const SizedBox(height: BalviaTheme.spaceXs),
                      const SyncStatusIcon(compact: false),
                    ],
                  ),
                ),
              ),

              // ---- Filter chips row ----
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: BalviaTheme.spaceMd,
                    ),
                    children: _TxFilter.values.map((f) {
                      final label = switch (f) {
                        _TxFilter.all => 'Todos',
                        _TxFilter.expense => 'Gastos',
                        _TxFilter.income => 'Ingresos',
                        _TxFilter.transfer => 'Transferencias',
                      };
                      final selected = _filter == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: BalviaTheme.spaceSm),
                        child: GestureDetector(
                          onTap: () => setState(() => _filter = f),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? BalviaTheme.seed : Colors.transparent,
                              borderRadius: BorderRadius.circular(100),
                              border: Border.all(
                                color: selected
                                    ? BalviaTheme.seed
                                    : cs.outlineVariant,
                              ),
                            ),
                            child: Text(
                              label,
                              style: BalviaTheme.captionStyle(
                                color: selected ? Colors.white : cs.onSurfaceVariant,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: BalviaTheme.spaceMd)),

              // ---- Body ----
              txsAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => SliverFillRemaining(
                  child: _ErrorBody(message: apiErrorMessage(e)),
                ),
                data: (allTxs) {
                  final categories = categoriesAsync.value ?? const <Category>[];
                  final accounts = accountsAsync.value ?? const <Account>[];

                  // Apply filter.
                  final txs = _filter == _TxFilter.all
                      ? allTxs
                      : allTxs
                            .where(
                              (t) => t.transactionType == _filter.name,
                            )
                            .toList();

                  if (txs.isEmpty) {
                    return const SliverFillRemaining(child: _EmptyBody());
                  }

                  final grouped = _groupByDay(txs);
                  final dates = grouped.keys.toList();

                  return SliverList.builder(
                    itemCount: dates.length,
                    itemBuilder: (ctx, i) {
                      final date = dates[i];
                      final dayTxs = grouped[date]!;
                      return _DaySection(
                        date: date,
                        transactions: dayTxs,
                        categories: categories,
                        accounts: accounts,
                        onTap: (tx) => _openEditSheet(ctx, ref, tx, accounts),
                        onDelete: (tx) => _confirmDelete(ctx, ref, tx),
                      );
                    },
                  );
                },
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  void _refresh(WidgetRef ref) {
    ref.read(syncControllerProvider.notifier).syncInBackground();
    ref.invalidate(localTransactionsProvider);
    ref.invalidate(allTransactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(activeTrackingPeriodProvider);
    ref.invalidate(periodSummaryProvider);
  }

  void _openEditSheet(
    BuildContext context,
    WidgetRef ref,
    Transaction tx,
    List<Account> accounts,
  ) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _EditTransactionSheet(transaction: tx, accounts: accounts),
    ).then((saved) {
      if (saved == true) {
        _invalidateAfterMutation(ref);
      }
    });
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Transaction tx,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar movimiento'),
        content: Text(
          '¿Eliminar ${tx.description ?? _typeLabel(tx.transactionType)} '
          'por ${AmountFormatter.formatCOP(tx.amount)}? '
          'Esta acción revertirá el saldo de la cuenta.',
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
      await ref.read(transactionRepositoryProvider).delete(tx.id);
      _invalidateAfterMutation(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Movimiento eliminado'),
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

  void _invalidateAfterMutation(WidgetRef ref) {
    // Edits/deletes go through the network repo; pull the change back into
    // Drift so the local-first list reflects it.
    ref.read(syncControllerProvider.notifier).syncInBackground();
    ref.invalidate(localTransactionsProvider);
    ref.invalidate(allTransactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(activeTrackingPeriodProvider);
    ref.invalidate(periodSummaryProvider);
    ref.invalidate(accountsForTransactionsProvider);
  }
}

// ---------------------------------------------------------------------------
// Provider: accounts list for the Movimientos screen
// ---------------------------------------------------------------------------

final accountsForTransactionsProvider =
    FutureProvider.autoDispose<List<Account>>(
      (ref) => ref.watch(accountRepositoryProvider).list(),
    );

// ---------------------------------------------------------------------------
// Day section
// ---------------------------------------------------------------------------

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.date,
    required this.transactions,
    required this.categories,
    required this.accounts,
    required this.onTap,
    required this.onDelete,
  });

  final String date;
  final List<Transaction> transactions;
  final List<Category> categories;
  final List<Account> accounts;
  final void Function(Transaction) onTap;
  final void Function(Transaction) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Compute net for the day.
    Decimal dayNet = Decimal.zero;
    for (final tx in transactions) {
      if (tx.transactionType == 'income') {
        dayNet += tx.amount;
      } else if (tx.transactionType == 'expense') {
        dayNet -= tx.amount;
      }
    }
    final netColor =
        dayNet >= Decimal.zero ? BalviaTheme.income : BalviaTheme.expense;
    final netSign = dayNet >= Decimal.zero ? '+' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Day header: label left, net right.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            BalviaTheme.spaceMd,
            BalviaTheme.spaceSm,
            BalviaTheme.spaceMd,
            BalviaTheme.spaceXs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDayHeader(date),
                style: BalviaTheme.captionStyle(
                  color: cs.onSurfaceVariant,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '$netSign${AmountFormatter.formatCOP(dayNet)}',
                style: BalviaTheme.captionStyle(
                  color: netColor,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),

        // Transaction tiles with swipe-to-delete.
        ...transactions.map(
          (tx) => _SwipeableTransactionTile(
            tx: tx,
            categories: categories,
            accounts: accounts,
            onTap: () => onTap(tx),
            onDelete: () => onDelete(tx),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Swipeable tile
// ---------------------------------------------------------------------------

class _SwipeableTransactionTile extends StatelessWidget {
  const _SwipeableTransactionTile({
    required this.tx,
    required this.categories,
    required this.accounts,
    required this.onTap,
    required this.onDelete,
  });

  final Transaction tx;
  final List<Category> categories;
  final List<Account> accounts;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dismissible(
      key: Key('tx-${tx.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: cs.error,
        child: Icon(Icons.delete_outline, color: cs.onError),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: _TransactionTile(
        tx: tx,
        categories: categories,
        accounts: accounts,
        onTap: onTap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction tile (matches mockup 15 spec)
// ---------------------------------------------------------------------------

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.tx,
    required this.categories,
    required this.accounts,
    required this.onTap,
  });

  final Transaction tx;
  final List<Category> categories;
  final List<Account> accounts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final amountColor = BalviaTheme.colorForType(tx.transactionType);
    final sign = BalviaTheme.signForType(tx.transactionType);

    final category = tx.categoryId != null
        ? categories.where((c) => c.id == tx.categoryId).firstOrNull
        : null;

    final catName = _categoryName(tx.categoryId, categories);
    final accName = _accountName(tx.accountId, accounts);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BalviaTheme.spaceMd,
          vertical: BalviaTheme.spaceXs + 2,
        ),
        child: Row(
          children: [
            CategoryAvatar(category: category, radius: 20),
            const SizedBox(width: BalviaTheme.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.description ?? _typeLabel(tx.transactionType),
                    style: BalviaTheme.bodyStyle(
                      color: cs.onSurface,
                    ).copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$catName · $accName',
                    style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: BalviaTheme.spaceSm),
            Text(
              '$sign${AmountFormatter.formatCOP(tx.amount)}',
              style: BalviaTheme.bodyStyle(
                color: amountColor,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit transaction sheet (unchanged logic, visual polish only)
// ---------------------------------------------------------------------------

class _EditTransactionSheet extends ConsumerStatefulWidget {
  const _EditTransactionSheet({
    required this.transaction,
    required this.accounts,
  });

  final Transaction transaction;
  final List<Account> accounts;

  @override
  ConsumerState<_EditTransactionSheet> createState() =>
      _EditTransactionSheetState();
}

class _EditTransactionSheetState extends ConsumerState<_EditTransactionSheet> {
  late String _transactionType;
  late String _selectedAccountId;
  String? _selectedCategoryId;
  late TextEditingController _descController;
  late TextEditingController _notesController;
  late TextEditingController _amountController;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final tx = widget.transaction;
    _transactionType = tx.transactionType;
    _selectedAccountId = tx.accountId;
    _selectedCategoryId = tx.categoryId;
    _descController = TextEditingController(text: tx.description ?? '');
    _notesController = TextEditingController(text: tx.notes ?? '');
    _amountController = TextEditingController(
      text: tx.amount.truncate().toBigInt().toString(),
    );
  }

  @override
  void dispose() {
    _descController.dispose();
    _notesController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final rawAmount = _amountController.text.trim();
    if (rawAmount.isEmpty) {
      setState(() => _error = 'Ingresa un monto');
      return;
    }
    final amount = Decimal.tryParse(rawAmount);
    if (amount == null || amount <= Decimal.zero) {
      setState(() => _error = 'Monto inválido (debe ser mayor a cero)');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref
          .read(transactionRepositoryProvider)
          .update(
            widget.transaction.id,
            accountId: _selectedAccountId,
            transactionType: _transactionType,
            amount: amount,
            categoryId: _selectedCategoryId,
            description: _descController.text.trim().isEmpty
                ? null
                : _descController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            transactionDate: widget.transaction.transactionDate,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final categoriesAsync = ref.watch(categoriesProvider);

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
            const SizedBox(height: BalviaTheme.spaceMd),

            Text(
              'Editar movimiento',
              style: BalviaTheme.titleStyle(color: cs.onSurface),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            if (_transactionType != 'transfer') ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Gasto')),
                  ButtonSegment(value: 'income', label: Text('Ingreso')),
                ],
                selected: {_transactionType},
                onSelectionChanged: (s) =>
                    setState(() => _transactionType = s.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(height: 12),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 16,
                          color: cs.onSecondaryContainer),
                      const SizedBox(width: 6),
                      Text(
                        'Transferencia (tipo no editable)',
                        style: TextStyle(color: cs.onSecondaryContainer),
                      ),
                    ],
                  ),
                ),
              ),

            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: 'COP ',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),

            categoriesAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (all) {
                final filtered = all
                    .where(
                      (c) =>
                          c.categoryType == _transactionType &&
                          c.parentId == null,
                    )
                    .toList()
                  ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

                if (filtered.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Categoría',
                        style: BalviaTheme.captionStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 6),
                        itemBuilder: (ctx, i) {
                          final cat = filtered[i];
                          final selected = cat.id == _selectedCategoryId;
                          return GestureDetector(
                            onTap: () => setState(
                              () => _selectedCategoryId =
                                  selected ? null : cat.id,
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? cs.primaryContainer
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(20),
                                border: selected
                                    ? Border.all(
                                        color: cs.primary, width: 1.5)
                                    : null,
                              ),
                              child: Text(
                                cat.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: selected
                                      ? cs.onPrimaryContainer
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),

            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Cuenta',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: widget.accounts.length > 1
                  ? DropdownButton<String>(
                      value: _selectedAccountId,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: widget.accounts
                          .map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedAccountId = v);
                      },
                    )
                  : Text(
                      widget.accounts.isNotEmpty
                          ? widget.accounts.first.name
                          : 'Cuenta',
                    ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 1,
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: 12),

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
                  : const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / error bodies
// ---------------------------------------------------------------------------

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 72,
              color: cs.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),
            Text(
              'Sin transacciones',
              style: BalviaTheme.titleStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: BalviaTheme.spaceXs),
            Text(
              'Registra tu primer gasto con el botón + de abajo.',
              style: BalviaTheme.bodyStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

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
