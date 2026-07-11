import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'core/theme_mode_provider.dart';

// Secondary entry-point for the overlay FlutterEngine.
// Imported here so the @pragma("vm:entry-point") annotation is visible to
// the tree-shaker (the function is called from the Android side by name).
import 'features/overlay/overlay_entry.dart'; // ignore: unused_import

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
