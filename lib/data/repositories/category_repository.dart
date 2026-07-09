import 'package:dio/dio.dart';

import '../models/category.dart';

/// Fetches categories (system + user's own). Results are cached in memory
/// by the provider layer for the duration of the session.
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
}
