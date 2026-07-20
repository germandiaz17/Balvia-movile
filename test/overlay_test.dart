// Tests for the floating bubble (overlay) feature.
//
// Coverage:
//   1. Most-used categories logic (mostUsedExpenseCategories)
//   2. OverlaySettings model (copyWith, bubbleColor, prefs round-trip)
//   3. Auto-off timer logic (shouldAutoOff)
//   4. Validation helpers (clampOpacity, isValidColorHex)

import 'package:flutter_test/flutter_test.dart';

import 'package:balvia_mobile/data/models/category.dart';
import 'package:balvia_mobile/data/models/transaction.dart';
import 'package:balvia_mobile/features/overlay/overlay_logic.dart';
import 'package:balvia_mobile/features/overlay/overlay_settings.dart';
import 'package:decimal/decimal.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Category _cat(
  String id,
  String name, {
  String type = 'expense',
  int order = 0,
}) {
  return Category(
    id: id,
    name: name,
    categoryType: type,
    isSystem: true,
    displayOrder: order,
  );
}

Transaction _tx(
  String categoryId, {
  String type = 'expense',
  String date = '2026-07-01',
}) {
  return Transaction(
    id: 'tx-$categoryId-$date',
    trackingPeriodId: 'period-1',
    accountId: 'acc-1',
    transactionType: type,
    amount: Decimal.parse('10000'),
    currency: 'COP',
    transactionDate: date,
    createdAt: DateTime(2026, 7, 1),
    categoryId: categoryId,
  );
}

// ---------------------------------------------------------------------------
// 1. mostUsedExpenseCategories
// ---------------------------------------------------------------------------

