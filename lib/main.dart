import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'core/theme_mode_provider.dart';

void main() {
  runApp(const ProviderScope(child: BalviaApp()));
}

class BalviaApp extends ConsumerWidget {
  const BalviaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // While the theme pref loads, fall back to system. Never shows a flash
    // because SharedPreferences is synchronous after the first read.
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return MaterialApp.router(
      title: 'Balvia',
      debugShowCheckedModeBanner: false,
      theme: BalviaTheme.light(),
      darkTheme: BalviaTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
