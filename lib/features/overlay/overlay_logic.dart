// Pure logic helpers for the overlay feature.
// No Flutter/platform dependencies — fully unit-testable.

import '../../data/models/category.dart';
import '../../data/models/transaction.dart';

// ---------------------------------------------------------------------------
// Most-used expense categories
// ---------------------------------------------------------------------------

/// Returns up to [limit] expense categories sorted by frequency of use
/// in [transactions] (most frequent first).
///
/// Falls back to the first [limit] expense categories from [allCategories]
/// if there are no expense transactions.
List<Category> mostUsedExpenseCategories(
  List<Transaction> transactions,
  List<Category> allCategories, {
  int limit = 6,
}) {
  // Count how many times each category was used in expense transactions.
  final counts = <String, int>{};
  for (final tx in transactions) {
    if (tx.transactionType == 'expense' && tx.categoryId != null) {
      counts[tx.categoryId!] = (counts[tx.categoryId!] ?? 0) + 1;
    }
  }

  if (counts.isEmpty) {
    // No data — return first N expense categories.
    return allCategories
        .where((c) => c.categoryType == 'expense')
        .take(limit)
        .toList();
  }

  // Only include categories that exist in allCategories.
  final expenseCategoryIds = allCategories
      .where((c) => c.categoryType == 'expense')
      .map((c) => c.id)
      .toSet();

  final ranked = counts.entries
      .where((e) => expenseCategoryIds.contains(e.key))
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final topIds = ranked.take(limit).map((e) => e.key).toSet();
  final topCategories = allCategories
      .where((c) => topIds.contains(c.id))
      .toList();

  // Sort by rank (same order as ranked list).
  topCategories.sort(
    (a, b) => ranked
        .indexWhere((e) => e.key == a.id)
        .compareTo(ranked.indexWhere((e) => e.key == b.id)),
  );

  // Fill remaining slots with other expense categories not yet in top.
  if (topCategories.length < limit) {
    final extra = allCategories
        .where(
          (c) => c.categoryType == 'expense' && !topIds.contains(c.id),
        )
        .take(limit - topCategories.length);
    topCategories.addAll(extra);
  }

  return topCategories;
}

// ---------------------------------------------------------------------------
// Auto-off timer logic
// ---------------------------------------------------------------------------

/// Returns true if the overlay should be hidden given:
///   [backgroundedAt] — when the app last went to background (UTC).
///   [autoOffMinutes] — configured threshold (null = never auto-off).
///   [now] — current time (injected for testability; defaults to DateTime.now()).
bool shouldAutoOff({
  required DateTime? backgroundedAt,
  required int? autoOffMinutes,
  DateTime? now,
}) {
  if (autoOffMinutes == null || backgroundedAt == null) return false;
  final elapsed = (now ?? DateTime.now().toUtc()).difference(backgroundedAt);
  return elapsed.inMinutes >= autoOffMinutes;
}

// ---------------------------------------------------------------------------
// Settings validation
// ---------------------------------------------------------------------------

/// Clamps opacity to the valid range [0.3, 1.0].
double clampOpacity(double opacity) => opacity.clamp(0.3, 1.0);

/// Returns true if [hex] is a valid #RRGGBB or #AARRGGBB color string.
bool isValidColorHex(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length != 6 && clean.length != 8) return false;
  return RegExp(r'^[0-9A-Fa-f]+$').hasMatch(clean);
}
