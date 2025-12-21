import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../models/category.dart';

class CategoryDAO {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Create a new category
  Future<int> insertCategory(Category category) async {
    final db = await _dbHelper.database;
    return await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // Get all categories
  Future<List<Category>> getAllCategories() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      orderBy: 'name ASC',
    );
    
    return List.generate(maps.length, (i) {
      return Category.fromMap(maps[i]);
    });
  }

  // Get predefined categories only
  Future<List<Category>> getPredefinedCategories() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      where: 'is_custom = ?',
      whereArgs: [0],
      orderBy: 'name ASC',
    );
    
    return List.generate(maps.length, (i) {
      return Category.fromMap(maps[i]);
    });
  }

  // Get custom categories only
  Future<List<Category>> getCustomCategories() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      where: 'is_custom = ?',
      whereArgs: [1],
      orderBy: 'name ASC',
    );
    
    return List.generate(maps.length, (i) {
      return Category.fromMap(maps[i]);
    });
  }

  // Get category by ID
  Future<Category?> getCategoryById(int id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isNotEmpty) {
      return Category.fromMap(maps.first);
    }
    return null;
  }

  // Get category by name
  Future<Category?> getCategoryByName(String name) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      where: 'name = ?',
      whereArgs: [name],
    );
    
    if (maps.isNotEmpty) {
      return Category.fromMap(maps.first);
    }
    return null;
  }

  // Update category
  Future<int> updateCategory(Category category) async {
    final db = await _dbHelper.database;
    return await db.update(
      'categories',
      category.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  // Delete category
  Future<int> deleteCategory(int categoryId) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [categoryId],
    );
  }

  // Delete custom category only (predefined categories cannot be deleted)
  Future<int> deleteCustomCategory(int categoryId) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'categories',
      where: 'id = ? AND is_custom = ?',
      whereArgs: [categoryId, 1],
    );
  }

  // Get count of categories
  Future<int> getCategoryCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM categories');
    
    return result.first['count'] as int;
  }

  // Get count of custom categories
  Future<int> getCustomCategoryCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM categories WHERE is_custom = 1',
    );
    
    return result.first['count'] as int;
  }

  // Check if category name already exists
  Future<bool> categoryNameExists(String name) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'categories',
      where: 'name = ?',
      whereArgs: [name],
    );
    
    return result.isNotEmpty;
  }

  // Get categories with transaction counts
  Future<List<Map<String, dynamic>>> getCategoriesWithTransactionCounts() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.*, COUNT(t.id) as transaction_count
      FROM categories c
      LEFT JOIN transactions t ON c.name = t.category
      GROUP BY c.id
      ORDER BY c.name ASC
    ''');
    
    return maps;
  }

  // Get predefined categories list (for quick access)
  static List<Category> getPredefinedCategoriesList() {
    return Category.predefinedCategories;
  }

  // Get category by name from predefined list (fast lookup)
  static Category? getPredefinedCategoryByName(String name) {
    try {
      return Category.predefinedCategories.firstWhere(
        (category) => category.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }

  // Initialize default categories in database (for first-time setup)
  Future<void> initializeDefaultCategories() async {
    final db = await _dbHelper.database;
    
    // Check if categories already exist
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM categories');
    final existingCount = countResult.first['count'] as int;
    
    if (existingCount == 0) {
      // Insert predefined categories
      await _insertPredefinedCategories(db);
    }
  }

  Future<void> _insertPredefinedCategories(Database db) async {
    for (Category category in Category.predefinedCategories) {
      await db.insert('categories', {
        'name': category.name,
        'icon': category.icon,
        'color': category.color,
        'is_custom': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  // Search categories by name
  Future<List<Category>> searchCategories(String query) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'categories',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
    );
    
    return List.generate(maps.length, (i) {
      return Category.fromMap(maps[i]);
    });
  }

  // Get categories sorted by most used (for suggestions)
  Future<List<Category>> getCategoriesByUsage() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT c.*, COUNT(t.id) as usage_count
      FROM categories c
      LEFT JOIN transactions t ON c.name = t.category
      GROUP BY c.id
      ORDER BY usage_count DESC, c.name ASC
    ''');
    
    return List.generate(maps.length, (i) {
      return Category.fromMap(maps[i]);
    });
  }
}
