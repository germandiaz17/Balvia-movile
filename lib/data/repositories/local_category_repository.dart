// Local category repository backed by Drift (offline-first reads).
//
// Categories are pulled by the sync engine (own categories from pull; system
// categories via GET /categories, which the sync engine also covers).
// Writes (create/update/delete) still go through the network API.

import '../local/app_database.dart' as db;
import '../../data/models/category.dart';

/// Converts a Drift [db.Category] row to the domain [Category].
Category _categoryRowToModel(db.Category row) => Category(
      id: row.id,
      name: row.name,
      categoryType: row.categoryType,
      isSystem: row.isSystem,
      parentId: row.parentId,
      icon: row.icon,
      color: row.color,
      displayOrder: row.displayOrder,
    );

class LocalCategoryRepository {
  LocalCategoryRepository(this._db);

  final db.AppDatabase _db;

  /// Stream of all non-deleted categories (system + own).
  Stream<List<Category>> watchAll() =>
      _db.categoriesDao.watchAll().map(
        (rows) => rows.map(_categoryRowToModel).toList(),
      );

  /// One-shot list.
  Future<List<Category>> getAll() async {
    final rows = await _db.categoriesDao.getAll();
    return rows.map(_categoryRowToModel).toList();
  }
}
