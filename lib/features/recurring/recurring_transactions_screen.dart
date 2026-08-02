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
import '../../data/models/recurring_transaction.dart';
import '../../data/models/savings_goal.dart' show formatDateOnly;
import '../../shared/empty_state.dart';

// ---------------------------------------------------------------------------
// Screen
//
// Loading this list makes the backend run the materialisation engine, so any
// overdue template becomes a real transaction right here. We kick off a sync
// once the list arrives so those transactions land in Drift and appear in
// Movimientos and Inicio instead of showing up out of nowhere later.
// ---------------------------------------------------------------------------

class RecurringTransactionsScreen extends ConsumerStatefulWidget {
  const RecurringTransactionsScreen({super.key});

  @override
  ConsumerState<RecurringTransactionsScreen> createState() =>
      _RecurringTransactionsScreenState();
}

class _RecurringTransactionsScreenState
    extends ConsumerState<RecurringTransactionsScreen> {
  @override
  Widget build(BuildContext context) {
    final recurringAsync = ref.watch(recurringTransactionsProvider);
    final accounts =
        ref.watch(localAccountsProvider).value ?? const <Account>[];
    final categories =
        ref.watch(localCategoriesProvider).value ?? const <Category>[];

    // Pull down whatever the engine just materialised.
    ref.listen(recurringTransactionsProvider, (_, next) {
      if (next.hasValue) {
        ref.read(syncControllerProvider.notifier).syncInBackground();
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Recurrentes')),
      floatingActionButton:
          recurringAsync.hasValue && recurringAsync.value!.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () =>
                  _showForm(accounts: accounts, categories: categories),
              icon: const Icon(Icons.add),
              label: const Text('Nueva'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recurringTransactionsProvider),
        child: recurringAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorBody(message: apiErrorMessage(e)),
          data: (items) => _buildList(items, accounts, categories),
        ),
      ),
    );
  }

  Widget _buildList(
    List<RecurringTransaction> items,
    List<Account> accounts,
    List<Category> categories,
  ) {
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.repeat_outlined,
        title: 'Sin transacciones recurrentes',
        subtitle:
            'Automatiza tu arriendo, tus suscripciones o tu nómina.\n'
            'Balvia las registra por ti en la fecha programada.',
        cta: 'Crear recurrente',
        onCta: () => _showForm(accounts: accounts, categories: categories),
      );
    }

    final live = items.where((r) => r.isActive && !r.isFinished).toList()
      ..sort((a, b) => a.nextDueDate!.compareTo(b.nextDueDate!));
    final idle = items.where((r) => !r.isActive || r.isFinished).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        BalviaTheme.spaceMd,
        BalviaTheme.spaceMd,
        BalviaTheme.spaceMd,
        BalviaTheme.space2xl + BalviaTheme.spaceXl,
      ),
      children: [
        const _InfoBanner(
          text:
              'Balvia registra estos movimientos automáticamente en la fecha '
              'programada. Al editar una recurrente, la próxima fecha se '
              'recalcula desde la fecha de inicio.',
        ),
        const SizedBox(height: BalviaTheme.spaceMd),
        if (live.isNotEmpty) ...[
          Text(
            'ACTIVAS',
            style: BalviaTheme.overlineStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),
          for (final item in live) ...[
            _RecurringCard(
              item: item,
              accountName: _accountName(accounts, item.accountId),
              onEdit: () => _showForm(
                existing: item,
                accounts: accounts,
                categories: categories,
              ),
              onToggle: () => _toggleActive(item),
              onDelete: () => _confirmDelete(item),
            ),
            const SizedBox(height: BalviaTheme.spaceSm),
          ],
        ],
        if (idle.isNotEmpty) ...[
          const SizedBox(height: BalviaTheme.spaceSm),
          Text(
            'PAUSADAS Y FINALIZADAS',
            style: BalviaTheme.overlineStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),
          for (final item in idle) ...[
            _RecurringCard(
              item: item,
              accountName: _accountName(accounts, item.accountId),
              onEdit: () => _showForm(
                existing: item,
                accounts: accounts,
                categories: categories,
              ),
              onToggle: item.isFinished ? null : () => _toggleActive(item),
              onDelete: () => _confirmDelete(item),
            ),
            const SizedBox(height: BalviaTheme.spaceSm),
          ],
        ],
      ],
    );
  }

  static String? _accountName(List<Account> accounts, String accountId) {
    for (final a in accounts) {
      if (a.id == accountId) return a.name;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Actions
  // -------------------------------------------------------------------------

  void _showForm({
    RecurringTransaction? existing,
    required List<Account> accounts,
    required List<Category> categories,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecurringFormSheet(
        existing: existing,
        accounts: accounts,
        categories: categories,
        onSave: (draft) async {
          final repo = ref.read(recurringTransactionRepositoryProvider);
          if (existing == null) {
            await repo.create(
              accountId: draft.accountId,
              name: draft.name,
              transactionType: draft.transactionType,
              amount: draft.amount,
              frequency: draft.frequency,
              startDate: draft.startDate,
              categoryId: draft.categoryId,
              description: draft.description,
              customIntervalDays: draft.customIntervalDays,
              dayOfMonth: draft.dayOfMonth,
              dayOfWeek: draft.dayOfWeek,
              endDate: draft.endDate,
              isActive: draft.isActive,
            );
          } else {
            await repo.update(
              existing.id,
              accountId: draft.accountId,
              name: draft.name,
              transactionType: draft.transactionType,
              amount: draft.amount,
              frequency: draft.frequency,
              startDate: draft.startDate,
              categoryId: draft.categoryId,
              description: draft.description,
              customIntervalDays: draft.customIntervalDays,
              dayOfMonth: draft.dayOfMonth,
              dayOfWeek: draft.dayOfWeek,
              endDate: draft.endDate,
              isActive: draft.isActive,
            );
          }
          ref.invalidate(recurringTransactionsProvider);
        },
      ),
    );
  }

  Future<void> _toggleActive(RecurringTransaction item) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      // The PUT is a full replace, so every field travels back unchanged except
      // is_active.
      await ref
          .read(recurringTransactionRepositoryProvider)
          .update(
            item.id,
            accountId: item.accountId,
            name: item.name,
            transactionType: item.transactionType,
            amount: item.amount,
            frequency: item.frequency,
            startDate: item.startDate,
            categoryId: item.categoryId,
            description: item.description,
            currency: item.currency,
            customIntervalDays: item.customIntervalDays,
            dayOfMonth: item.dayOfMonth,
            dayOfWeek: item.dayOfWeek,
            endDate: item.endDate,
            isActive: !item.isActive,
          );
      ref.invalidate(recurringTransactionsProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            item.isActive ? 'Recurrente pausada' : 'Recurrente reactivada',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(apiErrorMessage(e)),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmDelete(RecurringTransaction item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar recurrente'),
        content: Text(
          '¿Eliminar "${item.name}"? Los movimientos ya registrados se '
          'conservan; solo se deja de generar nuevos.',
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
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref.read(recurringTransactionRepositoryProvider).delete(item.id);
      ref.invalidate(recurringTransactionsProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Recurrente eliminada'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(apiErrorMessage(e)),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Card
// ---------------------------------------------------------------------------

class _RecurringCard extends StatelessWidget {
  const _RecurringCard({
    required this.item,
    required this.accountName,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final RecurringTransaction item;
  final String? accountName;
  final VoidCallback onEdit;

  /// Null for finished templates — there is nothing left to resume.
  final VoidCallback? onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amountColor = item.isExpense
        ? BalviaTheme.expense
        : BalviaTheme.income;
    final dimmed = !item.isActive || item.isFinished;

    return Opacity(
      opacity: dimmed ? 0.65 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        color: cs.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(BalviaTheme.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: amountColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
                    ),
                    child: Icon(
                      item.isExpense
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      size: 20,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(width: BalviaTheme.spaceSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: BalviaTheme.bodyStyle(
                            color: cs.onSurface,
                          ).copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          item.nextDueLabel,
                          style: BalviaTheme.captionStyle(
                            color: item.isFinished || !item.isActive
                                ? cs.onSurfaceVariant
                                : cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    AmountFormatter.formatCOP(item.amount),
                    style: BalviaTheme.bodyStyle(
                      color: amountColor,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) => switch (value) {
                      'edit' => onEdit(),
                      'toggle' => onToggle?.call(),
                      'delete' => onDelete(),
                      _ => null,
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined, size: 20),
                          title: Text('Editar'),
                        ),
                      ),
                      if (onToggle != null)
                        PopupMenuItem(
                          value: 'toggle',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              item.isActive
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 20,
                            ),
                            title: Text(item.isActive ? 'Pausar' : 'Reactivar'),
                          ),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: cs.error,
                          ),
                          title: Text(
                            'Eliminar',
                            style: TextStyle(color: cs.error),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: BalviaTheme.spaceXs),
              Row(
                children: [
                  _Chip(label: item.scheduleLabel),
                  if (accountName != null) ...[
                    const SizedBox(width: BalviaTheme.spaceXs),
                    Flexible(child: _Chip(label: accountName!)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

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
// Form sheet
// ---------------------------------------------------------------------------

/// Everything the form collects, so the callback signature stays readable.
class RecurringDraft {
  const RecurringDraft({
    required this.accountId,
    required this.name,
    required this.transactionType,
    required this.amount,
    required this.frequency,
    required this.startDate,
    required this.isActive,
    this.categoryId,
    this.description,
    this.customIntervalDays,
    this.dayOfMonth,
    this.dayOfWeek,
    this.endDate,
  });

  final String accountId;
  final String name;
  final String transactionType;
  final Decimal amount;
  final String frequency;
  final DateTime startDate;
  final bool isActive;
  final String? categoryId;
  final String? description;
  final int? customIntervalDays;
  final int? dayOfMonth;
  final int? dayOfWeek;
  final DateTime? endDate;
}

typedef _RecurringSaveCallback = Future<void> Function(RecurringDraft draft);

class _RecurringFormSheet extends StatefulWidget {
  const _RecurringFormSheet({
    required this.accounts,
    required this.categories,
    required this.onSave,
    this.existing,
  });

  final RecurringTransaction? existing;
  final List<Account> accounts;
  final List<Category> categories;
  final _RecurringSaveCallback onSave;

  @override
  State<_RecurringFormSheet> createState() => _RecurringFormSheetState();
}

class _RecurringFormSheetState extends State<_RecurringFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _intervalCtrl;
  late final TextEditingController _descriptionCtrl;

  late String _transactionType;
  late String _frequency;
  late DateTime _startDate;
  DateTime? _endDate;
  String? _accountId;
  String? _categoryId;
  int? _dayOfMonth;
  int? _dayOfWeek;
  late bool _isActive;

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _amountCtrl = TextEditingController(
      text: r != null ? r.amount.truncate().toBigInt().toString() : '',
    );
    _intervalCtrl = TextEditingController(
      text: r?.customIntervalDays?.toString() ?? '',
    );
    _descriptionCtrl = TextEditingController(text: r?.description ?? '');

    _transactionType = r?.transactionType ?? 'expense';
    _frequency = r?.frequency ?? 'monthly';
    final now = DateTime.now();
    _startDate = r?.startDate ?? DateTime(now.year, now.month, now.day);
    _endDate = r?.endDate;
    _accountId =
        r?.accountId ??
        (widget.accounts.isNotEmpty ? widget.accounts.first.id : null);
    _categoryId = r?.categoryId;
    _dayOfMonth = r?.dayOfMonth ?? _startDate.day;
    _dayOfWeek = r?.dayOfWeek ?? _startDate.weekday % 7; // DateTime: Sun == 7
    _isActive = r?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _intervalCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = AmountFormatter.toDecimal(
      _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    final interval = int.tryParse(_intervalCtrl.text.trim());

    final error = validateRecurringForm(
      name: _nameCtrl.text,
      accountId: _accountId,
      transactionType: _transactionType,
      amount: amount,
      frequency: _frequency,
      customIntervalDays: _frequency == 'custom' ? interval : null,
      dayOfMonth: _frequency == 'monthly' ? _dayOfMonth : null,
      dayOfWeek: (_frequency == 'weekly' || _frequency == 'biweekly')
          ? _dayOfWeek
          : null,
      startDate: _startDate,
      endDate: _endDate,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await widget.onSave(
        RecurringDraft(
          accountId: _accountId!,
          name: _nameCtrl.text.trim(),
          transactionType: _transactionType,
          amount: amount!,
          frequency: _frequency,
          startDate: _startDate,
          isActive: _isActive,
          categoryId: _categoryId,
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          customIntervalDays: interval,
          dayOfMonth: _dayOfMonth,
          dayOfWeek: _dayOfWeek,
          endDate: _endDate,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      final msg = apiErrorMessage(e);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = msg;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEdit = widget.existing != null;
    final activeAccounts = widget.accounts.where((a) => !a.isArchived).toList();
    final matchingCategories =
        widget.categories
            .where((c) => c.categoryType == _transactionType)
            .toList()
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
              isEdit ? 'Editar recurrente' : 'Nueva recurrente',
              style: BalviaTheme.titleStyle(color: cs.onSurface),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            // Type — transfer is not supported for templates.
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Gasto')),
                ButtonSegment(value: 'income', label: Text('Ingreso')),
              ],
              selected: {_transactionType},
              onSelectionChanged: (s) => setState(() {
                _transactionType = s.first;
                _categoryId = null; // categories are type-specific
                _error = null;
              }),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
                hintText: 'Ej: Arriendo',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: const InputDecoration(
                labelText: 'Cuenta',
                border: OutlineInputBorder(),
              ),
              items: activeAccounts
                  .map(
                    (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _accountId = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Categoría (opcional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sin categoría'),
                ),
                ...matchingCategories.map(
                  (c) => DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(c.name),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              initialValue: _frequency,
              decoration: const InputDecoration(
                labelText: 'Frecuencia',
                border: OutlineInputBorder(),
              ),
              items: kRecurringFrequencies
                  .map(
                    (f) => DropdownMenuItem(
                      value: f,
                      child: Text(frequencyLabel(f)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                _frequency = v ?? _frequency;
                _error = null;
              }),
            ),

            // Frequency-specific hint. daily and yearly need none.
            if (_frequency == 'monthly') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _dayOfMonth,
                decoration: const InputDecoration(
                  labelText: 'Día del mes',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (var d = 1; d <= 31; d++)
                    DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (v) => setState(() => _dayOfMonth = v),
              ),
            ],
            if (_frequency == 'weekly' || _frequency == 'biweekly') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _dayOfWeek,
                decoration: const InputDecoration(
                  labelText: 'Día de la semana',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (var d = 0; d <= 6; d++)
                    DropdownMenuItem(value: d, child: Text(dayOfWeekLabel(d))),
                ],
                onChanged: (v) => setState(() => _dayOfWeek = v),
              ),
            ],
            if (_frequency == 'custom') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _intervalCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Cada cuántos días',
                  border: OutlineInputBorder(),
                  hintText: 'Ej: 10',
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
            ],
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Inicio',
                    text: formatDateOnly(_startDate),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          _startDate = picked;
                          _error = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Fin (opcional)',
                    text: _endDate == null ? '—' : formatDateOnly(_endDate!),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            _endDate ??
                            _startDate.add(const Duration(days: 365)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          _endDate = picked;
                          _error = null;
                        });
                      }
                    },
                    onClear: _endDate == null
                        ? null
                        : () => setState(() => _endDate = null),
                  ),
                ),
              ],
            ),

            if (isEdit && widget.existing!.nextDueDate != null) ...[
              const SizedBox(height: 12),
              // Read-only: the engine owns this value.
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Próxima ejecución',
                  border: OutlineInputBorder(),
                  enabled: false,
                  helperText: 'La calcula Balvia; se recalcula al guardar',
                ),
                child: Text(formatDateOnly(widget.existing!.nextDueDate!)),
              ),
            ],
            const SizedBox(height: 12),

            SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('Activa'),
              subtitle: const Text('Si la pausas, deja de generar movimientos'),
              contentPadding: EdgeInsets.zero,
            ),

            TextField(
              controller: _descriptionCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                border: OutlineInputBorder(),
              ),
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
                  : Text(isEdit ? 'Guardar cambios' : 'Crear recurrente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.text,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final String text;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: onClear == null
              ? const Icon(Icons.calendar_today_outlined, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: onClear,
                  tooltip: 'Quitar fecha de fin',
                ),
        ),
        child: Text(text),
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
    return ListView(
      children: [
        Card(
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
      ],
    );
  }
}
