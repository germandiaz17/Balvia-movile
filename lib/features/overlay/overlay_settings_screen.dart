// Overlay settings screen — Perfil → "Burbuja flotante".
//
// Available on all platforms (builds without errors on Linux/desktop).
// On non-Android, shows an informational message instead of the controls.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync_providers.dart';
import '../../core/theme.dart';
import '../../data/models/account.dart';
import 'overlay_controller.dart';
import 'overlay_logic.dart';
import 'overlay_settings.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class OverlaySettingsScreen extends ConsumerStatefulWidget {
  const OverlaySettingsScreen({super.key});

  @override
  ConsumerState<OverlaySettingsScreen> createState() =>
      _OverlaySettingsScreenState();
}

class _OverlaySettingsScreenState extends ConsumerState<OverlaySettingsScreen> {
  bool _isAndroid = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isAndroid = Theme.of(context).platform == TargetPlatform.android;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Burbuja flotante'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
      ),
      body: !_isAndroid
          ? _buildNonAndroid(context, cs)
          : _buildAndroidContent(context, cs),
    );
  }

  // ---- Non-Android placeholder ----

  Widget _buildNonAndroid(BuildContext context, ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.android, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Solo disponible en Android',
              style: BalviaTheme.titleStyle(color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'La burbuja flotante es una función exclusiva de Android que '
              'permite capturar gastos mientras usas otras apps.',
              style: BalviaTheme.bodyStyle(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---- Android content ----

  Widget _buildAndroidContent(BuildContext context, ColorScheme cs) {
    final settingsAsync = ref.watch(overlaySettingsProvider);
    final overlayActive = ref.watch(overlayControllerProvider).value ?? false;

    return settingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (settings) => ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // ---- Live preview ----
          _BubblePreview(settings: settings),

          // ---- Master toggle ----
          SwitchListTile(
            title: Text(
              'Activar burbuja',
              style: BalviaTheme.bodyStyle(color: cs.onSurface).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              overlayActive ? 'La burbuja está activa' : 'La burbuja está inactiva',
              style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            ),
            secondary: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: BalviaTheme.seed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
              ),
              child: const Icon(
                Icons.bubble_chart_outlined,
                color: BalviaTheme.seed,
                size: 18,
              ),
            ),
            value: settings.enabled,
            onChanged: (value) async {
              final updated = settings.copyWith(enabled: value);
              await ref.read(overlaySettingsProvider.notifier).save(updated);

              if (!context.mounted) return;
              if (value) {
                await ref.read(overlayControllerProvider.notifier).enable(context);
              } else {
                await ref.read(overlayControllerProvider.notifier).disable();
              }
            },
          ),

          const Divider(),

          // ---- Transparency ----
          _SectionLabel('APARIENCIA'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.opacity_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Transparencia',
                  style: BalviaTheme.bodyStyle(color: cs.onSurface),
                ),
                const Spacer(),
                Text(
                  '${(settings.opacity * 100).round()}%',
                  style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Slider(
            value: settings.opacity,
            min: 0.3,
            max: 1.0,
            divisions: 14,
            onChanged: (v) async {
              final updated = settings.copyWith(opacity: clampOpacity(v));
              await ref.read(overlaySettingsProvider.notifier).save(updated);
              if (settings.enabled) {
                await ref.read(overlayControllerProvider.notifier).pushSettings();
              }
            },
          ),

          // ---- Color picker ----
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Color de la burbuja',
                  style: BalviaTheme.bodyStyle(color: cs.onSurface),
                ),
                const SizedBox(height: 8),
                _ColorPicker(
                  selectedHex: settings.colorHex,
                  onSelect: (hex) async {
                    final updated = settings.copyWith(colorHex: hex);
                    await ref
                        .read(overlaySettingsProvider.notifier)
                        .save(updated);
                    if (settings.enabled) {
                      await ref
                          .read(overlayControllerProvider.notifier)
                          .pushSettings();
                    }
                  },
                ),
              ],
            ),
          ),

          const Divider(),

          // ---- Account ----
          _SectionLabel('CUENTA POR DEFECTO'),
          _AccountSelector(
            selectedId: settings.defaultAccountId,
            onSelect: (id) async {
              final updated = settings.copyWith(
                defaultAccountId: id == '' ? null : id,
              );
              await ref.read(overlaySettingsProvider.notifier).save(updated);
              if (settings.enabled) {
                await ref
                    .read(overlayControllerProvider.notifier)
                    .pushSettings();
              }
            },
          ),

          const Divider(),

          // ---- Info to show ----
          _SectionLabel('INFORMACIÓN AL EXPANDIR'),
          SwitchListTile(
            title: Text(
              'Gasto de hoy',
              style: BalviaTheme.bodyStyle(color: cs.onSurface),
            ),
            subtitle: Text(
              'Muestra el gasto acumulado del día',
              style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            ),
            value: settings.showTodaySpend,
            onChanged: (v) async {
              final updated = settings.copyWith(showTodaySpend: v);
              await ref.read(overlaySettingsProvider.notifier).save(updated);
              if (settings.enabled) {
                await ref
                    .read(overlayControllerProvider.notifier)
                    .pushSettings();
              }
            },
          ),
          SwitchListTile(
            title: Text(
              'Saldo de cuenta',
              style: BalviaTheme.bodyStyle(color: cs.onSurface),
            ),
            subtitle: Text(
              'Muestra el saldo de la cuenta por defecto',
              style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            ),
            value: settings.showBalance,
            onChanged: (v) async {
              final updated = settings.copyWith(showBalance: v);
              await ref.read(overlaySettingsProvider.notifier).save(updated);
              if (settings.enabled) {
                await ref
                    .read(overlayControllerProvider.notifier)
                    .pushSettings();
              }
            },
          ),

          const Divider(),

          // ---- Auto-off ----
          _SectionLabel('AUTO-APAGADO'),
          _AutoOffSelector(
            currentMinutes: settings.autoOffMinutes,
            onSelect: (minutes) async {
              final updated = settings.copyWith(autoOffMinutes: minutes ?? -1);
              await ref.read(overlaySettingsProvider.notifier).save(updated);
            },
          ),

          const SizedBox(height: 8),

          // ---- Limits note ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Nota: en algunos Android (Xiaomi, Huawei, Samsung) el sistema '
              'puede matar la burbuja en background agresivo. La burbuja se '
              'reactiva automáticamente al abrir Balvia.',
              style: BalviaTheme.captionStyle(
                color: cs.onSurfaceVariant,
              ).copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: BalviaTheme.overlineStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Live bubble preview
