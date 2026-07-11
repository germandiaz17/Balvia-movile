import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/balvia_logo.dart';

/// Splash screen shown while the app bootstraps (auth status = unknown).
///
/// Design: full teal gradient background, rounded-square logo, "balvia"
/// wordmark in white, tagline "Tus finanzas, bajo control", thin progress bar
/// at the bottom. (mockup 09)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF14B8A6), // teal-400
              Color(0xFF0F9D8C), // primary
              Color(0xFF0D8C7A), // slightly darker
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Decorative circles (background blobs matching mockup)
              Positioned(
                top: -60,
                right: -60,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),
              Positioned(
                bottom: 120,
                left: -40,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.07),
                  ),
                ),
              ),

              // Main content — centered
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo in translucent rounded square
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(
                          BalviaTheme.radiusXl,
                        ),
                      ),
                      child: const Center(
                        child: BalviaLogoMark(size: 48, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: BalviaTheme.spaceMd),

                    // Wordmark "balvia"
                    const Text(
                      'balvia',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: BalviaTheme.spaceSm),

                    // Tagline
                    Text(
                      'Tus finanzas, bajo control',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // Progress bar at the bottom
              Positioned(
                left: BalviaTheme.spaceLg,
                right: BalviaTheme.spaceLg,
                bottom:
                    BalviaTheme.spaceLg + MediaQuery.of(context).padding.bottom,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _progress,
                      builder: (_, child) => LinearProgressIndicator(
                        value: _progress.value,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                        color: Colors.white,
                        minHeight: 3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cargando tu cuenta…',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
