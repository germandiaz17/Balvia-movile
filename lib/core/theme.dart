import 'package:flutter/material.dart';

/// Balvia visual identity. Teal/emerald seed (growth, money), Material 3.
///
/// Semantic colors (transaction types, budget thresholds) are defined as
/// static constants so they are stable across light and dark themes — they
/// are brand/semantic, not derived from the M3 tonal palette.
class BalviaTheme {
  const BalviaTheme._();

  // -------------------------------------------------------------------------
  // Seed
  // -------------------------------------------------------------------------

  static const Color seed = Color(0xFF0F9D8C);

  // -------------------------------------------------------------------------
  // Semantic colors (design brief §3)
  // -------------------------------------------------------------------------

  /// Income / positive amounts — green.
  static const Color income = Color(0xFF4CAF50);

  /// Expense / negative amounts — red-coral.
  static const Color expense = Color(0xFFEF5350);

  /// Transfers / neutral — blue.
  static const Color transfer = Color(0xFF42A5F5);

  /// Budget warning threshold (≥ 80%) — amber.
  static const Color budgetWarning = Color(0xFFFFA726);

  /// Budget exceeded (≥ 100%) — same red as expense.
  static const Color budgetExceeded = Color(0xFFEF5350);

  // -------------------------------------------------------------------------
  // Convenience helpers
  // -------------------------------------------------------------------------

  /// Returns the semantic color for a transaction type string.
  static Color colorForType(String transactionType) =>
      switch (transactionType) {
        'income' => income,
        'expense' => expense,
        'transfer' => transfer,
        _ => expense,
      };

  /// Returns the sign prefix for a transaction type.
  static String signForType(String transactionType) =>
      switch (transactionType) {
        'income' => '+',
        'expense' => '-',
        _ => '',
      };

  // -------------------------------------------------------------------------
  // ThemeData builders
  // -------------------------------------------------------------------------

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
      // Tabular figures for monetary amounts — prevents layout jitter when
      // digits change (e.g. live keypad in quick capture).
      textTheme: _buildTextTheme(brightness),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    // Use tnum (tabular numbers) feature tag on all text styles so monetary
    // values displayed in any style are aligned column-by-column.
    const tabular = [FontFeature.tabularFigures()];
    const base = TextTheme();
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontFeatures: tabular),
      displayMedium: base.displayMedium?.copyWith(fontFeatures: tabular),
      displaySmall: base.displaySmall?.copyWith(fontFeatures: tabular),
      headlineLarge: base.headlineLarge?.copyWith(fontFeatures: tabular),
      headlineMedium: base.headlineMedium?.copyWith(fontFeatures: tabular),
      headlineSmall: base.headlineSmall?.copyWith(fontFeatures: tabular),
      titleLarge: base.titleLarge?.copyWith(fontFeatures: tabular),
      titleMedium: base.titleMedium?.copyWith(fontFeatures: tabular),
      titleSmall: base.titleSmall?.copyWith(fontFeatures: tabular),
      bodyLarge: base.bodyLarge?.copyWith(fontFeatures: tabular),
      bodyMedium: base.bodyMedium?.copyWith(fontFeatures: tabular),
      bodySmall: base.bodySmall?.copyWith(fontFeatures: tabular),
      labelLarge: base.labelLarge?.copyWith(fontFeatures: tabular),
      labelMedium: base.labelMedium?.copyWith(fontFeatures: tabular),
      labelSmall: base.labelSmall?.copyWith(fontFeatures: tabular),
    );
  }
}