void main() {
  final catFood = _cat('cat-food', 'Alimentación');
  final catTransport = _cat('cat-transport', 'Transporte');
  final catEnt = _cat('cat-ent', 'Entretenimiento');
  final catHealth = _cat('cat-health', 'Salud');
  final catIncome = _cat('cat-salary', 'Salario', type: 'income');
  final allCats = [catFood, catTransport, catEnt, catHealth, catIncome];

  group('mostUsedExpenseCategories', () {
    test('empty transactions returns first N expense categories', () {
      final result = mostUsedExpenseCategories([], allCats, limit: 3);
      expect(result.length, 3);
      expect(result.every((c) => c.categoryType == 'expense'), isTrue);
    });

    test('returns categories ranked by frequency', () {
      final txs = [
        _tx('cat-food'),
        _tx('cat-food'),
        _tx('cat-food'),
        _tx('cat-transport'),
        _tx('cat-transport'),
        _tx('cat-ent'),
      ];
      final result = mostUsedExpenseCategories(txs, allCats, limit: 3);
      expect(result.first.id, 'cat-food'); // 3 times
      expect(result[1].id, 'cat-transport'); // 2 times
      expect(result[2].id, 'cat-ent'); // 1 time
    });

    test('ignores income transactions for ranking', () {
      final txs = [
        _tx('cat-salary', type: 'income'),
        _tx('cat-salary', type: 'income'),
        _tx('cat-food'),
      ];
      final result = mostUsedExpenseCategories(txs, allCats, limit: 3);
      // cat-food should rank first (only expense transaction)
      expect(result.first.id, 'cat-food');
    });

    test('ignores categories not in allCategories', () {
      final txs = [_tx('unknown-cat'), _tx('cat-transport')];
      final result = mostUsedExpenseCategories(txs, allCats, limit: 3);
      // unknown-cat excluded; cat-transport first; backfill with others
      expect(result.any((c) => c.id == 'unknown-cat'), isFalse);
      expect(result.first.id, 'cat-transport');
    });

    test('respects limit', () {
      final txs = [
        _tx('cat-food'),
        _tx('cat-transport'),
        _tx('cat-ent'),
        _tx('cat-health'),
      ];
      final result = mostUsedExpenseCategories(txs, allCats, limit: 2);
      expect(result.length, 2);
    });

    test('fills remaining slots from other expense categories', () {
      final txs = [_tx('cat-food')];
      // limit=3, only 1 ranked → should backfill 2 more from expense cats
      final result = mostUsedExpenseCategories(txs, allCats, limit: 3);
      expect(result.length, 3);
      expect(result.every((c) => c.categoryType == 'expense'), isTrue);
    });

    test('returns empty list if no expense categories exist', () {
      final result = mostUsedExpenseCategories([], [catIncome], limit: 3);
      expect(result, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. OverlaySettings model
  // ---------------------------------------------------------------------------

  group('OverlaySettings', () {
    test('default values', () {
      const s = OverlaySettings();
      expect(s.enabled, isFalse);
      expect(s.opacity, closeTo(0.85, 0.001));
      expect(s.colorHex, '#0F9D8C');
      expect(s.defaultAccountId, isNull);
      expect(s.showTodaySpend, isTrue);
      expect(s.showBalance, isFalse);
      expect(s.autoOffMinutes, isNull);
    });

    test('copyWith updates only specified fields', () {
      const original = OverlaySettings(opacity: 0.5, enabled: true);
      final updated = original.copyWith(enabled: false);
      expect(updated.enabled, isFalse);
      expect(updated.opacity, closeTo(0.5, 0.001)); // unchanged
    });

    test('copyWith can clear defaultAccountId to null', () {
      const s = OverlaySettings(defaultAccountId: 'acc-1');
      final cleared = s.copyWith(defaultAccountId: null);
      expect(cleared.defaultAccountId, isNull);
    });

    test('copyWith can clear autoOffMinutes to null', () {
      const s = OverlaySettings(autoOffMinutes: 10);
      final cleared = s.copyWith(autoOffMinutes: null);
      expect(cleared.autoOffMinutes, isNull);
    });

    test('bubbleColor parses 6-char hex', () {
      const s = OverlaySettings(colorHex: '#0F9D8C');
      final color = s.bubbleColor;
      expect(color.toARGB32(), 0xFF0F9D8C);
    });

    test('bubbleColor falls back on invalid hex', () {
      const s = OverlaySettings(colorHex: 'invalid');
      final color = s.bubbleColor;
      expect(color.toARGB32(), 0xFF0F9D8C); // brand teal fallback
    });

    test('bubbleColor parses 8-char ARGB hex', () {
      const s = OverlaySettings(colorHex: '#FF0F9D8C');
      final color = s.bubbleColor;
      expect(color.toARGB32(), 0xFF0F9D8C);
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Auto-off timer logic
  // ---------------------------------------------------------------------------

  group('shouldAutoOff', () {
    final now = DateTime.utc(2026, 7, 10, 12, 0, 0);
    final backgrounded = DateTime.utc(2026, 7, 10, 11, 45, 0); // 15 min ago

    test('returns false when autoOffMinutes is null (never)', () {
      expect(
        shouldAutoOff(
          backgroundedAt: backgrounded,
          autoOffMinutes: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('returns false when backgroundedAt is null', () {
      expect(
        shouldAutoOff(backgroundedAt: null, autoOffMinutes: 5, now: now),
        isFalse,
      );
    });

    test('returns true when elapsed > threshold', () {
      // backgrounded 15 min ago, threshold is 10
      expect(
        shouldAutoOff(
          backgroundedAt: backgrounded,
          autoOffMinutes: 10,
          now: now,
        ),
        isTrue,
      );
    });

    test('returns false when elapsed < threshold', () {
      // backgrounded 15 min ago, threshold is 30
      expect(
        shouldAutoOff(
          backgroundedAt: backgrounded,
          autoOffMinutes: 30,
          now: now,
        ),
        isFalse,
      );
    });

    test('returns true at exactly the threshold', () {
      final exact = DateTime.utc(2026, 7, 10, 11, 50, 0); // exactly 10 min ago
      expect(
        shouldAutoOff(backgroundedAt: exact, autoOffMinutes: 10, now: now),
        isTrue,
      );
    });

    test('returns false 1 minute below threshold', () {
      final almostThere = DateTime.utc(2026, 7, 10, 11, 51, 0); // 9 min ago
      expect(
        shouldAutoOff(
          backgroundedAt: almostThere,
          autoOffMinutes: 10,
          now: now,
        ),
        isFalse,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 4. Validation helpers
  // ---------------------------------------------------------------------------

  group('clampOpacity', () {
    test('clamps below minimum to 0.3', () {
      expect(clampOpacity(0.0), closeTo(0.3, 0.001));
    });

    test('clamps above maximum to 1.0', () {
      expect(clampOpacity(1.5), closeTo(1.0, 0.001));
    });

    test('passes through values in range', () {
      expect(clampOpacity(0.75), closeTo(0.75, 0.001));
    });

    test('clamps exactly at bounds', () {
      expect(clampOpacity(0.3), closeTo(0.3, 0.001));
      expect(clampOpacity(1.0), closeTo(1.0, 0.001));
    });
  });

  group('isValidColorHex', () {
    test('valid 6-char hex without hash', () {
      expect(isValidColorHex('0F9D8C'), isTrue);
    });

    test('valid 6-char hex with hash', () {
      expect(isValidColorHex('#0F9D8C'), isTrue);
    });

    test('valid 8-char hex with hash', () {
      expect(isValidColorHex('#FF0F9D8C'), isTrue);
    });

    test('invalid — wrong length', () {
      expect(isValidColorHex('#FFF'), isFalse);
    });

    test('invalid — non-hex chars', () {
      expect(isValidColorHex('#GGGGGG'), isFalse);
    });

    test('empty string is invalid', () {
      expect(isValidColorHex(''), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. Bubble / window geometry
  // ---------------------------------------------------------------------------

  group('clampBubbleSize', () {
    test('clamps below minimum', () {
      expect(clampBubbleSize(10), 44.0);
    });

    test('clamps above maximum', () {
      expect(clampBubbleSize(200), 88.0);
    });

    test('passes through valid values', () {
      expect(clampBubbleSize(56), 56.0);
    });
  });

  group('bubble window geometry', () {
    test('pill is wider than tall', () {
      expect(bubbleWidth(56), greaterThan(56));
    });

    test('default size keeps historical window ratio', () {
      // 56dp bubble → 87dp pill → 97dp window; height 56 → 66 like before.
      expect(collapsedWindowHeight(56), 66);
      expect(collapsedWindowWidth(56), bubbleWidth(56) + 10);
    });
  });

  group('expandedOverlayOffset', () {
    test('centers horizontally under RIGHT gravity', () {
      final offset = expandedOverlayOffset(
        screenW: 411,
        screenH: 915,
        cardW: 340,
        cardH: 340,
      );
      // x = right margin = (411 - 340) / 2 ≈ 36
      expect(offset.x, ((411 - 340) / 2).round());
    });

    test('places card top at topMargin below screen top', () {
      final offset = expandedOverlayOffset(
        screenW: 411,
        screenH: 915,
        cardW: 340,
        cardH: 340,
        topMargin: 48,
      );
      // y offset from vertical center; card top = center + y - cardH/2.
      final cardTop = 915 / 2 + offset.y - 340 / 2;
      expect(cardTop, closeTo(48, 1));
      // Card must live entirely in the upper half + margin zone.
      expect(915 / 2 + offset.y + 340 / 2, lessThan(915 * 0.6));
    });

    test('clamps x away from the -1 MATCH_PARENT sentinel', () {
      final offset = expandedOverlayOffset(
        screenW: 338,
        screenH: 915,
        cardW: 340,
        cardH: 340,
      );
      expect(offset.x, greaterThanOrEqualTo(0));
    });
  });
}
