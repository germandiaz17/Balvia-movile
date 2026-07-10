import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../data/models/category.dart';

// ---------------------------------------------------------------------------
// CategoriesScreen
// ---------------------------------------------------------------------------

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(categoriesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_new_category',
        onPressed: () => _showCreateSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                apiErrorMessage(e),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
        ),
        data: (cats) {
          final system = cats.where((c) => c.isSystem).toList()
            ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          final own = cats.where((c) => !c.isSystem).toList()
            ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(categoriesProvider),
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 88),
              children: [
                if (own.isNotEmpty) ...[
                  _SectionHeader(title: 'Mis categorías (${own.length})'),
                  ...own.map(
                    (c) => _CategoryTile(
                      category: c,
                      onEdit: () => _showEditSheet(context, ref, c),
                      onDelete: () => _confirmDelete(context, ref, c),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _SectionHeader(title: 'Sistema (${system.length})'),
                ...system.map(
                  (c) => _CategoryTile(
                    category: c,
                    readOnly: true,
                    onEdit: null,
                    onDelete: null,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCreateSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryFormSheet(
        onSave: (name, type, icon, color) async {
          await ref
              .read(categoryRepositoryProvider)
              .create(name: name, categoryType: type, icon: icon, color: color);
          ref.invalidate(categoriesProvider);
        },
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, Category cat) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryFormSheet(
        initialName: cat.name,
        initialType: cat.categoryType,
        initialIcon: cat.icon,
        initialColor: cat.color,
        editMode: true,
        onSave: (name, type, icon, color) async {
          await ref
              .read(categoryRepositoryProvider)
              .update(cat.id, name: name, icon: icon, color: color);
          ref.invalidate(categoriesProvider);
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category cat,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Eliminar "${cat.name}"? Esta acción no se puede deshacer.'),
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
      await ref.read(categoryRepositoryProvider).delete(cat.id);
      ref.invalidate(categoriesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Categoría "${cat.name}" eliminada'),
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
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category tile
// ---------------------------------------------------------------------------

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.onEdit,
    required this.onDelete,
    this.readOnly = false,
  });

  final Category category;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final typeColor = switch (category.categoryType) {
      'income' => cs.primary,
      'expense' => cs.error,
      _ => cs.secondary,
    };
    final typeLabel = switch (category.categoryType) {
      'income' => 'Ingreso',
      'expense' => 'Gasto',
      _ => 'Transferencia',
    };

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: typeColor.withValues(alpha: 0.15),
          child: readOnly
              ? Icon(Icons.lock_outline, size: 16, color: typeColor)
              : Icon(Icons.label_outline, size: 16, color: typeColor),
        ),
        title: Text(category.name),
        subtitle: Text(
          typeLabel,
          style: theme.textTheme.bodySmall?.copyWith(color: typeColor),
        ),
        trailing: readOnly
            ? Tooltip(
                message: 'Categoría del sistema (solo lectura)',
                child: Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: cs.error,
                    ),
                    onPressed: onDelete,
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category form (create / edit)
// ---------------------------------------------------------------------------

typedef _SaveCallback =
    Future<void> Function(String name, String type, String? icon, String? color);

class _CategoryFormSheet extends StatefulWidget {
  const _CategoryFormSheet({
    required this.onSave,
    this.initialName = '',
    this.initialType = 'expense',
    this.initialIcon,
    this.initialColor,
    this.editMode = false,
  });

  final _SaveCallback onSave;
  final String initialName;
  final String initialType;
  final String? initialIcon;
  final String? initialColor;
  final bool editMode;

  @override
  State<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends State<_CategoryFormSheet> {
  late final TextEditingController _nameController;
  late String _type;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _type = widget.initialType;
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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await widget.onSave(name, _type, widget.initialIcon, widget.initialColor);
      if (mounted) Navigator.of(context).pop();
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
              widget.editMode ? 'Editar categoría' : 'Nueva categoría',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Name field.
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),

            // Type selector (disabled in edit mode — contract only accepts
            // name, parent_id, icon, color, display_order for PUT).
            if (!widget.editMode) ...[
              Text('Tipo', style: theme.textTheme.labelMedium),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Gasto')),
                  ButtonSegment(value: 'income', label: Text('Ingreso')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(height: 12),
            ],

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
                  : Text(widget.editMode ? 'Guardar cambios' : 'Crear categoría'),
            ),
          ],
        ),
      ),
    );
  }
}
