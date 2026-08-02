import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/amount_formatter.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import 'quick_capture_controller.dart';

/// Opens the quick-capture bottom sheet. Returns whether a transaction was
/// saved. Call from any widget that has a [WidgetRef].
Future<bool> showQuickCaptureModal(
  BuildContext context,
  WidgetRef ref, {
  required List<Account> accounts,
}) async {
  if (accounts.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Primero crea una cuenta para registrar gastos.'),
      ),
    );
    return false;
  }

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProviderScope(
      overrides: [],
      child: _QuickCaptureSheet(accounts: accounts),
    ),
  );
  return result ?? false;
}

class _QuickCaptureSheet extends ConsumerStatefulWidget {
  const _QuickCaptureSheet({required this.accounts});
  final List<Account> accounts;

  @override
  ConsumerState<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends ConsumerState<_QuickCaptureSheet> {
  late final TextEditingController _descController;

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.accounts.isNotEmpty) {
        ref
            .read(quickCaptureControllerProvider.notifier)
            .initWithAccount(widget.accounts.first.id);
      }
    });
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(quickCaptureControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // Listen for successful save.
    ref.listen<QuickCaptureState>(quickCaptureControllerProvider, (prev, next) {
      if (next.savedTransaction != null && (prev?.savedTransaction == null)) {
        Navigator.of(context).pop(true);
      }
    });

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(BalviaTheme.radiusXl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          _DragHandle(),
          const SizedBox(height: BalviaTheme.spaceSm),

          // Type segmented pill (Gasto / Ingreso / Transferencia)
          _TypePill(
            current: state.transactionType,
            onChanged: (t) => ref
                .read(quickCaptureControllerProvider.notifier)
                .setTransactionType(t),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),

          // "Monto" overline label
          Text(
            'MONTO',
            style: BalviaTheme.overlineStyle(color: BalviaTheme.inkMuted),
          ),
          const SizedBox(height: BalviaTheme.spaceXs),

          // Hero amount display
          _AmountDisplay(
            rawDigits: state.rawDigits,
            transactionType: state.transactionType,
          ),

          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: BalviaTheme.spaceMd,
                vertical: 4,
              ),
              child: Text(
                state.error!,
                style: TextStyle(color: colorScheme.error, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: BalviaTheme.spaceSm),

          // Category chips (horizontal scroll)
          _CategorySection(
            transactionType: state.transactionType,
            selectedId: state.selectedCategoryId,
            onSelect: (id) => ref
                .read(quickCaptureControllerProvider.notifier)
                .selectCategory(id),
          ),
          const SizedBox(height: BalviaTheme.spaceXs),

          // "Sugerir con IA" trigger (explicit tap only — the user pays per call).
          _SuggestWithAiButton(
            enabled: state.description.trim().isNotEmpty,
            isSuggesting: state.isSuggesting,
            onTap: () => ref
                .read(quickCaptureControllerProvider.notifier)
                .suggestCategory(),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),

          // Account + description row
          _AccountAndDescRow(
            accounts: widget.accounts,
            selectedAccountId: state.selectedAccountId,
            descController: _descController,
            onAccountSelect: (id) => ref
                .read(quickCaptureControllerProvider.notifier)
                .selectAccount(id),
            onDescChanged: (v) => ref
                .read(quickCaptureControllerProvider.notifier)
                .setDescription(v),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),

          // Keypad
          _NumericKeypad(
            onDigit: (d) => ref
                .read(quickCaptureControllerProvider.notifier)
                .appendDigit(d),
            onThousands: () => ref
                .read(quickCaptureControllerProvider.notifier)
                .appendThousands(),
            onBackspace: () =>
                ref.read(quickCaptureControllerProvider.notifier).backspace(),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),

          // Bottom row: mic (disabled) + Guardar
          _BottomRow(
            isLoading: state.isLoading,
            onSave: state.isLoading
                ? null
                : () =>
                      ref.read(quickCaptureControllerProvider.notifier).save(),
          ),
          SizedBox(
            height: MediaQuery.of(context).padding.bottom + BalviaTheme.spaceMd,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: BalviaTheme.spaceMd, bottom: 4),
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
}

/// Pill-style segmented control for Gasto / Ingreso / Transferencia (mockup 14).
///
/// The active tab has a solid fill with text color:
///   Gasto → expense red background
///   Ingreso → income-green tinted background (uses primaryContainer teal)
///   Transferencia → transfer blue
class _TypePill extends StatelessWidget {
  const _TypePill({required this.current, required this.onChanged});
  final String current;
  final ValueChanged<String> onChanged;

  static const _tabs = [
    ('expense', 'Gasto'),
    ('income', 'Ingreso'),
    ('transfer', 'Transferencia'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BalviaTheme.spaceMd),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          children: _tabs.map((tab) {
            final selected = current == tab.$1;
            final activeColor = _activeColor(tab.$1);
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(tab.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? activeColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    tab.$2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? Colors.white : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Color _activeColor(String type) => switch (type) {
    'expense' => BalviaTheme.expense,
    'income' => BalviaTheme.seed,
    'transfer' => BalviaTheme.transfer,
    _ => BalviaTheme.expense,
  };
}

/// Large colored amount display (mockup 14 — amount is colored by type).
class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({
    required this.rawDigits,
    required this.transactionType,
  });
  final String rawDigits;
  final String transactionType;

  @override
  Widget build(BuildContext context) {
    final color = BalviaTheme.colorForType(transactionType);
    final displayText = rawDigits.isEmpty
        ? '0'
        : AmountFormatter.formatDisplay(rawDigits);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BalviaTheme.spaceMd),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '\$$displayText',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Category chips with ✨ "sugerida" style for the first chip (visual only).
class _CategorySection extends ConsumerWidget {
  const _CategorySection({
    required this.transactionType,
    required this.selectedId,
    required this.onSelect,
  });
  final String transactionType;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return categoriesAsync.when(
      loading: () => const SizedBox(
        height: 44,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => const SizedBox.shrink(),
      data: (all) {
        final filtered =
            all
                .where(
                  (c) =>
                      c.categoryType == transactionType && c.parentId == null,
                )
                .toList()
              ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

        if (filtered.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: BalviaTheme.spaceMd,
            ),
            itemCount: filtered.length,
            separatorBuilder: (context, i) =>
                const SizedBox(width: BalviaTheme.spaceSm),
            itemBuilder: (_, i) {
              final cat = filtered[i];
              final isSelected = cat.id == selectedId;
              // First chip gets the ✨ "sugerida" visual (design system §5).
              final isSuggested = i == 0 && selectedId == null;
              return _CategoryChip(
                category: cat,
                selected: isSelected,
                suggested: isSuggested,
                onTap: () => onSelect(isSelected ? null : cat.id),
              );
            },
          ),
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.suggested,
    required this.onTap,
  });
  final Category category;
  final bool selected;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Color bg;
    Color fg;
    Border? border;

    if (selected) {
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
      border = Border.all(color: scheme.primary, width: 1.5);
    } else if (suggested) {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      border = Border.all(color: scheme.outline.withValues(alpha: 0.5));
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(100),
          border: border,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (suggested)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text('✨', style: TextStyle(fontSize: 12, color: fg)),
              ),
            Text(
              category.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtle "Sugerir con IA" trigger shown under the category chips.
/// Enabled only when there is a description; shows a spinner while the
/// suggestion is in flight. Best-effort — it never blocks the save flow.
class _SuggestWithAiButton extends StatelessWidget {
  const _SuggestWithAiButton({
    required this.enabled,
    required this.isSuggesting,
    required this.onTap,
  });

  final bool enabled;
  final bool isSuggesting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = enabled && !isSuggesting;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BalviaTheme.spaceMd),
        child: TextButton.icon(
          onPressed: active ? onTap : null,
          style: TextButton.styleFrom(
            foregroundColor: BalviaTheme.seed,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: isSuggesting
              ? const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: active ? BalviaTheme.seed : cs.onSurfaceVariant,
                ),
          label: Text(
            'Sugerir con IA',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? BalviaTheme.seed : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Account chip + description chip side by side (mockup 14 bottom row before keypad).
class _AccountAndDescRow extends StatelessWidget {
  const _AccountAndDescRow({
    required this.accounts,
    required this.selectedAccountId,
    required this.descController,
    required this.onAccountSelect,
    required this.onDescChanged,
  });

  final List<Account> accounts;
  final String? selectedAccountId;
  final TextEditingController descController;
  final ValueChanged<String> onAccountSelect;
  final ValueChanged<String> onDescChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final selectedAccount = accounts.isNotEmpty
        ? accounts.firstWhere(
            (a) => a.id == selectedAccountId,
            orElse: () => accounts.first,
          )
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BalviaTheme.spaceMd),
      child: Row(
        children: [
          // Account chip
          if (selectedAccount != null)
            Flexible(
              child: GestureDetector(
                onTap: () => _pickAccount(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BalviaTheme.spaceSm,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.attach_money,
                        size: 16,
                        color: BalviaTheme.seed,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        selectedAccount.name,
                        style: BalviaTheme.bodyStyle(color: cs.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(width: BalviaTheme.spaceSm),
          // Description chip
          Expanded(
            child: GestureDetector(
              onTap: () => _showDescInput(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: BalviaTheme.spaceSm,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        descController.text.isEmpty
                            ? 'Descripción'
                            : descController.text,
                        style: BalviaTheme.bodyStyle(
                          color: descController.text.isEmpty
                              ? cs.onSurfaceVariant
                              : cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _pickAccount(BuildContext context) {
    showModalBottomSheet<String>(
      context: context,
      builder: (_) => _AccountPickerSheet(accounts: accounts),
    ).then((id) {
      if (id != null) onAccountSelect(id);
    });
  }

  void _showDescInput(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Descripción', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              autofocus: true,
              onChanged: onDescChanged,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Ej: Almuerzo corrientazo',
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountPickerSheet extends StatelessWidget {
  const _AccountPickerSheet({required this.accounts});
  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Seleccionar cuenta',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...accounts.map(
            (a) => ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(a.name),
              subtitle: Text(
                AmountFormatter.formatCOP(a.currentBalance),
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => Navigator.of(context).pop(a.id),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Numeric keypad (mockup 14 — 3 columns + ",000" + "⌫")
// ---------------------------------------------------------------------------

/// Custom numeric keypad with:
///   - 1–9 digits
///   - ",000" key (appends three zeros — design system §4)
///   - 0 key
///   - ⌫ backspace key
class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({
    required this.onDigit,
    required this.onThousands,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onThousands;
  final VoidCallback onBackspace;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    [',000', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BalviaTheme.spaceMd),
      child: Column(
        children: _rows.map((row) {
          return Row(
            children: row.map((key) {
              return Expanded(
                child: _KeypadKey(
                  label: key,
                  onTap: switch (key) {
                    '⌫' => onBackspace,
                    ',000' => onThousands,
                    _ => () => onDigit(key),
                  },
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBackspace = label == '⌫';
    final isThousands = label == ',000';

    Color bgColor;
    Widget child;

    if (isBackspace) {
      bgColor = scheme.errorContainer.withValues(alpha: 0.5);
      child = Icon(Icons.backspace_outlined, size: 22, color: scheme.error);
    } else if (isThousands) {
      bgColor = scheme.surfaceContainerHighest;
      child = Text(
        ',000',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      );
    } else {
      bgColor = scheme.surfaceContainerHighest;
      child = Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w500),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(3),
      child: SizedBox(
        height: 56,
        child: Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom row: mic button (disabled) + Guardar button
// ---------------------------------------------------------------------------

class _BottomRow extends StatelessWidget {
  const _BottomRow({required this.isLoading, required this.onSave});
  final bool isLoading;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BalviaTheme.spaceMd),
      child: Row(
        children: [
          // Mic button — disabled with "Próximamente" tooltip
          Tooltip(
            message: 'Próximamente',
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: cs.outlineVariant),
                color: cs.surfaceContainerHighest,
              ),
              child: Icon(
                Icons.mic_outlined,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: BalviaTheme.spaceMd),
          // Guardar button — wide
          Expanded(
            child: FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(
                backgroundColor: BalviaTheme.seed,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Guardar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
