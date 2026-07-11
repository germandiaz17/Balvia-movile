import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/theme_mode_provider.dart';
import '../../data/models/user.dart';
import '../auth/auth_controller.dart';

// ---------------------------------------------------------------------------
// ProfileScreen
// ---------------------------------------------------------------------------

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Header card — avatar, name, email, plan badge.
          _UserHeader(user: user),
          const SizedBox(height: 8),

          // ---- Cuentas ----
          _SectionTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Cuentas',
            subtitle: 'Gestiona tus cuentas y saldos',
            onTap: () => context.push('/accounts'),
          ),

          // ---- Categorías ----
          _SectionTile(
            icon: Icons.category_outlined,
            title: 'Categorías',
            subtitle: 'Organiza tus gastos e ingresos',
            onTap: () => context.push('/categories'),
          ),

          // ---- Apariencia ----
          _AppearanceTile(),

          const Divider(indent: 16, endIndent: 16),

          // ---- Coming soon items ----
          _DisabledSectionTile(
            icon: Icons.flag_outlined,
            title: 'Metas de ahorro',
          ),
          _DisabledSectionTile(
            icon: Icons.repeat_outlined,
            title: 'Transacciones recurrentes',
          ),
          _DisabledSectionTile(
            icon: Icons.tune_outlined,
            title: 'Configuración del seguimiento',
          ),
          _DisabledSectionTile(
            icon: Icons.star_outline,
            title: 'Planes y suscripción',
          ),
          _DisabledSectionTile(icon: Icons.lock_outline, title: 'Seguridad'),

          const Divider(indent: 16, endIndent: 16),

          // ---- Cerrar sesión ----
          ListTile(
            leading: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Cerrar sesión',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres cerrar sesión?'),
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
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// User header card
// ---------------------------------------------------------------------------

class _UserHeader extends StatelessWidget {
  const _UserHeader({this.user});
  final User? user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final initials = _initials(user);

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: cs.primaryContainer,
            child: Text(
              initials,
              style: theme.textTheme.titleLarge?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (user?.fullName != null && user!.fullName!.isNotEmpty)
                  Text(
                    user!.fullName!,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                Text(
                  user?.email ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                // Plan badge — hardcoded Free until paywall feature exists.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Plan Free',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials(User? user) {
    if (user == null) return '?';
    final name = user.fullName;
    if (name != null && name.isNotEmpty) {
      final parts = name.trim().split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return parts[0][0].toUpperCase();
    }
    return user.email[0].toUpperCase();
  }
}

// ---------------------------------------------------------------------------
// Section tile
// ---------------------------------------------------------------------------

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Disabled / "coming soon" tile
// ---------------------------------------------------------------------------

class _DisabledSectionTile extends StatelessWidget {
  const _DisabledSectionTile({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
      title: Text(
        title,
        style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Próximamente',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      enabled: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance tile — inline theme picker
// ---------------------------------------------------------------------------

class _AppearanceTile extends ConsumerWidget {
  const _AppearanceTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeAsync = ref.watch(themeModeProvider);
    final current = themeAsync.value ?? ThemeMode.system;

    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('Apariencia'),
      subtitle: Text(_modeLabel(current)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showThemePicker(context, ref, current),
    );
  }

  String _modeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Según el sistema',
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Oscuro',
  };

  void _showThemePicker(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => _ThemePickerSheet(current: current),
    );
  }
}

class _ThemePickerSheet extends ConsumerWidget {
  const _ThemePickerSheet({required this.current});
  final ThemeMode current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text('Apariencia', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...ThemeMode.values.map(
            (mode) => ListTile(
              leading: Icon(_modeIcon(mode)),
              title: Text(_modeLabel(mode)),
              trailing: current == mode
                  ? Icon(Icons.check, color: cs.primary)
                  : null,
              onTap: () async {
                await ref.read(themeModeProvider.notifier).setMode(mode);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _modeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Según el sistema',
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Oscuro',
  };

  IconData _modeIcon(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };
}
