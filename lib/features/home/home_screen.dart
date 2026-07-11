import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/amount_formatter.dart';
import '../../core/providers.dart';
import '../../data/models/account.dart';
import '../../shared/sync_status_icon.dart';
import '../auth/auth_controller.dart';

/// Loads the user's accounts. autoDispose so it refetches when revisited.
final accountsProvider = FutureProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).list(),
);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final accounts = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balvia'),
        actions: [
          // Sync status indicator — shows nube/pending/offline.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: SyncStatusIcon(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'fab_add_account_home',
        tooltip: 'Nueva cuenta',
        onPressed: () => _showAddAccount(context, ref),
        child: const Icon(Icons.account_balance_wallet_outlined),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(accountsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Greeting.
            Text(
              'Hola${user?.fullName != null ? ', ${user!.fullName}' : ''} 👋',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (user != null)
              Text(user.email, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Tus cuentas',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                accounts.maybeWhen(
                  data: (items) {
                    if (items.isEmpty) return const SizedBox.shrink();
                    // Consolidated total.
                    final total = items.fold(
                      Decimal.zero,
                      (sum, a) => sum + a.currentBalance,
                    );
                    return Text(
                      AmountFormatter.formatCOP(total),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            accounts.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(apiErrorMessage(e)),
                ),
              ),
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          const Text(
                            'Aún no tienes cuentas. Crea la primera con el botón +.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _showAddAccount(context, ref),
                            icon: const Icon(Icons.add),
                            label: const Text('Nueva cuenta'),
                          ),
                        ],
                      ),
                    )
                  : Column(children: items.map(_AccountTile.new).toList()),
            ),
            const SizedBox(height: 80), // padding for the FAB
          ],
        ),
      ),
    );
  }

  void _showAddAccount(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => const _AddAccountDialog(),
    ).then((_) => ref.invalidate(accountsProvider));
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile(this.account);
  final Account account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isNegative =
        account.currentBalance < Decimal.zero;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(
            _accountIcon(account.accountType),
            color: cs.onPrimaryContainer,
            size: 20,
          ),
        ),
        title: Text(account.name),
        subtitle: Text(_typeLabel(account.accountType)),
        trailing: Text(
          AmountFormatter.formatCOP(account.currentBalance),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: isNegative ? cs.error : cs.onSurface,
          ),
        ),
      ),
    );
  }
}

const _accountTypes = {
  'cash': 'Efectivo',
  'checking': 'Cuenta corriente',
  'savings': 'Ahorros',
  'credit_card': 'Tarjeta de crédito',
  'investment': 'Inversión',
  'other': 'Otra',
};

String _typeLabel(String type) => _accountTypes[type] ?? type;

IconData _accountIcon(String type) => switch (type) {
  'cash' => Icons.payments_outlined,
  'checking' => Icons.account_balance_outlined,
  'savings' => Icons.savings_outlined,
  'credit_card' => Icons.credit_card_outlined,
  'investment' => Icons.trending_up_outlined,
  _ => Icons.account_balance_wallet_outlined,
};

class _AddAccountDialog extends ConsumerStatefulWidget {
  const _AddAccountDialog();
  @override
  ConsumerState<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends ConsumerState<_AddAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _balance = TextEditingController(text: '0');
  String _type = 'cash';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .create(
            name: _name.text.trim(),
            accountType: _type,
            initialBalance: _balance.text.trim(),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva cuenta'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: _accountTypes.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? 'cash'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _balance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Saldo inicial',
                helperText: 'El saldo solo cambia con transacciones después.',
              ),
              validator: (v) => (v == null || double.tryParse(v) == null)
                  ? 'Número inválido'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }
}
