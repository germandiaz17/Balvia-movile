import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/amount_formatter.dart';
import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import '../../data/models/transaction.dart';
import '../../shared/category_avatar.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Formats a YYYY-MM-DD string as "4 jul. 2026" (es-CO abbreviated).
String _formatDate(String yyyyMmDd) {
  final dt = DateTime.parse(yyyyMmDd);
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

/// Groups a list of transactions by their [transactionDate] (YYYY-MM-DD).
/// The resulting map is ordered newest date first.
Map<String, List<Transaction>> _groupByDay(List<Transaction> txs) {
  final map = <String, List<Transaction>>{};
  for (final tx in txs) {
    map.putIfAbsent(tx.transactionDate, () => []).add(tx);
  }
  // txs is already sorted newest-first; the insertion order is preserved.
  return map;
}

const _txTypeLabels = {
  'expense': 'Gasto',
  'income': 'Ingreso',
  'transfer': 'Transferencia',
};

String _typeLabel(String type) => _txTypeLabels[type] ?? type;

/// Returns the category name from [categories] by [categoryId], or a fallback.
String _categoryName(String? categoryId, List<Category> categories) {
  if (categoryId == null) return 'Sin categoría';
  try {
    return categories.firstWhere((c) => c.id == categoryId).name;
  } catch (_) {
    return 'Sin categoría';
  }
}

/// Returns the account name from [accounts] by [accountId], or a fallback.
String _accountName(String accountId, List<Account> accounts) {
  try {
    return accounts.firstWhere((a) => a.id == accountId).name;
  } catch (_) {
    return 'Cuenta';
  }
}

// ---------------------------------------------------------------------------
// TransactionsScreen
// ---------------------------------------------------------------------------

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txsAsync = ref.watch(allTransactionsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final accountsAsync = ref.watch(accountsForTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Movimientos'),
        actions: [
          // Access category management.
          IconButton(
            tooltip: 'Gestionar categorías',
            icon: const Icon(Icons.category_outlined),
            onPressed: () => context.push('/categories'),
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(ref),
        child: txsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorBody(message: apiErrorMessage(e)),
          data: (txs) {
            if (txs.isEmpty) {
              return const _EmptyBody();
            }

            final categories = categoriesAsync.value ?? const <Category>[];
            final accounts = accountsAsync.value ?? const <Account>[];
            final grouped = _groupByDay(txs);
            final dates = grouped.keys.toList();

            return ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 80),
              itemCount: dates.length,
              itemBuilder: (context, i) {
                final date = dates[i];
                final dayTxs = grouped[date]!;
                return _DaySection(
                  date: date,
                  transactions: dayTxs,
                  categories: categories,
                  accounts: accounts,
                  onTap: (tx) => _openEditSheet(context, ref, tx, accounts),
                  onDelete: (tx) => _confirmDelete(context, ref, tx),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _refresh(WidgetRef ref) {
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
    ref.invalidate(allTransactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(activeTrackingPeriodProvider);
    ref.invalidate(periodSummaryProvider);
    // Accounts balances change after any transaction mutation.
    ref.invalidate(accountsForTransactionsProvider);
  }
}

// ---------------------------------------------------------------------------
// Provider: accounts list for the Movimientos screen
// ---------------------------------------------------------------------------

/// Cached accounts list shared between the Movimientos tab and the edit sheet.
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
    final netColor = dayNet >= Decimal.zero
        ? BalviaTheme.income
        : BalviaTheme.expense;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Day header.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(date),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                AmountFormatter.formatCOP(dayNet),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: netColor,
                  fontWeight: FontWeight.bold,
                ),
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
        // Return false: the tile removal is handled by provider invalidation.
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
// Transaction tile
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

    final amountColor = BalviaTheme.colorForType(tx.transactionType);
    final sign = BalviaTheme.signForType(tx.transactionType);

    // Resolve category and account objects for CategoryAvatar.
    final category = tx.categoryId != null
        ? categories.where((c) => c.id == tx.categoryId).firstOrNull
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        onTap: onTap,
        leading: CategoryAvatar(category: category, radius: 18),
        title: Text(
          tx.description ?? _typeLabel(tx.transactionType),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_categoryName(tx.categoryId, categories)}  ·  '
          '${_accountName(tx.accountId, accounts)}',
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '$sign${AmountFormatter.formatCOP(tx.amount)}',
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
// Edit transaction sheet
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
    // Display amount without trailing .00 for COP integers.
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
              'Editar movimiento',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Type selector (expense / income only — transfers are read-only in
            // the edit flow to avoid the complexity of transfer_account_id).
            if (_transactionType != 'transfer') ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Gasto')),
                  ButtonSegment(value: 'income', label: Text('Ingreso')),
                ],
                selected: {_transactionType},
                onSelectionChanged: (s) =>
                    setState(() => _transactionType = s.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        size: 16,
                        color: cs.onSecondaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Transferencia (tipo no editable)',
                        style: TextStyle(color: cs.onSecondaryContainer),
                      ),
                    ],
                  ),
                ),
              ),

            // Amount.
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: 'COP ',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),

            // Category selector.
            categoriesAsync.when(
              loading: () => const Center(
                child: SizedBox(
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (e, s) => const SizedBox.shrink(),
              data: (all) {
                final filtered =
                    all
                        .where(
                          (c) =>
                              c.categoryType == _transactionType &&
                              c.parentId == null,
                        )
                        .toList()
                      ..sort(
                        (a, b) => a.displayOrder.compareTo(b.displayOrder),
                      );

                if (filtered.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Categoría', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 6),
                        itemBuilder: (ctx, i) {
                          final cat = filtered[i];
                          final selected = cat.id == _selectedCategoryId;
                          return GestureDetector(
                            onTap: () => setState(
                              () => _selectedCategoryId = selected
                                  ? null
                                  : cat.id,
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
                                    ? Border.all(color: cs.primary, width: 1.5)
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

            // Account selector.
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Cuenta',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
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
                        if (v != null) {
                          setState(() => _selectedAccountId = v);
                        }
                      },
                    )
                  : Text(
                      widget.accounts.isNotEmpty
                          ? widget.accounts.first.name
                          : 'Cuenta',
                    ),
            ),
            const SizedBox(height: 12),

            // Description.
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

            // Notes.
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Aún no hay movimientos en este periodo.\n'
          'Usa el botón + en Inicio para registrar uno.',
          textAlign: TextAlign.center,
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
