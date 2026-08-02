import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/amount_formatter.dart';
import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../core/sync_providers.dart';
import '../../core/theme.dart';
import '../../data/models/account.dart';
import '../../data/models/savings_goal.dart';
import '../../shared/empty_state.dart';
import '../../shared/goal_progress_bar.dart';

// ---------------------------------------------------------------------------
// Screen
//
// Goals are read from the network (savingsGoalsProvider), not from Drift: the
// tables exist locally and the pull fills them, but there is no DAO and
// /sync/push rejects anything that is not a transaction, so writes have to go
// over the wire anyway. Reading locally while writing remotely would show a
// stale list right after a mutation.
// ---------------------------------------------------------------------------

class SavingsGoalsScreen extends ConsumerWidget {
  const SavingsGoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(savingsGoalsProvider);
    final accounts =
        ref.watch(localAccountsProvider).value ?? const <Account>[];

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Metas de ahorro')),
      floatingActionButton: goalsAsync.hasValue && goalsAsync.value!.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showGoalForm(context, ref, accounts: accounts),
              icon: const Icon(Icons.add),
              label: const Text('Nueva meta'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(savingsGoalsProvider),
        child: goalsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorBody(message: apiErrorMessage(e)),
          data: (goals) => _buildList(context, ref, goals, accounts),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<SavingsGoal> goals,
    List<Account> accounts,
  ) {
    if (goals.isEmpty) {
      return EmptyState(
        icon: Icons.savings_outlined,
        title: 'Aún no tienes metas',
        subtitle:
            'Define cuánto quieres ahorrar y para cuándo.\n'
            'Registra abonos y mira tu progreso.',
        cta: 'Crear meta',
        onCta: () => _showGoalForm(context, ref, accounts: accounts),
      );
    }

    // Active goals first, then achieved, then paused/abandoned; inside each
    // group the closest target date leads.
    final sorted = List<SavingsGoal>.from(goals)
      ..sort((a, b) {
        final rank = _statusRank(a.status).compareTo(_statusRank(b.status));
        if (rank != 0) return rank;
        return a.targetDate.compareTo(b.targetDate);
      });

    var totalSaved = Decimal.zero;
    var totalTarget = Decimal.zero;
    for (final g in goals) {
      totalSaved += g.currentAmount;
      totalTarget += g.targetAmount;
    }
    final activeCount = goals.where((g) => g.status == 'active').length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        BalviaTheme.spaceMd,
        BalviaTheme.spaceMd,
        BalviaTheme.spaceMd,
        // Room for the FAB.
        BalviaTheme.space2xl + BalviaTheme.spaceXl,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: _StatChip(
                label: 'Ahorrado',
                amount: totalSaved,
                amountColor: BalviaTheme.income,
              ),
            ),
            const SizedBox(width: BalviaTheme.spaceSm),
            Expanded(
              child: _StatChip(
                label: 'Objetivo',
                amount: totalTarget,
                amountColor: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: BalviaTheme.spaceSm),
        Text(
          activeCount == 1 ? '1 meta activa' : '$activeCount metas activas',
          style: BalviaTheme.captionStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: BalviaTheme.spaceMd),
        for (final goal in sorted) ...[
          _GoalCard(
            goal: goal,
            onContribute: () => _showContributionSheet(context, ref, goal),
            onEdit: () =>
                _showGoalForm(context, ref, existing: goal, accounts: accounts),
            onDelete: () => _confirmDelete(context, ref, goal),
            onHistory: () => _showHistory(context, ref, goal),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),
        ],
      ],
    );
  }

  static int _statusRank(String status) => switch (status) {
    'active' => 0,
    'achieved' => 1,
    'paused' => 2,
    _ => 3,
  };

  // -------------------------------------------------------------------------
  // Create / edit
  // -------------------------------------------------------------------------

  void _showGoalForm(
    BuildContext context,
    WidgetRef ref, {
    SavingsGoal? existing,
    required List<Account> accounts,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GoalFormSheet(
        existing: existing,
        accounts: accounts,
        onSave:
            (
              name,
              targetAmount,
              startDate,
              targetDate,
              status,
              linkedAccountId,
              description,
            ) async {
              final repo = ref.read(savingsGoalRepositoryProvider);
              if (existing == null) {
                await repo.create(
                  name: name,
                  targetAmount: targetAmount,
                  startDate: startDate,
                  targetDate: targetDate,
                  description: description,
                  linkedAccountId: linkedAccountId,
                );
              } else {
                // PUT is a full replace, so every editable field travels, even
                // the ones the user left alone.
                await repo.update(
                  existing.id,
                  name: name,
                  targetAmount: targetAmount,
                  targetDate: targetDate,
                  status: status,
                  description: description,
                  icon: existing.icon,
                  color: existing.color,
                  linkedAccountId: linkedAccountId,
                );
              }
              ref.invalidate(savingsGoalsProvider);
            },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Contribution
  // -------------------------------------------------------------------------

  Future<void> _showContributionSheet(
    BuildContext context,
    WidgetRef ref,
    SavingsGoal goal,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContributionSheet(
        goal: goal,
        onSave: (amount, date, notes) async {
          final result = await ref
              .read(savingsGoalRepositoryProvider)
              .addContribution(
                goal.id,
                amount: amount,
                contributionDate: date,
                notes: notes,
              );
          ref.invalidate(savingsGoalsProvider);
          ref.invalidate(goalContributionsProvider(goal.id));

          // The response carries the refreshed goal, so we know whether this
          // contribution is the one that completed it.
          if (result.goal.isAchieved && !goal.isAchieved) {
            messenger.showSnackBar(
              SnackBar(
                content: Text('🎉 ¡Lograste tu meta "${result.goal.name}"!'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: BalviaTheme.income,
              ),
            );
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Abono registrado'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // History
  // -------------------------------------------------------------------------

  void _showHistory(BuildContext context, WidgetRef ref, SavingsGoal goal) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HistorySheet(goal: goal),
    );
  }

  // -------------------------------------------------------------------------
  // Delete
  // -------------------------------------------------------------------------

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SavingsGoal goal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar meta'),
        content: Text(
          '¿Eliminar "${goal.name}"? Se borrará también su historial de abonos. '
          'Esta acción no se puede deshacer.',
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

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref.read(savingsGoalRepositoryProvider).delete(goal.id);
      ref.invalidate(savingsGoalsProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Meta eliminada'),
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
// Stat chip (mirrors the budgets screen)
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
      padding: const EdgeInsets.all(BalviaTheme.spaceSm),
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
// Goal card
// ---------------------------------------------------------------------------

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.onContribute,
    required this.onEdit,
    required this.onDelete,
    required this.onHistory,
  });

  final SavingsGoal goal;
  final VoidCallback onContribute;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: goal.isAchieved
          ? BalviaTheme.income.withValues(alpha: 0.08)
          : cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        onTap: onHistory,
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
                      color: (goal.isAchieved ? BalviaTheme.income : cs.primary)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
                    ),
                    child: Icon(
                      goal.isAchieved
                          ? Icons.emoji_events_outlined
                          : Icons.savings_outlined,
                      size: 20,
                      color: goal.isAchieved ? BalviaTheme.income : cs.primary,
                    ),
                  ),
                  const SizedBox(width: BalviaTheme.spaceSm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.name,
                          style: BalviaTheme.bodyStyle(
                            color: cs.onSurface,
                          ).copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        _DeadlineLabel(goal: goal),
                      ],
                    ),
                  ),
                  if (goal.status != 'active')
                    _StatusBadge(status: goal.status),
                  PopupMenuButton<String>(
                    tooltip: 'Opciones',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) => switch (value) {
                      'contribute' => onContribute(),
                      'edit' => onEdit(),
                      'delete' => onDelete(),
                      _ => null,
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'contribute',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.add_circle_outline, size: 20),
                          title: Text('Abonar'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined, size: 20),
                          title: Text('Editar'),
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
              const SizedBox(height: BalviaTheme.spaceSm),
              GoalProgressBar(
                current: goal.currentAmount,
                target: goal.targetAmount,
              ),
              if (!goal.isAchieved) ...[
                const SizedBox(height: BalviaTheme.spaceXs),
                Text(
                  'Faltan ${AmountFormatter.formatCOP(goal.remainingAmount)}',
                  style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Faltan 45 días" / "Vencida hace 3 días" / "Lograda".
class _DeadlineLabel extends StatelessWidget {
  const _DeadlineLabel({required this.goal});

  final SavingsGoal goal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (goal.isAchieved) {
      return Text(
        'Lograda',
        style: BalviaTheme.captionStyle(color: BalviaTheme.income),
      );
    }

    final days = goal.daysRemaining;
    final (text, color) = switch (days) {
      < 0 => ('Vencida hace ${-days} ${_dayWord(-days)}', BalviaTheme.expense),
      0 => ('Vence hoy', BalviaTheme.budgetWarning),
      _ => ('Faltan $days ${_dayWord(days)}', cs.onSurfaceVariant),
    };

    return Text(text, style: BalviaTheme.captionStyle(color: color));
  }

  static String _dayWord(int n) => n == 1 ? 'día' : 'días';
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (status) {
      'achieved' => BalviaTheme.income,
      'paused' => BalviaTheme.budgetWarning,
      _ => cs.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        goalStatusLabel(status),
        style: BalviaTheme.captionStyle(
          color: color,
        ).copyWith(fontWeight: FontWeight.w700, fontSize: 10),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Goal form sheet (create / edit)
// ---------------------------------------------------------------------------

typedef _GoalSaveCallback =
    Future<void> Function(
      String name,
      Decimal targetAmount,
      DateTime startDate,
      DateTime targetDate,
      String status,
      String? linkedAccountId,
      String? description,
    );

class _GoalFormSheet extends StatefulWidget {
  const _GoalFormSheet({
    required this.accounts,
    required this.onSave,
    this.existing,
  });

  final SavingsGoal? existing;
  final List<Account> accounts;
  final _GoalSaveCallback onSave;

  @override
  State<_GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<_GoalFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _descriptionCtrl;

  late DateTime _startDate;
  late DateTime _targetDate;
  late String _status;
  String? _linkedAccountId;

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _nameCtrl = TextEditingController(text: g?.name ?? '');
    _amountCtrl = TextEditingController(
      text: g != null ? g.targetAmount.truncate().toBigInt().toString() : '',
    );
    _descriptionCtrl = TextEditingController(text: g?.description ?? '');
    final now = DateTime.now();
    _startDate = g?.startDate ?? DateTime(now.year, now.month, now.day);
    _targetDate = g?.targetDate ?? DateTime(now.year, now.month + 6, now.day);
    _status = g?.status ?? 'active';
    _linkedAccountId = g?.linkedAccountId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _targetDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _targetDate = picked;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'El nombre es requerido');
      return;
    }

    final amount = AmountFormatter.toDecimal(
      _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (amount == null) {
      setState(() => _error = 'El objetivo debe ser mayor a cero');
      return;
    }

    // Mirrors ErrInvalidGoalDates on the backend so the user finds out before
    // the round trip.
    if (!_targetDate.isAfter(_startDate)) {
      setState(
        () => _error = 'La fecha objetivo debe ser posterior a la de inicio',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await widget.onSave(
        name,
        amount,
        _startDate,
        _targetDate,
        _status,
        _linkedAccountId,
        _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
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
    final activeAccounts = widget.accounts
        .where((a) => !a.isArchived)
        .toList(growable: false);

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
            const _SheetHandle(),
            const SizedBox(height: BalviaTheme.spaceMd),
            Text(
              isEdit ? 'Editar meta' : 'Nueva meta',
              style: BalviaTheme.titleStyle(color: cs.onSurface),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
                hintText: 'Ej: Viaje a Cartagena',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Objetivo',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                hintText: 'Ej: 3000000',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Inicio',
                    date: _startDate,
                    // start_date is immutable server-side (goalUpdateRequest
                    // does not accept it), so we don't pretend otherwise.
                    onTap: isEdit ? null : () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Objetivo',
                    date: _targetDate,
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String?>(
              initialValue: _linkedAccountId,
              decoration: const InputDecoration(
                labelText: 'Cuenta vinculada (opcional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Sin vincular'),
                ),
                ...activeAccounts.map(
                  (a) => DropdownMenuItem<String?>(
                    value: a.id,
                    child: Text(a.name),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _linkedAccountId = v),
            ),
            const SizedBox(height: 12),

            if (isEdit) ...[
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                ),
                items: kGoalStatuses
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(goalStatusLabel(s)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: 12),
            ],

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
                  : Text(isEdit ? 'Guardar cambios' : 'Crear meta'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contribution sheet
// ---------------------------------------------------------------------------

typedef _ContributionSaveCallback =
    Future<void> Function(Decimal amount, DateTime? date, String? notes);

class _ContributionSheet extends StatefulWidget {
  const _ContributionSheet({required this.goal, required this.onSave});

  final SavingsGoal goal;
  final _ContributionSaveCallback onSave;

  @override
  State<_ContributionSheet> createState() => _ContributionSheetState();
}

class _ContributionSheetState extends State<_ContributionSheet> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  late DateTime _date;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = AmountFormatter.toDecimal(
      _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    if (amount == null) {
      setState(() => _error = 'El monto debe ser mayor a cero');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await widget.onSave(
        amount,
        _date,
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // A 422 "no active tracking period" lands here; apiErrorMessage surfaces
      // the backend's own wording.
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
            const _SheetHandle(),
            const SizedBox(height: BalviaTheme.spaceMd),
            Text(
              'Abonar a "${widget.goal.name}"',
              style: BalviaTheme.titleStyle(color: cs.onSurface),
            ),
            const SizedBox(height: BalviaTheme.spaceXs),
            Text(
              'Faltan ${AmountFormatter.formatCOP(widget.goal.remainingAmount)}',
              style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Monto del abono',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),

            _DateField(
              label: 'Fecha',
              date: _date,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _notesCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
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
                  : const Text('Registrar abono'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contribution history sheet
// ---------------------------------------------------------------------------

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.goal});

  final SavingsGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final contributionsAsync = ref.watch(goalContributionsProvider(goal.id));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(BalviaTheme.radiusXl),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        BalviaTheme.spaceMd,
        BalviaTheme.spaceMd,
        BalviaTheme.spaceMd,
        BalviaTheme.spaceLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SheetHandle(),
          const SizedBox(height: BalviaTheme.spaceMd),
          Text(goal.name, style: BalviaTheme.titleStyle(color: cs.onSurface)),
          const SizedBox(height: BalviaTheme.spaceSm),
          GoalProgressBar(
            current: goal.currentAmount,
            target: goal.targetAmount,
          ),
          const SizedBox(height: BalviaTheme.spaceMd),
          Text(
            'ABONOS',
            style: BalviaTheme.overlineStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),
          Flexible(
            child: contributionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BalviaTheme.spaceLg),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  Text(apiErrorMessage(e), style: TextStyle(color: cs.error)),
              data: (contributions) {
                if (contributions.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: BalviaTheme.spaceLg,
                    ),
                    child: Text(
                      'Todavía no has abonado a esta meta.',
                      style: BalviaTheme.bodyStyle(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final sorted = List<GoalContribution>.from(contributions)
                  ..sort(
                    (a, b) => b.contributionDate.compareTo(a.contributionDate),
                  );
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: sorted.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = sorted[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(
                        Icons.arrow_upward,
                        size: 18,
                        color: BalviaTheme.income,
                      ),
                      title: Text(AmountFormatter.formatCOP(c.amount)),
                      subtitle: Text(
                        c.notes ?? formatDateOnly(c.contributionDate),
                      ),
                      trailing: c.notes == null
                          ? null
                          : Text(
                              formatDateOnly(c.contributionDate),
                              style: BalviaTheme.captionStyle(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared pieces
// ---------------------------------------------------------------------------

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// Read-only text field that opens a date picker. A null [onTap] renders it
/// disabled.
class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.date, this.onTap});

  final String label;
  final DateTime date;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          enabled: onTap != null,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(formatDateOnly(date)),
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
