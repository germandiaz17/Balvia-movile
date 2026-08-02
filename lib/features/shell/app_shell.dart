import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/models/account.dart';
import '../transactions/quick_capture_modal.dart';

/// Persistent shell with 4 tabs + central FAB (design brief §4).
///
/// Tab layout (StatefulShellRoute branches):
///   0 → Inicio (dashboard)
///   1 → Transacciones (historial)
///   [FAB] → captura rápida (abre modal desde cualquier tab)
///   2 → Presupuestos
///   3 → Perfil/Más
///
/// The bottom bar uses BottomAppBar with floatingActionButtonLocation centered
/// (notched dock style). Two destinations on each side of the FAB.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: navigationShell,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _CentralFab(navigationShell: navigationShell),
      bottomNavigationBar: _BottomBar(navigationShell: navigationShell),
    );
  }
}

// ---------------------------------------------------------------------------
// Central FAB — opens quick-capture modal
// ---------------------------------------------------------------------------

class _CentralFab extends ConsumerWidget {
  const _CentralFab({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FloatingActionButton(
      heroTag: 'fab_quick_capture_shell',
      tooltip: 'Registrar gasto',
      shape: const CircleBorder(),
      onPressed: () => _openCapture(context, ref),
      child: const Icon(Icons.add, size: 28),
    );
  }

  Future<void> _openCapture(BuildContext context, WidgetRef ref) async {
    // Fetch accounts; if not ready use empty list (modal handles it gracefully).
    final accounts = await ref
        .read(accountRepositoryProvider)
        .list()
        .catchError((_) => <Account>[]);

    if (!context.mounted) return;
    final saved = await showQuickCaptureModal(context, ref, accounts: accounts);
    if (saved && context.mounted) {
      // Invalidate all downstream providers so the Dashboard and Transactions
      // tabs pick up the new transaction immediately.
      ref.invalidate(activeTrackingPeriodProvider);
      ref.invalidate(periodSummaryProvider);
      ref.invalidate(recentTransactionsProvider);
      ref.invalidate(allTransactionsProvider);
      ref.invalidate(budgetsProvider);
      ref.invalidate(insightsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gasto registrado'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Bottom bar with notched center
// ---------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = navigationShell.currentIndex;

    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 6,
      color: cs.surface,
      elevation: 8,
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Left side: Inicio, Transacciones.
          _NavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: 'Inicio',
            selected: idx == 0,
            onTap: () => _go(0),
          ),
          _NavItem(
            icon: Icons.receipt_long_outlined,
            activeIcon: Icons.receipt_long,
            label: 'Transacciones',
            selected: idx == 1,
            onTap: () => _go(1),
          ),
          // Gap for FAB.
          const SizedBox(width: 64),
          // Right side: Presupuestos, Perfil.
          _NavItem(
            icon: Icons.pie_chart_outline,
            activeIcon: Icons.pie_chart,
            label: 'Presupuestos',
            selected: idx == 2,
            onTap: () => _go(2),
          ),
          _NavItem(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Perfil',
            selected: idx == 3,
            onTap: () => _go(3),
          ),
        ],
      ),
    );
  }

  void _go(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.primary : cs.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? activeIcon : icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
