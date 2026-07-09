import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/category.dart';

void main() {
  group('Category.fromJson', () {
    test('parses system expense category', () {
      final c = Category.fromJson({
        'id': 'cat-1',
        'name': 'Comida',
        'category_type': 'expense',
        'is_system': true,
        'parent_id': null,
        'icon': null,
        'color': null,
        'display_order': 0,
      });

      expect(c.id, 'cat-1');
      expect(c.name, 'Comida');
      expect(c.categoryType, 'expense');
      expect(c.isSystem, isTrue);
      expect(c.parentId, isNull);
    });

    test('parses user income category with parent', () {
      final c = Category.fromJson({
        'id': 'cat-2',
        'name': 'Freelance',
        'category_type': 'income',
        'is_system': false,
        'parent_id': 'cat-parent',
        'icon': 'laptop',
        'color': '#00FF00',
        'display_order': 3,
      });

      expect(c.categoryType, 'income');
      expect(c.isSystem, isFalse);
      expect(c.parentId, 'cat-parent');
      expect(c.icon, 'laptop');
      expect(c.color, '#00FF00');
      expect(c.displayOrder, 3);
    });

    test('toJson round-trips', () {
      final original = Category.fromJson({
        'id': 'cat-3',
        'name': 'Transporte',
        'category_type': 'expense',
        'is_system': true,
        'parent_id': null,
        'icon': null,
        'color': null,
        'display_order': 1,
      });
      final json = original.toJson();
      final rebuilt = Category.fromJson(json);

      expect(rebuilt.id, original.id);
      expect(rebuilt.name, original.name);
      expect(rebuilt.categoryType, original.categoryType);
      expect(rebuilt.isSystem, original.isSystem);
      expect(rebuilt.displayOrder, original.displayOrder);
    });

    test('display_order defaults to 0 when absent', () {
      final c = Category.fromJson({
        'id': 'cat-4',
        'name': 'Salud',
        'category_type': 'expense',
        'is_system': true,
        'parent_id': null,
        'icon': null,
        'color': null,
        // display_order intentionally omitted
      });
      expect(c.displayOrder, 0);
    });
  });
}
