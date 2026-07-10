/// Tests for CategoryRepository serialization — request body shape for
/// create (POST) and update (PUT) per the API contract.
/// We test via model round-trips (fromJson/toJson) since the repository
/// itself is thin and the contract is what matters.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:balvia_mobile/data/models/category.dart';

void main() {
  final baseJson = <String, dynamic>{
    'id': 'cat-99',
    'name': 'Restaurantes',
    'category_type': 'expense',
    'is_system': false,
    'parent_id': null,
    'icon': null,
    'color': null,
    'display_order': 5,
  };

  group('Category.fromJson — create/update response', () {
    test('parses user-owned expense category', () {
      final cat = Category.fromJson(baseJson);
      expect(cat.id, 'cat-99');
      expect(cat.name, 'Restaurantes');
      expect(cat.categoryType, 'expense');
      expect(cat.isSystem, isFalse);
      expect(cat.displayOrder, 5);
    });

    test('parses system category with read-only flag', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['is_system'] = true
        ..['name'] = 'Comida';
      final cat = Category.fromJson(json);
      expect(cat.isSystem, isTrue);
    });

    test('parses income category', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['category_type'] = 'income';
      final cat = Category.fromJson(json);
      expect(cat.categoryType, 'income');
    });

    test('parses icon and color when present', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['icon'] = 'restaurant'
        ..['color'] = '#FF5722';
      final cat = Category.fromJson(json);
      expect(cat.icon, 'restaurant');
      expect(cat.color, '#FF5722');
    });

    test('parent_id parsed when present', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['parent_id'] = 'cat-parent';
      final cat = Category.fromJson(json);
      expect(cat.parentId, 'cat-parent');
    });
  });

  group('Category.toJson — body shape for POST / PUT', () {
    test('round-trips without data loss', () {
      final cat = Category.fromJson(baseJson);
      final json = cat.toJson();
      final rebuilt = Category.fromJson(json);

      expect(rebuilt.id, cat.id);
      expect(rebuilt.name, cat.name);
      expect(rebuilt.categoryType, cat.categoryType);
      expect(rebuilt.isSystem, cat.isSystem);
      expect(rebuilt.displayOrder, cat.displayOrder);
    });

    test('null fields serialise as null', () {
      final cat = Category.fromJson(baseJson);
      final json = cat.toJson();
      expect(json['parent_id'], isNull);
      expect(json['icon'], isNull);
      expect(json['color'], isNull);
    });

    test('icon and color serialise when set', () {
      final json = Map<String, dynamic>.from(baseJson)
        ..['icon'] = 'food'
        ..['color'] = '#4CAF50';
      final cat = Category.fromJson(json);
      final out = cat.toJson();
      expect(out['icon'], 'food');
      expect(out['color'], '#4CAF50');
    });
  });

  group('System-category guard (contract: PUT returns 404 for is_system)', () {
    test('isSystem flag is true for system categories', () {
      final systemCat = Category.fromJson({
        'id': 'sys-1',
        'name': 'Transporte',
        'category_type': 'expense',
        'is_system': true,
        'parent_id': null,
        'icon': null,
        'color': null,
        'display_order': 0,
      });
      // The UI uses isSystem to gate edit/delete actions.
      expect(systemCat.isSystem, isTrue);
    });

    test('user category isSystem is false', () {
      final userCat = Category.fromJson(baseJson);
      expect(userCat.isSystem, isFalse);
    });
  });
}
