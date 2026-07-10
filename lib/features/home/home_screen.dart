import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../data/models/account.dart';
import '../auth/auth_controller.dart';
import '../transactions/quick_capture_modal.dart';

// Dashboard providers are invalidated here so the summary refreshes
// immediately after a quick-capture save, even before the user navigates
// to the Dashboard tab.
// Providers: activeTrackingPeriodProvider, periodSummaryProvider,
//            recentTransactionsProvider (all imported via core/providers.dart).

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
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      floatingActionButton: accounts.maybeWhen(
        data: (items) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Secondary: add account (small FAB).
            FloatingActionButton.small(
              heroTag: 'fab_add_account',
              tooltip: 'Nueva cuenta',
              onPressed: () => _showAddAccount(context, ref),
              child: const Icon(Icons.account_balance_wallet_outlined),
            ),
            const SizedBox(height: 12),
            // Primary: quick expense capture (large, prominent).
            FloatingActionButton.extended(
              heroTag: 'fab_quick_capture',
              onPressed: () async {
                final saved = await showQuickCaptureModal(
                  context,
                  ref,
                  accounts: items,
                );
                if (saved && context.mounted) {
                  ref.invalidate(accountsProvider);
                  // Dashboard providers must refresh: a new transaction
                  // changes the period summary and recent list.
                  ref.invalidate(activeTrackingPeriodProvider);
                  ref.invalidate(periodSummaryProvider);
                  ref.invalidate(recentTransactionsProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gasto registrado'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Gasto'),
            ),
          ],
        ),
        orElse: () => FloatingActionButton.extended(
          heroTag: 'fab_add_account_fallback',
          onPressed: () => _showAddAccount(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('Cuenta'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(accountsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Hola${user?.fullName != null ? ', ${user!.fullName}' : ''} 👋',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (user != null)
              Text(user.email, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 24),
            Text('Tus cuentas', style: Theme.of(context).textTheme.titleMedium),
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
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Aún no tienes cuentas. Crea la primera con el botón +.',
                      ),
                    )
                  : Column(children: items.map(_AccountTile.new).toList()),
            ),
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
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet)),
        title: Text(account.name),
        subtitle: Text(_typeLabel(account.accountType)),
        trailing: Text(
          '${account.currency} ${account.currentBalance.toStringAsFixed(2)}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
              decoration: const InputDecoration(labelText: 'Saldo inicial'),
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
