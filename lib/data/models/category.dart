/// A spending/income category. System categories are read-only.
/// Mirrors the contract object in docs/API_CONTRACT.md §Categories.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.categoryType,
    required this.isSystem,
    this.parentId,
    this.icon,
    this.color,
    this.displayOrder = 0,
  });

  final String id;
  final String name;

  /// income | expense | transfer
  final String categoryType;
  final bool isSystem;
  final String? parentId;
  final String? icon;
  final String? color;
  final int displayOrder;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: json['id'] as String,
    name: json['name'] as String,
    categoryType: json['category_type'] as String,
    isSystem: json['is_system'] as bool,
    parentId: json['parent_id'] as String?,
    icon: json['icon'] as String?,
    color: json['color'] as String?,
    displayOrder: json['display_order'] as int? ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category_type': categoryType,
    'is_system': isSystem,
    'parent_id': parentId,
    'icon': icon,
    'color': color,
    'display_order': displayOrder,
  };
}
