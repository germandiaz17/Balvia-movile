import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models/user_settings.dart';

// ---------------------------------------------------------------------------
// Screen
//
// Domain rule 8: a change to the tracking configuration applies to the NEXT
// seguimiento, never to the one currently running. That is the whole UX problem
// here — a user who changes the duration and sees today's period unchanged will
// think it did not save. So the cut-off date is stated up front in a fixed
// banner (not a SnackBar that scrolls away), repeated in the confirmation
// dialog, and repeated again on success.
// ---------------------------------------------------------------------------

class TrackingSettingsScreen extends ConsumerStatefulWidget {
  const TrackingSettingsScreen({super.key});

  @override
  ConsumerState<TrackingSettingsScreen> createState() =>
      _TrackingSettingsScreenState();
}

class _TrackingSettingsScreenState
    extends ConsumerState<TrackingSettingsScreen> {
  /// Pending selection, null until the user touches the selector.
  int? _selectedDuration;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(userSettingsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Configuración del seguimiento')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBody(message: apiErrorMessage(e)),
        data: (settings) => _buildBody(settings),
      ),
    );
  }

  Widget _buildBody(UserSettings settings) {
    final cs = Theme.of(context).colorScheme;
    final duration = _selectedDuration ?? settings.trackingDurationDays;
    final dirty = duration != settings.trackingDurationDays;

    return ListView(
      padding: const EdgeInsets.all(BalviaTheme.spaceMd),
      children: [
        _ActivePeriodCard(settings: settings),
        const SizedBox(height: BalviaTheme.spaceLg),

        Text(
          'DURACIÓN DEL SEGUIMIENTO',
          style: BalviaTheme.overlineStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: BalviaTheme.spaceSm),
        // A closed 28–31 range, so a segmented control rather than a free field.
        SegmentedButton<int>(
          segments: [
            for (final d in kTrackingDurations)
              ButtonSegment(value: d, label: Text('$d')),
          ],
          selected: {duration},
          onSelectionChanged: _saving
              ? null
              : (s) => setState(() => _selectedDuration = s.first),
        ),
        const SizedBox(height: BalviaTheme.spaceXs),
        Text(
          'Cuántos días dura cada seguimiento. Entre 28 y 31.',
          style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: BalviaTheme.spaceMd),

        _DeferredChangeBanner(settings: settings),
        const SizedBox(height: BalviaTheme.spaceLg),

        Text(
          'DÍA DE INICIO',
          style: BalviaTheme.overlineStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: BalviaTheme.spaceSm),
        // Read-only on purpose: the rollover always starts the next period the
        // day after the previous one ends, so this value is recorded but does
        // not steer anything yet. Showing it as editable would be a lie.
        ListTile(
          enabled: false,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.event_outlined, color: cs.onSurfaceVariant),
          title: Text('Día ${settings.trackingStartDay}'),
          subtitle: const Text(
            'Se ajusta automáticamente: cada seguimiento empieza al día '
            'siguiente de que termina el anterior.',
          ),
        ),
        const SizedBox(height: BalviaTheme.spaceLg),

        FilledButton(
          onPressed: (!dirty || _saving)
              ? null
              : () => _confirmAndSave(settings, duration),
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar cambios'),
        ),
      ],
    );
  }

  Future<void> _confirmAndSave(UserSettings settings, int duration) async {
    final cutoff = settings.activePeriodEndDate;
    final nextStart = settings.nextPeriodStartDate;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar la duración'),
        content: Text(
          cutoff == null
              ? 'Tus seguimientos pasarán a durar $duration días. El cambio '
                    'aplica al próximo seguimiento.'
              : 'Tus seguimientos pasarán a durar $duration días.\n\n'
                    'Tu seguimiento actual termina el ${longDate(cutoff)} y no '
                    'se modifica. La nueva duración se usa desde el que empieza '
                    'el ${longDate(nextStart!)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _saving = true);

    try {
      await ref
          .read(userSettingsRepositoryProvider)
          .update(trackingDurationDays: duration);
      ref.invalidate(userSettingsProvider);
      if (mounted) setState(() => _selectedDuration = null);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            nextStart == null
                ? 'Se aplicará al próximo seguimiento'
                : 'Se aplicará desde el seguimiento que empieza el '
                      '${longDate(nextStart)}',
          ),
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Active period card
// ---------------------------------------------------------------------------

class _ActivePeriodCard extends StatelessWidget {
  const _ActivePeriodCard({required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final end = settings.activePeriodEndDate;

    return Card(
      margin: EdgeInsets.zero,
      color: BalviaTheme.surfaceTonal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(BalviaTheme.spaceMd),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: BalviaTheme.seed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
              ),
              child: const Icon(
                Icons.timer_outlined,
                color: BalviaTheme.seed,
                size: 20,
              ),
            ),
            const SizedBox(width: BalviaTheme.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seguimiento actual',
                    style: BalviaTheme.bodyStyle(
                      color: cs.onSurface,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    end == null
                        ? 'Sin seguimiento activo'
                        : 'Termina el ${longDate(end)} · '
                              '${settings.trackingDurationDays} días',
                    style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Deferred-change banner
// ---------------------------------------------------------------------------

class _DeferredChangeBanner extends StatelessWidget {
  const _DeferredChangeBanner({required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context) {
    final end = settings.activePeriodEndDate;
    final next = settings.nextPeriodStartDate;

    return Container(
      padding: const EdgeInsets.all(BalviaTheme.spaceMd),
      decoration: BoxDecoration(
        color: BalviaTheme.budgetWarning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
        border: Border.all(
          color: BalviaTheme.budgetWarning.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: BalviaTheme.budgetWarning,
            size: 18,
          ),
          const SizedBox(width: BalviaTheme.spaceSm),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: BalviaTheme.captionStyle(
                  color: BalviaTheme.budgetWarning.withValues(alpha: 0.9),
                ),
                children: [
                  const TextSpan(
                    text: 'Los cambios aplican al próximo seguimiento. ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (end == null)
                    const TextSpan(
                      text:
                          'Tu seguimiento actual no se modifica; la nueva '
                          'duración se usa a partir del siguiente.',
                    )
                  else ...[
                    const TextSpan(text: 'Tu seguimiento actual termina el '),
                    TextSpan(
                      text: longDate(end),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(
                      text: ' y no se modifica. La nueva duración ',
                    ),
                    TextSpan(text: 'se usa desde el ${longDate(next!)}.'),
                  ],
                ],
              ),
            ),
          ),
        ],
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
