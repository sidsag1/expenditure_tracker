class Category {
  final int? id;
  final String name;
  final String icon;
  final String color;
  final bool isCustom;
  final DateTime createdAt;
  final DateTime updatedAt;

  Category({
    this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.isCustom = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  // Predefined categories
  static List<Category> get predefinedCategories {
    final now = DateTime.now();
    return [
      Category(
        name: 'Food & Dining',
        icon: '🍽️',
        color: '#FF6B6B',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Transportation',
        icon: '🚗',
        color: '#4ECDC4',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Shopping',
        icon: '🛍️',
        color: '#45B7D1',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Entertainment',
        icon: '🎬',
        color: '#96CEB4',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Bills & Utilities',
        icon: '💡',
        color: '#FFEAA7',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Health & Medical',
        icon: '🏥',
        color: '#DDA0DD',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Education',
        icon: '📚',
        color: '#74B9FF',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Travel',
        icon: '✈️',
        color: '#00B894',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Groceries',
        icon: '🛒',
        color: '#00CEC9',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Business',
        icon: '💼',
        color: '#636E72',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Investment',
        icon: '📈',
        color: '#FDCB6E',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
      Category(
        name: 'Uncategorized',
        icon: '💰',
        color: '#B2BEC3',
        isCustom: false,
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }

  // Convert Category object to Map for database operations
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'color': color,
      'is_custom': isCustom ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Create Category object from Map
  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      icon: map['icon'],
      color: map['color'],
      isCustom: map['is_custom'] == 1,
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }

  // Copy with modifications
  Category copyWith({
    int? id,
    String? name,
    String? icon,
    String? color,
    bool? isCustom,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'Category(id: $id, name: $name, icon: $icon, color: $color, isCustom: $isCustom)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Category && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
