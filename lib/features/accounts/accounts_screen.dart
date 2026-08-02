import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/amount_formatter.dart';
import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models/account.dart';

// ---------------------------------------------------------------------------
// Provider: accounts list
// ---------------------------------------------------------------------------

final accountsProvider = FutureProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).list(),
);

// ---------------------------------------------------------------------------
// AccountsScreen
// ---------------------------------------------------------------------------

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Cuentas'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(accountsProvider),
        child: accountsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorBody(message: apiErrorMessage(e)),
          data: (accounts) => _AccountsBody(
            accounts: accounts,
            onRefresh: () => ref.invalidate(accountsProvider),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body: total card + account list + add button + create form
// ---------------------------------------------------------------------------

class _AccountsBody extends ConsumerStatefulWidget {
  const _AccountsBody({required this.accounts, required this.onRefresh});

  final List<Account> accounts;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_AccountsBody> createState() => _AccountsBodyState();
}

class _AccountsBodyState extends ConsumerState<_AccountsBody> {
  bool _showForm = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = widget.accounts.where((a) => !a.isArchived).toList();

    // Total consolidado = sum of current_balance across all active accounts.
    Decimal total = Decimal.zero;
    for (final a in active) {
      total += a.currentBalance;
    }

    // Month/year label for the card caption.
    final now = DateTime.now();
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
    final periodLabel = '${months[now.month - 1]} ${now.year}';

    return CustomScrollView(
      slivers: [
        // ---- Total consolidado card (teal) ----
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              BalviaTheme.spaceMd,
              BalviaTheme.spaceSm,
              BalviaTheme.spaceMd,
              BalviaTheme.spaceMd,
            ),
            child: _TotalCard(
              total: total,
              activeCount: active.length,
              periodLabel: periodLabel,
            ),
          ),
        ),

        // ---- "MIS CUENTAS" overline ----
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              BalviaTheme.spaceMd,
              0,
              BalviaTheme.spaceMd,
              BalviaTheme.spaceSm,
            ),
            child: Text(
              'MIS CUENTAS',
              style: BalviaTheme.overlineStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ),

        // ---- Account tiles ----
        if (active.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: BalviaTheme.spaceMd,
                vertical: BalviaTheme.spaceSm,
              ),
              child: _EmptyAccountsHint(),
            ),
          )
        else
          SliverList.builder(
            itemCount: active.length,
            itemBuilder: (_, i) => _AccountTile(
              account: active[i],
              onEdit: () => _openEditSheet(context, active[i]),
              onDelete: () => _confirmDelete(context, active[i]),
            ),
          ),

        // ---- "Agregar cuenta" dashed button ----
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              BalviaTheme.spaceMd,
              BalviaTheme.spaceSm,
              BalviaTheme.spaceMd,
              BalviaTheme.spaceMd,
            ),
            child: _DashedAddButton(
              label: 'Agregar cuenta',
              onTap: () => setState(() => _showForm = !_showForm),
            ),
          ),
        ),

        // ---- Inline create form ----
        if (_showForm)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                BalviaTheme.spaceMd,
                0,
                BalviaTheme.spaceMd,
                BalviaTheme.spaceMd,
              ),
              child: _CreateAccountForm(
                onSaved: () {
                  setState(() => _showForm = false);
                  widget.onRefresh();
                },
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  void _openEditSheet(BuildContext context, Account account) {
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditAccountSheet(account: account),
    ).then((saved) {
      if (saved == true) widget.onRefresh();
    });
  }

  Future<void> _confirmDelete(BuildContext context, Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cuenta'),
        content: Text(
          '¿Eliminar "${account.name}"? Esta acción no se puede deshacer. '
          'Las transacciones existentes quedarán huérfanas.',
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
      await ref.read(accountRepositoryProvider).delete(account.id);
      widget.onRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cuenta eliminada'),
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
// Total card
// ---------------------------------------------------------------------------

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.total,
    required this.activeCount,
    required this.periodLabel,
  });

  final Decimal total;
  final int activeCount;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BalviaTheme.spaceMd),
      decoration: BoxDecoration(
        color: BalviaTheme.seed,
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total consolidado',
            style: BalviaTheme.captionStyle(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: BalviaTheme.spaceXs),
          Text(
            AmountFormatter.formatCOP(total),
            style: BalviaTheme.displayStyle(color: Colors.white),
          ),
          const SizedBox(height: BalviaTheme.spaceXs),
          Text(
            '$activeCount ${activeCount == 1 ? 'cuenta activa' : 'cuentas activas'} · $periodLabel',
            style: BalviaTheme.captionStyle(
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account tile
// ---------------------------------------------------------------------------

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.onEdit,
    required this.onDelete,
  });

  final Account account;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color iconBg;
    final Color iconColor;
    final IconData icon;

    // Resolve color: use account.color (#RRGGBB) if set, else type-based pastel.
    if (account.color != null) {
      final hex = account.color!.replaceFirst('#', '');
      final value = hex.length == 6 ? int.tryParse('FF$hex', radix: 16) : null;
      final parsed = value != null
          ? Color(value)
          : _typeColor(account.accountType);
      iconBg = parsed.withValues(alpha: 0.15);
      iconColor = parsed;
    } else {
      iconColor = _typeColor(account.accountType);
      iconBg = iconColor.withValues(alpha: 0.15);
    }
    icon = _typeIcon(account.accountType);

    final isNegative = account.currentBalance < Decimal.zero;
    final balanceColor = isNegative ? BalviaTheme.expense : BalviaTheme.income;

    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BalviaTheme.spaceMd,
          vertical: BalviaTheme.spaceSm + 2,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: BalviaTheme.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: BalviaTheme.bodyStyle(
                      color: cs.onSurface,
                    ).copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _typeLabel(account.accountType),
                    style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: BalviaTheme.spaceSm),
            Text(
              AmountFormatter.formatCOP(account.currentBalance),
              style: BalviaTheme.bodyStyle(
                color: balanceColor,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: cs.onSurfaceVariant),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Type helpers
// ---------------------------------------------------------------------------

String _typeLabel(String type) => switch (type) {
  'cash' => 'Efectivo',
  'checking' => 'Cuenta corriente',
  'savings' => 'Cuenta de ahorros',
  'credit_card' => 'Tarjeta de crédito',
  'investment' => 'Inversión',
  _ => 'Otra',
};

IconData _typeIcon(String type) => switch (type) {
  'cash' => Icons.attach_money,
  'checking' => Icons.account_balance_outlined,
  'savings' => Icons.savings_outlined,
  'credit_card' => Icons.credit_card_outlined,
  'investment' => Icons.trending_up,
  _ => Icons.account_balance_wallet_outlined,
};

Color _typeColor(String type) => switch (type) {
  'cash' => const Color(0xFF4CAF50),
  'checking' => const Color(0xFF42A5F5),
  'savings' => const Color(0xFF26A69A),
  'credit_card' => const Color(0xFFEF5350),
  'investment' => const Color(0xFFAB47BC),
  _ => const Color(0xFF78909C),
};

// ---------------------------------------------------------------------------
// Account type chip list
// ---------------------------------------------------------------------------

const _accountTypes = [
  ('cash', 'Efectivo'),
  ('savings', 'Ahorros'),
  ('checking', 'Corriente'),
  ('credit_card', 'Tarjeta crédito'),
  ('investment', 'Inversión'),
  ('other', 'Otra'),
];

// ---------------------------------------------------------------------------
// Color swatches for the picker (mockup: teal, blue, orange, red, purple, grey)
// ---------------------------------------------------------------------------

const _colorSwatches = [
  Color(0xFF0F9D8C), // teal (brand)
  Color(0xFF42A5F5), // blue
  Color(0xFFFFA726), // orange
  Color(0xFFEF5350), // red
  Color(0xFFAB47BC), // purple
  Color(0xFF78909C), // grey-blue
];

// ---------------------------------------------------------------------------
// Dashed "Agregar cuenta" button
// ---------------------------------------------------------------------------

class _DashedAddButton extends StatelessWidget {
  const _DashedAddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant, style: BorderStyle.none),
          borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        ),
        child: CustomPaint(
          painter: _DashedBorderPainter(color: cs.outlineVariant),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, color: BalviaTheme.seed, size: 20),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: BalviaTheme.bodyStyle(
                    color: BalviaTheme.seed,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashGap = 4.0;
    const r = BalviaTheme.radiusMd;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(r),
        ),
      );

    // Draw dashes along the path.
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          paint,
        );
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Create account form (inline)
// ---------------------------------------------------------------------------

