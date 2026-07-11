import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models/category.dart';

/// Circle avatar for a category using its color field (#RRGGBB from the backend
/// seed) and a mapped Material icon. Falls back to a generic icon and the
/// primary color when category data is unavailable.
///
/// Use [radius] to control size (default 20 — fits a ListTile leading nicely).
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, this.category, this.radius = 20});

  final Category? category;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cat = category;
    final bgColor = _resolveColor(cat, context);
    final icon = _resolveIcon(cat);

    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor.withValues(alpha: 0.18),
      child: Icon(icon, size: radius * 0.85, color: bgColor),
    );
  }

  Color _resolveColor(Category? cat, BuildContext context) {
    if (cat?.color != null) {
      final hex = cat!.color!.replaceFirst('#', '');
      if (hex.length == 6) {
        final value = int.tryParse('FF$hex', radix: 16);
        if (value != null) return Color(value);
      }
    }
    // Fall back to semantic color by category type.
    return switch (cat?.categoryType) {
      'income' => BalviaTheme.income,
      'expense' => BalviaTheme.expense,
      'transfer' => BalviaTheme.transfer,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  IconData _resolveIcon(Category? cat) {
    if (cat?.icon == null) return Icons.label_outline;
    return _iconMap[cat!.icon!] ?? Icons.label_outline;
  }
}

// ---------------------------------------------------------------------------
// Icon name → Material IconData mapping for the seed categories
// (DESIGN.md §7 and API seed data). Names match what the backend stores.
// ---------------------------------------------------------------------------

const Map<String, IconData> _iconMap = {
  // Income
  'briefcase': Icons.work_outline,
  'laptop': Icons.laptop_outlined,
  'trending-up': Icons.trending_up,
  'gift': Icons.card_giftcard_outlined,
  'arrow-back': Icons.undo,
  'plus-circle': Icons.add_circle_outline,

  // Expense
  'restaurant': Icons.restaurant_outlined,
  'directions-car': Icons.directions_car_outlined,
  'home': Icons.home_outlined,
  'flash': Icons.flash_on_outlined,
  'medical-bag': Icons.local_hospital_outlined,
  'school': Icons.school_outlined,
  'movie': Icons.movie_outlined,
  'card': Icons.credit_card_outlined,
  'shirt': Icons.checkroom_outlined,
  'paw': Icons.pets_outlined,
  'coffee': Icons.coffee_outlined,
  'document-text': Icons.description_outlined,
  'help-circle': Icons.help_outline,

  // Misc / fallbacks
  'swap-horiz': Icons.swap_horiz,
  'label': Icons.label_outline,
};
