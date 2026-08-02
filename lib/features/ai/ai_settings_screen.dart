// AI settings screen — Perfil → "Inteligencia artificial".
//
// BYOK (bring your own key): the user provides their own Claude/OpenAI API key,
// which is stored ENCRYPTED on the server and never shared. The key is
// write-only — the backend never returns it, so this screen shows status via
// `has_key`/`provider`, never the key value.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models/ai_settings.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();

  String _provider = 'anthropic';
  bool _obscureKey = true;
  bool _saving = false;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settingsAsync = ref.watch(aiSettingsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Inteligencia artificial'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            _buildBody(context, cs, null, error: apiErrorMessage(e)),
        data: (settings) => _buildBody(context, cs, settings),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ColorScheme cs,
    AiSettings? settings, {
    String? error,
  }) {
    final configured = settings?.configured ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        BalviaTheme.spaceMd,
        BalviaTheme.spaceMd,
        BalviaTheme.spaceMd,
        40,
      ),
      children: [
        // ---- Explanation ----
        Container(
          padding: const EdgeInsets.all(BalviaTheme.spaceMd),
          decoration: BoxDecoration(
            color: BalviaTheme.seed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_awesome, color: BalviaTheme.seed, size: 20),
              const SizedBox(width: BalviaTheme.spaceSm),
              Expanded(
                child: Text(
                  'Usa tu propia llave de IA (Claude o compatible con OpenAI) '
                  'para categorizar tus gastos automáticamente. La llave se '
                  'guarda cifrada en el servidor y nunca se comparte.',
                  style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: BalviaTheme.spaceMd),

        // ---- Current status ----
        if (error != null)
          _StatusCard(
            icon: Icons.error_outline,
            color: cs.error,
            title: 'No se pudo cargar el estado',
            subtitle: error,
          )
        else if (configured)
          _StatusCard(
            icon: Icons.check_circle_outline,
            color: BalviaTheme.seed,
            title: 'Configurado con ${_providerLabel(settings!.provider)}',
            subtitle:
                'Tu llave está guardada de forma segura. Por seguridad no se '
                'muestra; para cambiarla ingresa una nueva.',
          )
        else
          _StatusCard(
            icon: Icons.info_outline,
            color: cs.onSurfaceVariant,
            title: 'Sin configurar',
            subtitle: 'Aún no has agregado una llave de IA.',
          ),
        const SizedBox(height: BalviaTheme.spaceLg),

        // ---- Provider selector ----
        Text(
          'Proveedor',
          style: BalviaTheme.bodyStyle(
            color: cs.onSurface,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: BalviaTheme.spaceSm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'anthropic',
              label: Text('Claude'),
              icon: Icon(Icons.auto_awesome, size: 16),
            ),
            ButtonSegment(
              value: 'openai_compatible',
              label: Text('OpenAI-compat.'),
              icon: Icon(Icons.hub_outlined, size: 16),
            ),
          ],
          selected: {_provider},
          onSelectionChanged: (sel) => setState(() => _provider = sel.first),
        ),
        const SizedBox(height: BalviaTheme.spaceMd),

        // ---- API key ----
        Text(
          configured ? 'Nueva llave (API key)' : 'Llave (API key)',
          style: BalviaTheme.bodyStyle(
            color: cs.onSurface,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: BalviaTheme.spaceSm),
        TextField(
          controller: _apiKeyController,
          obscureText: _obscureKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            hintText: _provider == 'anthropic' ? 'sk-ant-...' : 'sk-...',
            border: const OutlineInputBorder(),
            filled: true,
            suffixIcon: IconButton(
              icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility),
              tooltip: _obscureKey ? 'Mostrar' : 'Ocultar',
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ),
        ),

        // ---- OpenAI-compatible extras ----
        if (_provider == 'openai_compatible') ...[
          const SizedBox(height: BalviaTheme.spaceMd),
          Text(
            'Base URL (opcional)',
            style: BalviaTheme.bodyStyle(
              color: cs.onSurface,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),
          TextField(
            controller: _baseUrlController,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://api.openai.com/v1',
              border: OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: BalviaTheme.spaceMd),
          Text(
            'Modelo (opcional)',
            style: BalviaTheme.bodyStyle(
              color: cs.onSurface,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),
          TextField(
            controller: _modelController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              hintText: 'gpt-4o-mini',
              border: OutlineInputBorder(),
              filled: true,
            ),
          ),
        ],
        const SizedBox(height: BalviaTheme.spaceLg),

        // ---- Save button ----
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: BalviaTheme.seed,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
            ),
          ),
          child: _saving
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
        ),

        // ---- Delete button ----
        if (configured) ...[
          const SizedBox(height: BalviaTheme.spaceSm),
          TextButton.icon(
            onPressed: _saving ? null : _confirmDelete,
            style: TextButton.styleFrom(foregroundColor: cs.error),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar configuración'),
          ),
        ],
      ],
    );
  }

  String _providerLabel(String? provider) => switch (provider) {
    'anthropic' => 'Claude (Anthropic)',
    'openai_compatible' => 'OpenAI-compatible',
    _ => provider ?? 'IA',
  };

  Future<void> _save() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una llave (API key)')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(aiRepositoryProvider)
          .setSettings(
            provider: _provider,
            apiKey: apiKey,
            baseUrl: _provider == 'openai_compatible'
                ? _baseUrlController.text.trim()
                : null,
            model: _provider == 'openai_compatible'
                ? _modelController.text.trim()
                : null,
          );
      if (!mounted) return;
      _apiKeyController.clear();
      ref.invalidate(aiSettingsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración de IA guardada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar configuración'),
        content: const Text(
          '¿Seguro que quieres eliminar tu configuración de IA? Se borrará '
          'tu llave del servidor.',
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

    setState(() => _saving = true);
    try {
      await ref.read(aiRepositoryProvider).deleteSettings();
      if (!mounted) return;
      _apiKeyController.clear();
      ref.invalidate(aiSettingsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración de IA eliminada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_errorMessage(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 503 means the server hasn't set up AI encryption yet — surface a clearer
  /// message; otherwise fall back to the shared api-error helper.
  String _errorMessage(Object e) {
    if (e is DioException && e.response?.statusCode == 503) {
      return 'La IA no está disponible en el servidor todavía';
    }
    return apiErrorMessage(e);
  }
}

// ---------------------------------------------------------------------------
// Status card
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(BalviaTheme.spaceMd),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: BalviaTheme.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: BalviaTheme.bodyStyle(
                    color: cs.onSurface,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
