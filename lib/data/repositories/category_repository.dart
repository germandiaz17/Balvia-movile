import 'package:dio/dio.dart';

import '../models/category.dart';

/// Manages category API calls (system + own).
/// System categories are read-only per the contract; only user-owned categories
/// may be created, updated, or deleted.
class CategoryRepository {
  CategoryRepository(this._dio);

  final Dio _dio;

  /// Returns all categories (system + own) for the authenticated user.
  Future<List<Category>> list() async {
    final res = await _dio.get('/categories');
    final items = (res.data as Map<String, dynamic>)['categories'] as List;
    return items
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetches a single category by [id]. Returns null if 404.
  Future<Category?> get(String id) async {
    try {
      final res = await _dio.get('/categories/$id');
      return Category.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Creates a user-owned category. [categoryType] must be one of
  /// income | expense | transfer.
  Future<Category> create({
    required String name,
    required String categoryType,
    String? parentId,
    String? icon,
    String? color,
    int displayOrder = 0,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'category_type': categoryType,
      'display_order': displayOrder,
    };
    if (parentId != null) body['parent_id'] = parentId;
    if (icon != null && icon.isNotEmpty) body['icon'] = icon;
    if (color != null && color.isNotEmpty) body['color'] = color;

    final res = await _dio.post('/categories', data: body);
    return Category.fromJson(res.data as Map<String, dynamic>);
  }

  /// Updates a user-owned category. The contract returns 404 for system
  /// categories, so the caller should gate on [Category.isSystem].
  Future<Category> update(
    String id, {
    required String name,
    String? parentId,
    String? icon,
    String? color,
    int displayOrder = 0,
  }) async {
    final body = <String, dynamic>{'name': name, 'display_order': displayOrder};
    if (parentId != null) body['parent_id'] = parentId;
    if (icon != null && icon.isNotEmpty) body['icon'] = icon;
    if (color != null && color.isNotEmpty) body['color'] = color;

    final res = await _dio.put('/categories/$id', data: body);
    return Category.fromJson(res.data as Map<String, dynamic>);
  }

  /// Hard-deletes a user-owned category (DELETE /categories/:id).
  /// The backend returns 404 for system categories.
  Future<void> delete(String id) async {
    await _dio.delete('/categories/$id');
  }
}
