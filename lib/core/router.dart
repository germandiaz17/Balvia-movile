import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/budgets/budgets_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
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
      GoRoute(path: '/', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),

      // Push routes (displayed on top of the shell, no bottom nav).
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
      GoRoute(path: '/accounts', builder: (_, _) => const _AccountsPage()),
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

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Thin wrapper: re-uses the existing HomeScreen account management UI.
/// Full accounts screen (design brief §5.8) is a post-MVP task.
class _AccountsPage extends StatelessWidget {
  const _AccountsPage();

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
