import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/theme.dart';
import '../../core/theme_mode_provider.dart';
import '../../data/models/user.dart';
import '../auth/auth_controller.dart';

// ---------------------------------------------------------------------------
// ProfileScreen — mockup 19
// ---------------------------------------------------------------------------

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Perfil'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
        actions: [
          // Bell icon — no action yet (placeholder per mockup).
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notificaciones',
            onPressed: null,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // ---- Teal header card ----
          _ProfileHeader(user: user),

          const SizedBox(height: BalviaTheme.spaceMd),

          // ---- HERRAMIENTAS section ----
          _SectionLabel(label: 'HERRAMIENTAS'),

          _ProfileTile(
            iconColor: const Color(0xFF26A69A), // teal
            iconBg: const Color(0xFFE0F2F1),
            icon: Icons.account_balance_wallet_outlined,
            title: 'Cuentas',
            onTap: () => context.push('/accounts'),
          ),
          _ProfileTile(
            iconColor: const Color(0xFF7E57C2), // purple
            iconBg: const Color(0xFFEDE7F6),
            icon: Icons.category_outlined,
            title: 'Categorías',
            onTap: () => context.push('/categories'),
          ),
          _DisabledProfileTile(
            iconColor: const Color(0xFFFFA726), // amber
            iconBg: const Color(0xFFFFF3E0),
            icon: Icons.timer_outlined,
            title: 'Configuración del seguimiento',
          ),
          _DisabledProfileTile(
            iconColor: const Color(0xFF42A5F5), // blue
            iconBg: const Color(0xFFE3F2FD),
            icon: Icons.savings_outlined,
            title: 'Metas de ahorro',
          ),
          _DisabledProfileTile(
            iconColor: const Color(0xFF66BB6A), // green
            iconBg: const Color(0xFFE8F5E9),
            icon: Icons.repeat_outlined,
            title: 'Transacciones recurrentes',
          ),

          const SizedBox(height: BalviaTheme.spaceMd),

          // ---- PREFERENCIAS section ----
          _SectionLabel(label: 'PREFERENCIAS'),

          _AppearanceTile(),

          _DisabledProfileTile(
            iconColor: const Color(0xFF26A69A),
            iconBg: const Color(0xFFE0F2F1),
            icon: Icons.shield_outlined,
            title: 'Seguridad y privacidad',
          ),
          _DisabledProfileTile(
            iconColor: const Color(0xFFEF5350),
            iconBg: const Color(0xFFFFEBEE),
            icon: Icons.help_outline,
            title: 'Ayuda y soporte',
          ),

          const SizedBox(height: BalviaTheme.spaceMd),

          // ---- CUENTA section ----
          _SectionLabel(label: 'CUENTA'),

          // Cerrar sesión — red.
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: BalviaTheme.spaceMd,
              vertical: 2,
            ),
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
              ),
              child: Icon(
                Icons.logout,
                size: 18,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            title: Text(
              'Cerrar sesión',
              style: BalviaTheme.bodyStyle(
                color: Theme.of(context).colorScheme.error,
              ).copyWith(fontWeight: FontWeight.w500),
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
// Teal profile header
// ---------------------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({this.user});
  final User? user;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(user);

    return Container(
      width: double.infinity,
      color: BalviaTheme.seed,
      padding: const EdgeInsets.fromLTRB(
        BalviaTheme.spaceMd,
        BalviaTheme.spaceMd,
        BalviaTheme.spaceMd,
        BalviaTheme.spaceLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Translucent circle avatar with initial.
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white.withValues(alpha: 0.25),
            child: Text(
              initials,
              style: BalviaTheme.titleStyle(color: Colors.white).copyWith(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),

          // Full name.
          if (user?.fullName != null && user!.fullName!.isNotEmpty)
            Text(
              user!.fullName!,
              style: BalviaTheme.titleStyle(color: Colors.white),
            ),

          // Email.
          Text(
            user?.email ?? '',
            style: BalviaTheme.captionStyle(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: BalviaTheme.spaceSm),

          // Plan badge pill.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(100),
            ),
            child: const Text(
              '★ Plan Free',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: BalviaTheme.spaceXs),

          // "Mejorar a Pro" link — dead (no action yet).
          GestureDetector(
            onTap: null,
            child: Text(
              'Mejorar a Pro ›',
              style: BalviaTheme.captionStyle(
                color: Colors.white.withValues(alpha: 0.9),
              ).copyWith(decoration: TextDecoration.underline),
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
// Section label overline
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BalviaTheme.spaceMd,
        BalviaTheme.spaceSm,
        BalviaTheme.spaceMd,
        4,
      ),
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
// Profile tile — active
// ---------------------------------------------------------------------------

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.iconColor,
    required this.iconBg,
    required this.icon,
    required this.title,
    this.onTap,
  });

  final Color iconColor;
  final Color iconBg;
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BalviaTheme.spaceMd,
        vertical: 2,
      ),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
      title: Text(
        title,
        style: BalviaTheme.bodyStyle(color: cs.onSurface),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: cs.onSurfaceVariant,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Disabled tile ("Próximamente")
// ---------------------------------------------------------------------------

class _DisabledProfileTile extends StatelessWidget {
  const _DisabledProfileTile({
    required this.iconColor,
    required this.iconBg,
    required this.icon,
    required this.title,
  });

  final Color iconColor;
  final Color iconBg;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      enabled: false,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BalviaTheme.spaceMd,
        vertical: 2,
      ),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconBg.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
        ),
        child: Icon(icon, size: 18, color: iconColor.withValues(alpha: 0.4)),
      ),
      title: Text(
        title,
        style: BalviaTheme.bodyStyle(
          color: cs.onSurface.withValues(alpha: 0.38),
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(
            color: cs.outline.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Próximamente',
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
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
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BalviaTheme.spaceMd,
        vertical: 2,
      ),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(BalviaTheme.radiusSm),
        ),
        child: const Icon(
          Icons.palette_outlined,
          size: 18,
          color: Color(0xFFFFA726),
        ),
      ),
      title: Text(
        'Apariencia',
        style: BalviaTheme.bodyStyle(color: cs.onSurface),
      ),
      subtitle: Text(
        _modeLabel(current),
        style: BalviaTheme.captionStyle(color: cs.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
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
