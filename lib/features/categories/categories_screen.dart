import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models/category.dart';
import '../../shared/category_avatar.dart';

// ---------------------------------------------------------------------------
// CategoriesScreen
// ---------------------------------------------------------------------------

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  // 0 = Gastos, 1 = Ingresos.
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Categorías'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            color: cs.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                apiErrorMessage(e),
                style: TextStyle(color: cs.onErrorContainer),
              ),
            ),
          ),
        ),
        data: (cats) {
          final typeKey = _tabIndex == 0 ? 'expense' : 'income';

          final system =
              cats
                  .where((c) => c.isSystem && c.categoryType == typeKey)
                  .toList()
                ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

          final own =
              cats
                  .where((c) => !c.isSystem && c.categoryType == typeKey)
                  .toList()
                ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(categoriesProvider),
            child: CustomScrollView(
              slivers: [
                // ---- Segmented control Gastos / Ingresos ----
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      BalviaTheme.spaceMd,
                      BalviaTheme.spaceSm,
                      BalviaTheme.spaceMd,
                      BalviaTheme.spaceMd,
                    ),
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Gastos')),
                        ButtonSegment(value: 1, label: Text('Ingresos')),
                      ],
                      selected: {_tabIndex},
                      onSelectionChanged: (s) =>
                          setState(() => _tabIndex = s.first),
                    ),
                  ),
                ),

                // ---- SISTEMA overline + grid ----
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      BalviaTheme.spaceMd,
                      0,
                      BalviaTheme.spaceMd,
                      BalviaTheme.spaceSm,
                    ),
                    child: Text(
                      'SISTEMA (${system.length} CATEGORÍAS)',
                      style: BalviaTheme.overlineStyle(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BalviaTheme.spaceMd,
                  ),
                  sliver: SliverGrid.count(
                    crossAxisCount: 4,
                    mainAxisSpacing: BalviaTheme.spaceMd,
                    crossAxisSpacing: BalviaTheme.spaceSm,
                    childAspectRatio: 0.75,
                    children: system
                        .map(
                          (c) => _CategoryGridCell(category: c, readOnly: true),
                        )
                        .toList(),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: BalviaTheme.spaceLg),
                ),

                // ---- Mis categorías (propias) ----
                if (own.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        BalviaTheme.spaceMd,
                        0,
                        BalviaTheme.spaceMd,
                        BalviaTheme.spaceSm,
                      ),
                      child: Text(
                        'MIS CATEGORÍAS (${own.length})',
                        style: BalviaTheme.overlineStyle(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BalviaTheme.spaceMd,
                    ),
                    sliver: SliverGrid.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: BalviaTheme.spaceMd,
                      crossAxisSpacing: BalviaTheme.spaceSm,
                      childAspectRatio: 0.75,
                      children: own
                          .map(
                            (c) => _CategoryGridCell(
                              category: c,
                              readOnly: false,
                              onTap: () => _showEditSheet(context, ref, c),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: BalviaTheme.spaceLg),
                  ),
                ],

                // ---- CTA dashed "Nueva categoría personalizada" ----
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BalviaTheme.spaceMd,
                    ),
                    child: _DashedCategoryButton(
                      onTap: () => _showCreateSheet(context, ref),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 80)),
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
        initialType: _tabIndex == 0 ? 'expense' : 'income',
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
        onDelete: () async {
          await ref.read(categoryRepositoryProvider).delete(cat.id);
          ref.invalidate(categoriesProvider);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid cell
// ---------------------------------------------------------------------------

class _CategoryGridCell extends StatelessWidget {
  const _CategoryGridCell({
    required this.category,
    required this.readOnly,
    this.onTap,
  });

  final Category category;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CategoryAvatar(category: category, radius: 28),
              if (readOnly)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      size: 9,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            category.name,
            style: BalviaTheme.captionStyle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashed CTA button
// ---------------------------------------------------------------------------

class _DashedCategoryButton extends StatelessWidget {
  const _DashedCategoryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(BalviaTheme.spaceMd),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant, style: BorderStyle.none),
          borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        ),
        child: CustomPaint(
          painter: _DashedRectPainter(color: cs.outlineVariant),
          child: Padding(
            padding: const EdgeInsets.all(BalviaTheme.spaceMd),
            child: Row(
              children: [
                Icon(Icons.add, color: BalviaTheme.seed, size: 20),
                const SizedBox(width: BalviaTheme.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nueva categoría personalizada',
                        style: BalviaTheme.bodyStyle(
                          color: BalviaTheme.seed,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Agrega tu propio icono, color y nombre',
                        style: BalviaTheme.captionStyle(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const dashW = 6.0;
    const dashG = 4.0;
    const r = BalviaTheme.radiusMd;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(r),
        ),
      );

    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dashW), paint);
        d += dashW + dashG;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Category form sheet (create / edit)
// ---------------------------------------------------------------------------

typedef _SaveCallback =
    Future<void> Function(
      String name,
      String type,
      String? icon,
      String? color,
    );

class _CategoryFormSheet extends StatefulWidget {
  const _CategoryFormSheet({
    required this.onSave,
    this.initialName = '',
    this.initialType = 'expense',
    this.initialIcon,
    this.initialColor,
    this.editMode = false,
    this.onDelete,
  });

  final _SaveCallback onSave;
  final String initialName;
  final String initialType;
  final String? initialIcon;
  final String? initialColor;
  final bool editMode;
  final Future<void> Function()? onDelete;

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

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text(
          '¿Eliminar "${_nameController.text}"? Esta acción no se puede deshacer.',
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
    setState(() => _isLoading = true);
    try {
      await widget.onDelete!();
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

            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.editMode ? 'Editar categoría' : 'Nueva categoría',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.editMode && widget.onDelete != null)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error),
                    tooltip: 'Eliminar',
                    onPressed: _isLoading ? null : _delete,
                  ),
              ],
            ),
            const SizedBox(height: 16),

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
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
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
                  : Text(
                      widget.editMode ? 'Guardar cambios' : 'Crear categoría',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
