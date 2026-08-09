import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/amount_formatter.dart';
import '../../core/api_error.dart';
import '../../core/providers.dart';
import '../../core/sync_providers.dart';
import '../../core/theme.dart';
import '../../data/models/account.dart';
import '../../data/models/tracking_period.dart';
import '../../data/models/user_settings.dart'
    show kPeriodModeCalendar, kPeriodModeRolling, longDate;
import 'onboarding_controller.dart';

/// Accounts read over the network rather than from Drift.
///
/// The wizard runs seconds after registration, before the first sync pull has
/// necessarily landed, so the local DB is very likely still empty. The rest of
/// the app reads accounts from Drift (`localAccountsProvider`) — this is the
/// deliberate exception.
final onboardingAccountsProvider = FutureProvider.autoDispose<List<Account>>(
  (ref) => ref.read(accountRepositoryProvider).list(),
);

/// First-run wizard, shown once right after registration.
///
/// It exists because registering used to drop the user straight on /home with
/// no explanation of the seguimiento — the one concept the whole app is built
/// around — and, before the backend provisioned a default account, with nothing
/// to charge an expense to either.
///
/// Three steps: what a seguimiento is (with the user's real dates), the opening
/// balance of their first account, and where the capture button lives. Every
/// step is skippable: the backend guarantees a usable account exists, so
/// nothing here is required for the app to work.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 3;

  final _pageController = PageController();
  final _nameController = TextEditingController(text: 'Efectivo');

  /// Raw digits, no separators — same convention as quick capture.
  String _balanceDigits = '';

  int _step = 0;
  bool _saving = false;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(onboardingControllerProvider.notifier).complete();
    // The router redirect sends us to /home as soon as the flag clears.
  }

  void _goTo(int step) {
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Persists the first account, then advances. A failure keeps the user on
  /// the step with the reason shown, rather than swallowing it — but the
  /// "Omitir" escape hatch stays available.
  Future<void> _saveAccountAndContinue(Account? existing) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _snack('Ponle un nombre a la cuenta.');
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(accountRepositoryProvider);
      // Digits-only, so "0" when left empty — a valid opening balance.
      final opening = _balanceDigits.isEmpty ? '0' : _balanceDigits;

      if (existing != null) {
        await repo.update(
          existing.id,
          name: name,
          accountType: existing.accountType,
          // Echoed back, not defaulted: the PUT is a full replace, so omitting
          // these would wipe the icon the backend seeded the account with.
          icon: existing.icon,
          color: existing.color,
          initialBalance: opening,
        );
      } else {
        // No default account (a user who registered before the backend started
        // provisioning one, or a failed sync). Create it instead.
        await repo.create(
          name: name,
          accountType: 'cash',
          initialBalance: opening,
        );
      }
      // Pull the new account down into Drift, which is what the rest of the
      // app reads from.
      ref.read(syncControllerProvider.notifier).syncInBackground();
      ref.invalidate(onboardingAccountsProvider);
      if (mounted) _goTo(2);
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: _step > 0 && !_saving
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _goTo(_step - 1),
              )
            : null,
        actions: [
          if (_step < _stepCount - 1)
            TextButton(
              onPressed: _saving ? null : _finish,
              child: const Text('Omitir'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  const _PeriodStep(),
                  _AccountStep(
                    nameController: _nameController,
                    balanceDigits: _balanceDigits,
                    saving: _saving,
                    onBalanceChanged: (digits) =>
                        setState(() => _balanceDigits = digits),
                    onContinue: _saveAccountAndContinue,
                  ),
                  const _ReadyStep(),
                ],
              ),
            ),
            _StepDots(current: _step, total: _stepCount),
            const SizedBox(height: BalviaTheme.spaceMd),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BalviaTheme.spaceLg,
                0,
                BalviaTheme.spaceLg,
                BalviaTheme.spaceLg,
              ),
              child: _primaryAction(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primaryAction() {
    // The account step owns its own button: it needs the loaded account to
    // decide between update and create.
    if (_step == 1) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _saving ? null : (_step == 0 ? () => _goTo(1) : _finish),
        child: Text(
          _step == 0 ? 'Entendido' : 'Empezar',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — what a seguimiento is
// ---------------------------------------------------------------------------

class _PeriodStep extends ConsumerStatefulWidget {
  const _PeriodStep();

  @override
  ConsumerState<_PeriodStep> createState() => _PeriodStepState();
}

class _PeriodStepState extends ConsumerState<_PeriodStep> {
  bool _saving = false;

  /// Switching here is free of the usual "applies next period" caveat: the
  /// backend reshapes a first period that has no transactions yet, and at this
  /// point in the wizard there cannot be any. So the dates card below updates
  /// immediately and the user never meets a transition period.
  Future<void> _selectMode(String mode) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(userSettingsRepositoryProvider)
          .update(trackingPeriodMode: mode);
      ref.invalidate(userSettingsProvider);
      ref.invalidate(activeTrackingPeriodProvider);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(apiErrorMessage(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final periodAsync = ref.watch(activeTrackingPeriodProvider);
    final settingsAsync = ref.watch(userSettingsProvider);
    final mode =
        settingsAsync.asData?.value.trackingPeriodMode ?? kPeriodModeRolling;

    return _StepScaffold(
      icon: Icons.calendar_month_outlined,
      title: 'Tus finanzas por seguimientos',
      body:
          'Balvia organiza tu plata por "seguimientos": el bloque de tiempo '
          'donde viven tus gastos, presupuestos y análisis. Cuando uno termina '
          'se cierra solo y el siguiente arranca enseguida.\n\n'
          'Elige cómo quieres contarlos (puedes cambiarlo después):',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OnboardingModeChip(
            label: 'Mes calendario',
            hint: 'Del 1 al último día de cada mes',
            selected: mode == kPeriodModeCalendar,
            enabled: !_saving,
            onTap: () => _selectMode(kPeriodModeCalendar),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),
          _OnboardingModeChip(
            label: 'Ciclo personalizado',
            hint: 'Bloques de 28 a 31 días desde hoy',
            selected: mode == kPeriodModeRolling,
            enabled: !_saving,
            onTap: () => _selectMode(kPeriodModeRolling),
          ),
          const SizedBox(height: BalviaTheme.spaceMd),
          periodAsync.when(
            // The dates are the point of this screen, but they are not worth
            // blocking on: a spinner or a silent absence both beat an error page.
            loading: () => const SizedBox(
              height: 72,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (_, _) => const SizedBox.shrink(),
            data: (period) => _PeriodDatesCard(period: period, colorScheme: cs),
          ),
        ],
      ),
    );
  }
}

class _OnboardingModeChip extends StatelessWidget {
  const _OnboardingModeChip({
    required this.label,
    required this.hint,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BalviaTheme.spaceMd,
          vertical: BalviaTheme.spaceSm,
        ),
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
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 20,
              color: selected ? BalviaTheme.seed : cs.onSurfaceVariant,
            ),
            const SizedBox(width: BalviaTheme.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: BalviaTheme.bodyStyle(color: cs.onSurface).copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  Text(
                    hint,
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

class _PeriodDatesCard extends StatelessWidget {
  const _PeriodDatesCard({required this.period, required this.colorScheme});

  final TrackingPeriod period;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.parse(period.startDate);
    final end = DateTime.parse(period.endDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(BalviaTheme.spaceMd),
      decoration: BoxDecoration(
        color: BalviaTheme.surfaceTonal,
        borderRadius: BorderRadius.circular(BalviaTheme.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TU PRIMER SEGUIMIENTO',
            style: BalviaTheme.overlineStyle(color: BalviaTheme.inkMuted),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),
          Text(
            'Del ${longDate(start)} al ${longDate(end)}',
            style: BalviaTheme.bodyStyle(
              color: colorScheme.onSurface,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: BalviaTheme.spaceXs),
          Text(
            period.isWholeCalendarMonth
                ? '${period.durationDays} días · mes completo'
                : '${period.durationDays} días',
            style: BalviaTheme.captionStyle(color: BalviaTheme.inkMuted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — the first account
// ---------------------------------------------------------------------------

class _AccountStep extends ConsumerWidget {
  const _AccountStep({
    required this.nameController,
    required this.balanceDigits,
    required this.saving,
    required this.onBalanceChanged,
    required this.onContinue,
  });

  final TextEditingController nameController;
  final String balanceDigits;
  final bool saving;
  final ValueChanged<String> onBalanceChanged;
  final Future<void> Function(Account? existing) onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(onboardingAccountsProvider);
    // Registration provisions exactly one account; anything else means the user
    // got here some other way, and we edit the first one rather than guess.
    final existing = accountsAsync.asData?.value.firstOrNull;

    return _StepScaffold(
      icon: Icons.account_balance_wallet_outlined,
      title: '¿Cuánto tienes ahora?',
      body:
          'Te creamos una cuenta de efectivo para que puedas registrar gastos '
          'de una vez. Dale el nombre que quieras y dinos con cuánto arrancas.',
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'NOMBRE DE LA CUENTA',
            style: BalviaTheme.overlineStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: BalviaTheme.spaceXs),
          TextField(
            controller: nameController,
            enabled: !saving,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Efectivo',
              border: OutlineInputBorder(),
              filled: true,
            ),
          ),
          const SizedBox(height: BalviaTheme.spaceMd),

          Text(
            'SALDO INICIAL',
            style: BalviaTheme.overlineStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: BalviaTheme.spaceXs),
          TextField(
            enabled: !saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: onBalanceChanged,
            decoration: InputDecoration(
              prefixText: '\$ ',
              hintText: '0',
              border: const OutlineInputBorder(),
              filled: true,
              helperText: balanceDigits.isEmpty
                  ? 'Puedes dejarlo en cero y ajustarlo después.'
                  : AmountFormatter.formatDisplay(balanceDigits),
            ),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),
          Text(
            'El saldo inicial solo se puede cambiar mientras la cuenta no '
            'tenga movimientos.',
            style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: BalviaTheme.spaceLg),

          FilledButton(
            onPressed: saving ? null : () => onContinue(existing),
            child: saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Continuar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — where to capture
// ---------------------------------------------------------------------------

class _ReadyStep extends StatelessWidget {
  const _ReadyStep();

  @override
  Widget build(BuildContext context) {
    return const _StepScaffold(
      icon: Icons.bolt_outlined,
      title: 'Listo para registrar',
      body:
          'El botón central de la barra inferior abre la captura rápida: monto, '
          'categoría y listo, en menos de cinco segundos.\n\nLa IA te sugiere '
          'la categoría si configuras tu propia API key en Perfil. Y la burbuja '
          'flotante te deja registrar sin abrir la app.',
    );
  }
}

// ---------------------------------------------------------------------------
// Shared step chrome
// ---------------------------------------------------------------------------

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.icon,
    required this.title,
    required this.body,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: BalviaTheme.spaceLg,
        vertical: BalviaTheme.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(BalviaTheme.radiusXl),
              ),
              child: Icon(icon, size: 36, color: cs.primary),
            ),
          ),
          const SizedBox(height: BalviaTheme.spaceLg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: BalviaTheme.headlineStyle(color: cs.onSurface),
          ),
          const SizedBox(height: BalviaTheme.spaceMd),
          Text(
            body,
            textAlign: TextAlign.center,
            style: BalviaTheme.bodyStyle(color: BalviaTheme.inkMuted),
          ),
          if (extra != null) ...[
            const SizedBox(height: BalviaTheme.spaceLg),
            extra!,
          ],
        ],
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? cs.primary : cs.outlineVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
