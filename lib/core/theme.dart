import 'package:flutter/material.dart';

/// Balvia visual identity. Teal/emerald seed (growth, money), Material 3.
///
/// Semantic colors (transaction types, budget thresholds) are defined as
/// static constants so they are stable across light and dark themes — they
/// are brand/semantic, not derived from the M3 tonal palette.
///
/// Typography scale (design system §2 — Roboto):
///   Display  32 / W700
///   Headline 24 / W700
///   Title    18 / W600
///   Body     14 / W400
///   Caption  12 / W400
///   Overline 11 / W600 uppercase
class BalviaTheme {
  const BalviaTheme._();

  // -------------------------------------------------------------------------
  // Brand palette (design system §1)
  // -------------------------------------------------------------------------

  /// Primary brand teal.
  static const Color seed = Color(0xFF0F9D8C);

  /// Primary container (light teal tint).
  static const Color primaryContainer = Color(0xFFB2DFDB);

  /// Surface tonal (very light teal surface).
  static const Color surfaceTonal = Color(0xFFE6F4F2);

  /// Surface light.
  static const Color surfaceLight = Color(0xFFFFFBFE);

  /// Surface dark.
  static const Color surfaceDark = Color(0xFF1C1B1F);

  /// Ink muted — secondary text.
  static const Color inkMuted = Color(0xFF49454F);

  // -------------------------------------------------------------------------
  // Semantic colors (design system §3)
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
  // Typography scale helpers (design system §2)
  // -------------------------------------------------------------------------

  static TextStyle displayStyle({Color? color}) => TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle headlineStyle({Color? color}) => TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle titleStyle({Color? color}) => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static TextStyle bodyStyle({Color? color}) =>
      TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: color);

  static TextStyle captionStyle({Color? color}) =>
      TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: color);

  static TextStyle overlineStyle({Color? color}) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    color: color,
  );

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
  // Spacing scale (design system §5 — xs·4 / sm·8 / md·16 / lg·24 / xl·32 / 2xl·48)
  // -------------------------------------------------------------------------
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double space2xl = 48;

  // -------------------------------------------------------------------------
  // Corner radius scale (design system §6 — none·0 / xs·2 / sm·8 / md·12 / lg·16 / xl·24 / pill)
  // -------------------------------------------------------------------------
  static const double radiusNone = 0;
  static const double radiusXs = 2;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;

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
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
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
