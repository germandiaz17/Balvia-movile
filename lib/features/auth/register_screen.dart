import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/theme.dart';
import 'auth_controller.dart';
import '../../shared/balvia_logo.dart';

/// Register screen (mockup 11).
///
/// Layout: logo centered, "Crea tu cuenta", fields (nombre/email/password),
/// password strength bar + segments, helper text, terms checkbox (UI only),
/// "Crear cuenta" button, "Inicia sesión" link.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _termsAccepted = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .register(_email.text.trim(), _password.text, _fullName.text.trim());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strength = passwordStrength(_password.text);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: BalviaTheme.spaceLg,
            vertical: BalviaTheme.spaceMd,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: BalviaTheme.spaceMd),

                // Logo
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(BalviaTheme.radiusLg),
                    ),
                    child: Center(
                      child: BalviaLogoMark(size: 36, color: cs.primary),
                    ),
                  ),
                ),
                const SizedBox(height: BalviaTheme.spaceMd),

                // Title
                Text(
                  'Crea tu cuenta',
                  textAlign: TextAlign.center,
                  style: BalviaTheme.headlineStyle(color: cs.onSurface),
                ),
                const SizedBox(height: BalviaTheme.spaceXs),
                Text(
                  'Empieza a controlar tus finanzas hoy',
                  textAlign: TextAlign.center,
                  style: BalviaTheme.bodyStyle(color: BalviaTheme.inkMuted),
                ),
                const SizedBox(height: BalviaTheme.spaceLg),

                // Full name
                Text(
                  'Nombre completo',
                  style: BalviaTheme.bodyStyle(
                    color: cs.onSurface,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _fullName,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          hintText: 'Germán Rodríguez',
                          border: OutlineInputBorder(),
                          filled: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(opcional)',
                      style: BalviaTheme.captionStyle(
                        color: BalviaTheme.inkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BalviaTheme.spaceMd),

                // Email
                Text(
                  'Correo electrónico',
                  style: BalviaTheme.bodyStyle(
                    color: cs.onSurface,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                    hintText: 'german@correo.co',
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Email inválido' : null,
                ),
                const SizedBox(height: BalviaTheme.spaceMd),

                // Password
                Text(
                  'Contraseña',
                  style: BalviaTheme.bodyStyle(
                    color: cs.onSurface,
                  ).copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _password,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    border: const OutlineInputBorder(),
                    filled: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8)
                      ? 'Mínimo 8 caracteres'
                      : null,
                ),
                const SizedBox(height: BalviaTheme.spaceSm),

                // Password strength bar
                _PasswordStrengthBar(strength: strength),
                const SizedBox(height: BalviaTheme.spaceXs),
                Text(
                  'Mínimo 8 caracteres. Usa letras, números y símbolos.',
                  style: BalviaTheme.captionStyle(color: BalviaTheme.inkMuted),
                ),
                const SizedBox(height: BalviaTheme.spaceMd),

                // Terms checkbox (UI only)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _termsAccepted,
                      onChanged: (v) =>
                          setState(() => _termsAccepted = v ?? false),
                      activeColor: cs.primary,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: RichText(
                          text: TextSpan(
                            style: BalviaTheme.captionStyle(
                              color: cs.onSurface,
                            ),
                            children: [
                              const TextSpan(text: 'Acepto los '),
                              TextSpan(
                                text: 'Términos de uso',
                                style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: ' y la '),
                              TextSpan(
                                text: 'Política de privacidad',
                                style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const TextSpan(text: ' de Balvia'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BalviaTheme.spaceLg),

                // Create account button
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Crear cuenta',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: BalviaTheme.spaceMd),

                // Already have account
                Center(
                  child: Text(
                    '¿Ya tienes cuenta?',
                    style: BalviaTheme.bodyStyle(color: BalviaTheme.inkMuted),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _loading ? null : () => context.go('/login'),
                  child: Text(
                    'Inicia sesión',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(height: BalviaTheme.spaceMd),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Password strength helpers (exported for tests)
// ---------------------------------------------------------------------------

/// Computes password strength on a 0–4 scale.
///
///   0 = empty
///   1 = too short (< 8)
///   2 = weak (≥ 8, only one character class)
///   3 = good (≥ 8, two character classes)
///   4 = strong (≥ 8, three or more character classes)
int passwordStrength(String password) {
  if (password.isEmpty) return 0;
  if (password.length < 8) return 1;

  int classes = 0;
  if (password.contains(RegExp(r'[a-z]'))) classes++;
  if (password.contains(RegExp(r'[A-Z]'))) classes++;
  if (password.contains(RegExp(r'[0-9]'))) classes++;
  if (password.contains(RegExp(r'[^a-zA-Z0-9]'))) classes++;

  if (classes >= 3) return 4;
  if (classes == 2) return 3;
  return 2;
}

/// Human-readable label for [passwordStrength] value.
String passwordStrengthLabel(int strength) => switch (strength) {
  0 => '',
  1 => 'Muy corta',
  2 => 'Débil',
  3 => 'Contraseña buena',
  4 => 'Muy segura',
  _ => '',
};

// ---------------------------------------------------------------------------
// Password strength bar widget (4 segments)
// ---------------------------------------------------------------------------

class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.strength});
  final int strength;

  @override
  Widget build(BuildContext context) {
    if (strength == 0) return const SizedBox.shrink();

    final color = _strengthColor(strength);
    final label = passwordStrengthLabel(strength);

    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(4, (i) {
              final filled = i < strength;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: filled
                        ? color
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _strengthColor(int strength) => switch (strength) {
    1 => BalviaTheme.expense,
    2 => BalviaTheme.budgetWarning,
    3 => BalviaTheme.income,
    4 => const Color(0xFF1B8A4D), // deep green
    _ => Colors.grey,
  };
}
