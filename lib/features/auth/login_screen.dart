import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_error.dart';
import '../../core/theme.dart';
import 'auth_controller.dart';
import '../../shared/balvia_logo.dart';

/// Login screen (mockup 10).
///
/// Layout:
///   - Teal header with wave/curve at the bottom containing logo + tagline
///   - White body: "Bienvenido" headline, overline labels on fields,
///     "¿Olvidaste tu contraseña?" link (dead), filled button, register link.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(_email.text.trim(), _password.text);
      // Router redirects to /home automatically on success.
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

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // ---- Teal wave header ----
          _TealWaveHeader(),

          // ---- Scrollable form body ----
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                BalviaTheme.spaceLg,
                BalviaTheme.spaceLg,
                BalviaTheme.spaceLg,
                BalviaTheme.spaceLg,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Headline
                    Text(
                      'Bienvenido',
                      style: BalviaTheme.headlineStyle(color: cs.onSurface),
                    ),
                    const SizedBox(height: BalviaTheme.spaceXs),
                    Text(
                      'Ingresa a tu cuenta de Balvia',
                      style: BalviaTheme.bodyStyle(color: BalviaTheme.inkMuted),
                    ),
                    const SizedBox(height: BalviaTheme.spaceLg),

                    // Email field
                    _OverlineLabel('CORREO ELECTRÓNICO'),
                    const SizedBox(height: BalviaTheme.spaceXs),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        hintText: 'tu@correo.co',
                        border: OutlineInputBorder(),
                        filled: true,
                      ),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Email inválido'
                          : null,
                    ),
                    const SizedBox(height: BalviaTheme.spaceMd),

                    // Password field
                    _OverlineLabel('CONTRASEÑA'),
                    const SizedBox(height: BalviaTheme.spaceXs),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.password],
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
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Ingresa tu contraseña'
                          : null,
                    ),

                    // Forgot password — dead link (post-MVP)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: null, // TODO: post-MVP forgot password flow
                        style: TextButton.styleFrom(
                          foregroundColor: cs.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                        ),
                        child: Text(
                          '¿Olvidaste tu contraseña?',
                          style: BalviaTheme.bodyStyle(color: cs.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: BalviaTheme.spaceMd),

                    // Login button
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
                              'Iniciar sesión',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: BalviaTheme.spaceLg),

                    // Divider + register link
                    Row(
                      children: [
                        Expanded(child: Divider(color: cs.outlineVariant)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            '¿Nuevo en Balvia?',
                            style: BalviaTheme.captionStyle(
                              color: BalviaTheme.inkMuted,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: cs.outlineVariant)),
                      ],
                    ),
                    const SizedBox(height: BalviaTheme.spaceMd),
                    OutlinedButton(
                      onPressed: _loading
                          ? null
                          : () => context.go('/register'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: BorderSide(color: cs.primary),
                        foregroundColor: cs.primary,
                      ),
                      child: const Text(
                        'Regístrate gratis',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Teal wave header (mockup 10 — logo + tagline + wave clip)
// ---------------------------------------------------------------------------

class _TealWaveHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        height: 220,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF14B8A6), Color(0xFF0F9D8C)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              // Logo mark
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(BalviaTheme.radiusMd),
                ),
                child: const Center(
                  child: BalviaLogoMark(size: 32, color: Colors.white),
                ),
              ),
              const SizedBox(height: BalviaTheme.spaceSm),
              const Text(
                'balvia',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: BalviaTheme.spaceXs),
              Text(
                'Tus finanzas, bajo control',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
              // Extra space consumed by the wave
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom clipper that produces the wave/curve at the bottom of the header.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 50);
    path.quadraticBezierTo(
      size.width / 2,
      size.height + 20,
      size.width,
      size.height - 50,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper old) => false;
}

// ---------------------------------------------------------------------------
// Overline label (design system §2 — 11px W600 uppercase)
// ---------------------------------------------------------------------------

class _OverlineLabel extends StatelessWidget {
  const _OverlineLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: BalviaTheme.overlineStyle(color: BalviaTheme.inkMuted),
    );
  }
}

// Logo mark (duplicated here vs splash to avoid cross-feature import).
