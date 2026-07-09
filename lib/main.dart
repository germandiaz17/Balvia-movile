import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/theme.dart';

void main() {
  runApp(const ProviderScope(child: BalviaApp()));
}

class BalviaApp extends ConsumerWidget {
  const BalviaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Balvia',
      debugShowCheckedModeBanner: false,
      theme: BalviaTheme.light(),
      darkTheme: BalviaTheme.dark(),
      routerConfig: router,
    );
  }
}
