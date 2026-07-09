import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/amount_formatter.dart';
import '../../core/providers.dart';
import '../../data/models/account.dart';
import '../../data/models/category.dart';
import 'quick_capture_controller.dart';

/// Opens the quick-capture bottom sheet and returns whether a transaction was
/// saved successfully. Call from any widget that has a [WidgetRef].
///
/// The caller is responsible for refreshing dependent providers
/// (e.g. accountsProvider) after a successful save.
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
      // Override so each modal open starts with fresh state.
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
    // Pre-select the first account after the first frame.
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DragHandle(),
          _TypeToggle(
            current: state.transactionType,
            onChanged: (t) => ref
                .read(quickCaptureControllerProvider.notifier)
                .setTransactionType(t),
          ),
          _AmountDisplay(rawDigits: state.rawDigits),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                state.error!,
                style: TextStyle(color: colorScheme.error, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 8),
          _CategorySection(
            transactionType: state.transactionType,
            selectedId: state.selectedCategoryId,
            onSelect: (id) => ref
                .read(quickCaptureControllerProvider.notifier)
                .selectCategory(id),
          ),
          const SizedBox(height: 8),
          _AccountSelector(
            accounts: widget.accounts,
            selectedId: state.selectedAccountId,
            onSelect: (id) => ref
                .read(quickCaptureControllerProvider.notifier)
                .selectAccount(id),
          ),
          const SizedBox(height: 8),
          _DescriptionField(
            controller: _descController,
            onChanged: (v) => ref
                .read(quickCaptureControllerProvider.notifier)
                .setDescription(v),
          ),
          const SizedBox(height: 12),
          _NumericKeypad(
            onDigit: (d) => ref
                .read(quickCaptureControllerProvider.notifier)
                .appendDigit(d),
            onBackspace: () =>
                ref.read(quickCaptureControllerProvider.notifier).backspace(),
            onSave: state.isLoading
                ? null
                : () =>
                      ref.read(quickCaptureControllerProvider.notifier).save(),
            isSaving: state.isLoading,
          ),
          const SizedBox(height: 16),
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
      padding: const EdgeInsets.only(top: 12, bottom: 4),
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

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.current, required this.onChanged});
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _ToggleChip(
              label: 'Gasto',
              icon: Icons.remove_circle_outline,
              selected: current == 'expense',
              selectedColor: scheme.errorContainer,
              selectedForeground: scheme.onErrorContainer,
              onTap: () => onChanged('expense'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ToggleChip(
              label: 'Ingreso',
              icon: Icons.add_circle_outline,
              selected: current == 'income',
              selectedColor: scheme.primaryContainer,
              selectedForeground: scheme.onPrimaryContainer,
              onTap: () => onChanged('income'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.selectedForeground,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedColor;
  final Color selectedForeground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedColor : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? selectedForeground : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? selectedForeground : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.rawDigits});
  final String rawDigits;

  @override
  Widget build(BuildContext context) {
    final displayText = rawDigits.isEmpty
        ? '0'
        : AmountFormatter.formatDisplay(rawDigits);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            'COP ',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                displayText,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'No se pudieron cargar las categorías',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filtered.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final cat = filtered[i];
              final isSelected = cat.id == selectedId;
              return _CategoryChip(
                category: cat,
                selected: isSelected,
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
    required this.onTap,
  });
  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: scheme.primary, width: 1.5)
              : null,
        ),
        child: Text(
          category.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AccountSelector extends StatelessWidget {
  const _AccountSelector({
    required this.accounts,
    required this.selectedId,
    required this.onSelect,
  });
  final List<Account> accounts;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (accounts.length == 1) {
      // Only one account — show it as non-interactive label.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              accounts.first.name,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final selected = accounts.firstWhere(
      (a) => a.id == selectedId,
      orElse: () => accounts.first,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => _pickAccount(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                selected.name,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _pickAccount(BuildContext context) {
    showModalBottomSheet<String>(
      context: context,
      builder: (_) => _AccountPickerSheet(accounts: accounts),
    ).then((id) {
      if (id != null) onSelect(id);
    });
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
                'COP ${a.currentBalance.toStringAsFixed(0)}',
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

class _DescriptionField extends StatelessWidget {
  const _DescriptionField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: const InputDecoration(
          hintText: 'Descripción (opcional)',
          isDense: true,
          border: OutlineInputBorder(),
          filled: true,
        ),
        maxLines: 1,
        textCapitalization: TextCapitalization.sentences,
      ),
    );
  }
}

/// A custom numeric keypad optimised for speed. Digits are large tap targets;
/// backspace is on the right; the save button is prominent and green.
class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onSave,
    required this.isSaving,
  });
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onSave;
  final bool isSaving;

  static const _rows = [
    ['7', '8', '9'],
    ['4', '5', '6'],
    ['1', '2', '3'],
    ['', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Digit grid — 3 columns.
          Expanded(
            flex: 3,
            child: Column(
              children: _rows.map((row) {
                return Row(
                  children: row.map((key) {
                    if (key.isEmpty) return const Expanded(child: SizedBox());
                    return Expanded(
                      child: _KeypadButton(
                        label: key,
                        onTap: key == '⌫' ? onBackspace : () => onDigit(key),
                      ),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 8),
          // Save button — tall, on the right.
          Expanded(
            child: SizedBox(
              height:
                  _rowHeight * _rows.length + _rowSpacing * (_rows.length - 1),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: EdgeInsets.zero,
                ),
                onPressed: onSave,
                child: isSaving
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_rounded,
                            size: 28,
                            color: scheme.onPrimary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Guardar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onPrimary,
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
}

const _rowHeight = 56.0;
const _rowSpacing = 4.0;

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBackspace = label == '⌫';
    return Padding(
      padding: const EdgeInsets.all(_rowSpacing / 2),
      child: SizedBox(
        height: _rowHeight,
        child: Material(
          color: isBackspace
              ? scheme.errorContainer.withAlpha(120)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Center(
              child: isBackspace
                  ? Icon(
                      Icons.backspace_outlined,
                      size: 22,
                      color: scheme.error,
                    )
                  : Text(
                      label,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