class _CreateAccountForm extends ConsumerStatefulWidget {
  const _CreateAccountForm({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_CreateAccountForm> createState() => _CreateAccountFormState();
}

class _CreateAccountFormState extends ConsumerState<_CreateAccountForm> {
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();
  String _accountType = 'savings';
  Color? _selectedColor;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'El nombre es requerido');
      return;
    }
    final rawBalance = _balanceController.text.trim();
    final initialBalance = rawBalance.isEmpty ? '0' : rawBalance;
    // Validate it's a number.
    if (Decimal.tryParse(initialBalance) == null) {
      setState(() => _error = 'Saldo inicial inválido');
      return;
    }

    String? colorHex;
    if (_selectedColor != null) {
      colorHex =
          '#${(_selectedColor!.r * 255).round().toRadixString(16).padLeft(2, '0')}'
          '${(_selectedColor!.g * 255).round().toRadixString(16).padLeft(2, '0')}'
          '${(_selectedColor!.b * 255).round().toRadixString(16).padLeft(2, '0')}';
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref
          .read(accountRepositoryProvider)
          .create(
            name: name,
            accountType: _accountType,
            initialBalance: initialBalance,
            color: colorHex,
          );
      widget.onSaved();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = apiErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BalviaTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Crear nueva cuenta',
              style: BalviaTheme.titleStyle(color: cs.onSurface),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            // Name.
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la cuenta',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            // Account type chips.
            Text(
              'Tipo de cuenta',
              style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: BalviaTheme.spaceSm),
            Wrap(
              spacing: BalviaTheme.spaceSm,
              runSpacing: BalviaTheme.spaceSm,
              children: _accountTypes.map((entry) {
                final (value, label) = entry;
                final selected = _accountType == value;
                return GestureDetector(
                  onTap: () => setState(() => _accountType = value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? BalviaTheme.seed : Colors.transparent,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: selected ? BalviaTheme.seed : cs.outlineVariant,
                      ),
                    ),
                    child: Text(
                      label,
                      style: BalviaTheme.captionStyle(
                        color: selected ? Colors.white : cs.onSurfaceVariant,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            // Initial balance.
            TextField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Saldo inicial',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                helperText:
                    'Solo se establece al crear. El saldo cambia '
                    'automáticamente con tus transacciones.',
                helperMaxLines: 2,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            // Color picker.
            Text(
              'Color',
              style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: BalviaTheme.spaceSm),
            Row(
              children: _colorSwatches.map((color) {
                final selected = _selectedColor == color;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(
                      () => _selectedColor = selected ? null : color,
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: cs.onSurface, width: 2.5)
                            : null,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Guardar cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Edit account bottom sheet
// ---------------------------------------------------------------------------

class _EditAccountSheet extends ConsumerStatefulWidget {
  const _EditAccountSheet({required this.account});

  final Account account;

  @override
  ConsumerState<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends ConsumerState<_EditAccountSheet> {
  late final TextEditingController _nameController;
  late String _accountType;
  Color? _selectedColor;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.account.name);
    _accountType = widget.account.accountType;

    if (widget.account.color != null) {
      final hex = widget.account.color!.replaceFirst('#', '');
      if (hex.length == 6) {
        final value = int.tryParse('FF$hex', radix: 16);
        if (value != null) _selectedColor = Color(value);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'El nombre es requerido');
      return;
    }

    String? colorHex;
    if (_selectedColor != null) {
      colorHex =
          '#${(_selectedColor!.r * 255).round().toRadixString(16).padLeft(2, '0')}'
          '${(_selectedColor!.g * 255).round().toRadixString(16).padLeft(2, '0')}'
          '${(_selectedColor!.b * 255).round().toRadixString(16).padLeft(2, '0')}';
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await ref
          .read(accountRepositoryProvider)
          .update(
            widget.account.id,
            name: name,
            accountType: _accountType,
            color: colorHex,
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
              'Editar cuenta',
              style: BalviaTheme.titleStyle(color: cs.onSurface),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la cuenta',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            Text(
              'Tipo de cuenta',
              style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: BalviaTheme.spaceSm),
            Wrap(
              spacing: BalviaTheme.spaceSm,
              runSpacing: BalviaTheme.spaceSm,
              children: _accountTypes.map((entry) {
                final (value, label) = entry;
                final selected = _accountType == value;
                return GestureDetector(
                  onTap: () => setState(() => _accountType = value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? BalviaTheme.seed : Colors.transparent,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: selected ? BalviaTheme.seed : cs.outlineVariant,
                      ),
                    ),
                    child: Text(
                      label,
                      style: BalviaTheme.captionStyle(
                        color: selected ? Colors.white : cs.onSurfaceVariant,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: BalviaTheme.spaceMd),

            Text(
              'Color',
              style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: BalviaTheme.spaceSm),
            Row(
              children: _colorSwatches.map((color) {
                final selected = _selectedColor == color;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(
                      () => _selectedColor = selected ? null : color,
                    ),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(color: cs.onSurface, width: 2.5)
                            : null,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
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
// Empty accounts hint
// ---------------------------------------------------------------------------

class _EmptyAccountsHint extends StatelessWidget {
  const _EmptyAccountsHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      'Aún no tienes cuentas. Agrega una con el botón de abajo.',
      style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
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