// ---------------------------------------------------------------------------

class _BubblePreview extends StatelessWidget {
  const _BubblePreview({required this.settings});
  final OverlaySettings settings;

  @override
  Widget build(BuildContext context) {
    final color = settings.bubbleColor;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
      ),
      child: Column(
        children: [
          Text(
            'Vista previa',
            style: BalviaTheme.captionStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: settings.opacity,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: CustomPaint(
                  size: const Size(28, 28),
                  painter: _WhiteLogoPainter(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal logo painter for the preview (mirrors BalviaLogoMark but white).
class _WhiteLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.65)
      ..lineTo(w * 0.30, h * 0.35)
      ..lineTo(w * 0.50, h * 0.55)
      ..lineTo(w * 0.70, h * 0.25)
      ..lineTo(w * 0.92, h * 0.45);
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(w * 0.70, h * 0.25),
      w * 0.07,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Color picker (circle swatches)
// ---------------------------------------------------------------------------

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selectedHex, required this.onSelect});

  final String selectedHex;
  final void Function(String) onSelect;

  static const _colors = [
    ('#0F9D8C', Color(0xFF0F9D8C)), // Brand teal
    ('#5C6BC0', Color(0xFF5C6BC0)), // Indigo
    ('#7E57C2', Color(0xFF7E57C2)), // Purple
    ('#EF5350', Color(0xFFEF5350)), // Red
    ('#FFA726', Color(0xFFFFA726)), // Amber
    ('#42A5F5', Color(0xFF42A5F5)), // Blue
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _colors.map((entry) {
        final hex = entry.$1;
        final color = entry.$2;
        final isSelected = selectedHex.toLowerCase() == hex.toLowerCase();
        return GestureDetector(
          onTap: () => onSelect(hex),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 2.5,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Account selector
// ---------------------------------------------------------------------------

class _AccountSelector extends ConsumerWidget {
  const _AccountSelector({required this.selectedId, required this.onSelect});

  final String? selectedId;
  final void Function(String) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(localAccountsProvider);

    return accountsAsync.when(
      loading: () => const ListTile(title: Text('Cargando cuentas…')),
      error: (err, st) => const ListTile(title: Text('Error al cargar cuentas')),
      data: (accounts) {
        if (accounts.isEmpty) {
          return ListTile(
            title: Text(
              'No hay cuentas. Crea una cuenta primero.',
              style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
            ),
          );
        }

        final selected = selectedId != null
            ? accounts.firstWhere(
                (a) => a.id == selectedId,
                orElse: () => accounts.first,
              )
            : accounts.first;

        return ListTile(
          title: Text(
            'Cuenta',
            style: BalviaTheme.bodyStyle(color: cs.onSurface),
          ),
          subtitle: Text(
            selected.name,
            style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
          ),
          trailing: Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
          onTap: () => _showPicker(context, accounts),
        );
      },
    );
  }

  void _showPicker(BuildContext context, List<Account> accounts) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(
              'Cuenta por defecto',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            ...accounts.map(
              (a) => ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(a.name),
                trailing: a.id == selectedId
                    ? const Icon(Icons.check, color: BalviaTheme.seed)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSelect(a.id);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Auto-off selector
// ---------------------------------------------------------------------------

class _AutoOffSelector extends StatelessWidget {
  const _AutoOffSelector({
    required this.currentMinutes,
    required this.onSelect,
  });

  final int? currentMinutes;
  final void Function(int?) onSelect;

  static const _options = <(String, int?)>[
    ('Nunca', null),
    ('5 minutos', 5),
    ('10 minutos', 10),
    ('15 minutos', 15),
    ('30 minutos', 30),
    ('1 hora', 60),
  ];

  // Record fields accessed via positional $1/$2 — lint prefers named records
  // but we use them for brevity; suppress via comment if needed.

  String get _currentLabel {
    for (final opt in _options) {
      if (opt.$2 == currentMinutes) return opt.$1;
    }
    return '${currentMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
        ),
        child: const Icon(
          Icons.timer_outlined,
          size: 18,
          color: Color(0xFFFFA726),
        ),
      ),
      title: Text(
        'Ocultar burbuja después de',
        style: BalviaTheme.bodyStyle(color: cs.onSurface),
      ),
      subtitle: Text(
        _currentLabel,
        style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
      ),
      trailing: Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
      onTap: () => _showPicker(context),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Text(
              'Auto-apagado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            ..._options.map(
              (opt) => ListTile(
                title: Text(opt.$1),
                trailing: currentMinutes == opt.$2
                    ? const Icon(Icons.check, color: BalviaTheme.seed)
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSelect(opt.$2);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
