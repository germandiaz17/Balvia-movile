import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accounts/accounts_screen.dart';
import '../features/ai/ai_settings_screen.dart';
import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/home/home_screen.dart';
import '../features/overlay/overlay_settings_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/recurring/recurring_transactions_screen.dart';
import '../features/savings_goals/savings_goals_screen.dart';
import '../features/settings/tracking_settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/transactions/transactions_screen.dart';

/// App router. Redirects based on auth status; refreshes whenever it changes.
///
/// Shell principal (4 tabs + central FAB, design brief §4):
///   /home          → Tab 0: Inicio (dashboard + accounts + quick capture)
///   /transactions  → Tab 1: Transacciones (full transaction list)
///   [FAB]          → Captura rápida (modal, no tab)
///   /budgets       → Tab 2: Presupuestos
///   /profile       → Tab 3: Perfil/Más
///
/// Push routes (no bottom nav):
///   /categories    → Gestión de categorías (from Profile or Transactions)
///   /accounts      → Gestión de cuentas (from Profile)
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authControllerProvider).status;
      final loc = state.matchedLocation;
      final atAuth = loc == '/login' || loc == '/register';
      final atSplash = loc == '/';

      if (status == AuthStatus.unknown) {
        return atSplash ? null : '/';
      }
      if (status == AuthStatus.unauthenticated) {
        return atAuth ? null : '/login';
      }
      // authenticated → send splash/auth screens to home tab.
      if (atAuth || atSplash) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),

      // Push routes (displayed on top of the shell, no bottom nav).
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
      GoRoute(path: '/accounts', builder: (_, _) => const AccountsScreen()),
      GoRoute(
        path: '/overlay-settings',
        builder: (_, _) => const OverlaySettingsScreen(),
      ),
      GoRoute(
        path: '/ai-settings',
        builder: (_, _) => const AiSettingsScreen(),
      ),
      GoRoute(
        path: '/savings-goals',
        builder: (_, _) => const SavingsGoalsScreen(),
      ),
      GoRoute(
        path: '/recurring',
        builder: (_, _) => const RecurringTransactionsScreen(),
      ),
      GoRoute(
        path: '/tracking-settings',
        builder: (_, _) => const TrackingSettingsScreen(),
      ),
      // Dashboard is accessed through the shell at /home (Tab 0 replaces
      // the old /dashboard). The old route is kept for backward compat.
      GoRoute(path: '/dashboard', builder: (_, _) => const HomeScreen()),

      // Four-tab shell: Inicio, Transacciones, Presupuestos, Perfil.
      // The central FAB lives in AppShell (not a branch).
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // Tab 0 — Inicio
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          // Tab 1 — Transacciones
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/transactions',
                builder: (_, _) => const TransactionsScreen(),
              ),
            ],
          ),
          // Tab 2 — Presupuestos
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/budgets',
                builder: (_, _) => const BudgetsScreen(),
              ),
            ],
          ),
          // Tab 3 — Perfil/Más
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
