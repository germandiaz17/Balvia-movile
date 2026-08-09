import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/period_math.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/models/user_settings.dart';

// ---------------------------------------------------------------------------
// Screen
//
// Domain rule 8: a change to the tracking configuration applies to the NEXT
// seguimiento, never to the one currently running. That is the whole UX problem
// here — a user who changes something and sees today's period unchanged will
// think it did not save. So the cut-off date is stated up front in a fixed
// banner (not a SnackBar that scrolls away), repeated in the confirmation
// dialog, and repeated again on success.
//
// Switching to calendar months adds a second thing to explain: the gap between
// the current period's end and the 1st of a month becomes a one-off transition
// period. Users are told its exact dates before they commit, because finding an
// unexplained 27-day seguimiento later is alarming.
// ---------------------------------------------------------------------------

class TrackingSettingsScreen extends ConsumerStatefulWidget {
  const TrackingSettingsScreen({super.key});

  @override
  ConsumerState<TrackingSettingsScreen> createState() =>
      _TrackingSettingsScreenState();
}

class _TrackingSettingsScreenState
    extends ConsumerState<TrackingSettingsScreen> {
  /// Pending selections, null until the user touches the corresponding control.
  int? _selectedDuration;
  String? _selectedMode;
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
    final mode = _selectedMode ?? settings.trackingPeriodMode;
    final dirty =
        duration != settings.trackingDurationDays ||
        mode != settings.trackingPeriodMode;
    final isCalendar = mode == kPeriodModeCalendar;

    return ListView(
      padding: const EdgeInsets.all(BalviaTheme.spaceMd),
      children: [
        _ActivePeriodCard(settings: settings),
        const SizedBox(height: BalviaTheme.spaceLg),

        Text(
          'CÓMO SE CUENTAN TUS SEGUIMIENTOS',
          style: BalviaTheme.overlineStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: BalviaTheme.spaceSm),
        _ModeOption(
          value: kPeriodModeCalendar,
          groupValue: mode,
          icon: Icons.calendar_month_outlined,
          title: 'Mes calendario',
          subtitle:
              'Del día 1 al último día de cada mes. Para quien piensa y cobra '
              'por mes.',
          onChanged: _saving ? null : (v) => setState(() => _selectedMode = v),
        ),
        const SizedBox(height: BalviaTheme.spaceSm),
        _ModeOption(
          value: kPeriodModeRolling,
          groupValue: mode,
          icon: Icons.timelapse_outlined,
          title: 'Ciclo personalizado',
          subtitle:
              'Bloques de una duración fija, encadenados. Para quien no cobra '
              'en fechas de calendario.',
          onChanged: _saving ? null : (v) => setState(() => _selectedMode = v),
        ),

        // The duration only means something in rolling mode: a calendar month
        // is as long as the month is. Showing the selector anyway would invite
        // the user to set a number that quietly does nothing.
        if (!isCalendar) ...[
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
        ],
        const SizedBox(height: BalviaTheme.spaceMd),

        _DeferredChangeBanner(
          settings: settings,
          pendingMode: mode,
          pendingDuration: duration,
        ),
        const SizedBox(height: BalviaTheme.spaceLg),

        if (!isCalendar) ...[
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
        ],

        FilledButton(
          onPressed: (!dirty || _saving)
              ? null
              : () => _confirmAndSave(settings, mode, duration),
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

  Future<void> _confirmAndSave(
    UserSettings settings,
    String mode,
    int duration,
  ) async {
    final modeChanged = mode != settings.trackingPeriodMode;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          modeChanged
              ? 'Cambiar el tipo de seguimiento'
              : 'Cambiar la duración',
        ),
        content: Text(
          _changeSummary(settings: settings, mode: mode, duration: duration),
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
      // Send only what changed: the backend update is a COALESCE partial, so an
      // absent key leaves the column alone.
      final updated = await ref
          .read(userSettingsRepositoryProvider)
          .update(
            trackingPeriodMode: modeChanged ? mode : null,
            trackingDurationDays: duration != settings.trackingDurationDays
                ? duration
                : null,
          );
      ref.invalidate(userSettingsProvider);
      if (mounted) {
        setState(() {
          _selectedDuration = null;
          _selectedMode = null;
        });
      }

      // The backend reshapes a pristine first period on the spot instead of
      // deferring, and says so. Reporting "applies later" in that case would be
      // plainly wrong.
      final nextStart = updated.nextPeriodStartDate;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            !updated.appliesToNextPeriod
                ? 'Listo, tu seguimiento actual ya usa el nuevo formato'
                : nextStart == null
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
// Shared copy
//
// One place builds the sentence describing a pending change, so the banner, the
// confirmation dialog and any future surface cannot drift apart.
// ---------------------------------------------------------------------------

/// Describes what the NEXT period will look like under [mode] and [duration].
///
/// Deliberately phrased around the outcome rather than around "what changed",
/// so the same sentence is true whether the user has a pending edit or is just
/// looking at their settled configuration. Wording it as a diff produced copy
/// that talked about "the new duration" to someone on calendar months, where
/// duration means nothing at all.
String _changeSummary({
  required UserSettings settings,
  required String mode,
  required int duration,
}) {
  final end = settings.activePeriodEndDate;
  final isCalendar = mode == kPeriodModeCalendar;

  if (end == null) {
    return isCalendar
        ? 'Tus seguimientos serán meses calendario, del día 1 al último día '
              'de cada mes.'
        : 'Tus seguimientos durarán $duration días.';
  }

  final buffer = StringBuffer(
    'Tu seguimiento actual termina el ${longDate(end)} y no se modifica.\n\n',
  );
  final next = nextPeriodRange(
    prevEnd: end,
    mode: mode,
    durationDays: duration,
  );

  if (!isCalendar) {
    buffer.write(
      'Desde el ${longDate(next.start)}, cada seguimiento durará $duration '
      'días.',
    );
    return buffer.toString();
  }

  if (!next.isTransition) {
    buffer.write(
      'Desde el ${longDate(next.start)} tus seguimientos serán meses '
      'calendario completos.',
    );
    return buffer.toString();
  }

  // The gap up to the 1st becomes a one-off bridge — name its exact dates.
  final firstFullMonth = next.end.add(const Duration(days: 1));
  buffer
    ..write(
      'Del ${longDate(next.start)} al ${longDate(next.end)} tendrás un '
      'seguimiento de transición de ${next.durationDays} días, ',
    )
    ..write(
      'y desde el ${longDate(firstFullMonth)} tus seguimientos serán meses '
      'calendario completos.',
    );
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Mode option
// ---------------------------------------------------------------------------

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final String value;
  final String groupValue;
  final IconData icon;
  final String title;
  final String subtitle;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = value == groupValue;

    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(value),
      borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(BalviaTheme.spaceMd),
        decoration: BoxDecoration(
          color: selected
              ? BalviaTheme.seed.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
          border: Border.all(
            color: selected
                ? BalviaTheme.seed
                : cs.outlineVariant.withValues(alpha: 0.6),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? BalviaTheme.seed : cs.onSurfaceVariant,
            ),
            const SizedBox(width: BalviaTheme.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: BalviaTheme.bodyStyle(color: cs.onSurface).copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, size: 20, color: BalviaTheme.seed),
          ],
        ),
      ),
    );
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
                        : settings.usesCalendarMonths
                        ? 'Termina el ${longDate(end)}'
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
  const _DeferredChangeBanner({
    required this.settings,
    required this.pendingMode,
    required this.pendingDuration,
  });

  final UserSettings settings;
  final String pendingMode;
  final int pendingDuration;

  @override
  Widget build(BuildContext context) {
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
                  TextSpan(
                    text: _changeSummary(
                      settings: settings,
                      mode: pendingMode,
                      duration: pendingDuration,
                    ).replaceAll('\n\n', ' '),
                  ),
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
