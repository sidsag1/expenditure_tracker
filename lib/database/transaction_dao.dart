import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../models/transaction.dart';

class TransactionDAO {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Create a new transaction
  Future<int> insertTransaction(Transaction transaction) async {
    final db = await _dbHelper.database;
    return await db.insert(
      'transactions',
      transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // Insert or ignore if transaction ID already exists (for duplicate prevention)
  Future<int> insertOrIgnoreTransaction(Transaction transaction) async {
    final db = await _dbHelper.database;
    return await db.insert(
      'transactions',
      transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // Get all transactions
  Future<List<Transaction>> getAllTransactions() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  // Get transactions by account
  Future<List<Transaction>> getTransactionsByAccount(int accountId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  // Get transactions by date range
  Future<List<Transaction>> getTransactionsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'transaction_date BETWEEN ? AND ?',
      whereArgs: [
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  // Get transactions by category
  Future<List<Transaction>> getTransactionsByCategory(String category) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  // Get transactions by bank
  Future<List<Transaction>> getTransactionsByBank(String bankName) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'bank_name = ?',
      whereArgs: [bankName],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  // Get recent transactions (last N transactions)
  Future<List<Transaction>> getRecentTransactions({int limit = 10}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'transaction_date DESC',
      limit: limit,
    );
    
    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  // Get transaction by ID
  Future<Transaction?> getTransactionById(int id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isNotEmpty) {
      return Transaction.fromMap(maps.first);
    }
    return null;
  }

  // Get transaction by transaction ID (for duplicate detection)
  Future<Transaction?> getTransactionByTransactionId(String transactionId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
    
    if (maps.isNotEmpty) {
      return Transaction.fromMap(maps.first);
    }
    return null;
  }

  // Update transaction
  Future<int> updateTransaction(Transaction transaction) async {
    final db = await _dbHelper.database;
    return await db.update(
      'transactions',
      transaction.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  // Update transaction category
  Future<int> updateTransactionCategory(int transactionId, String category) async {
    final db = await _dbHelper.database;
    return await db.update(
      'transactions',
      {
        'category': category,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  // Delete transaction
  Future<int> deleteTransaction(int transactionId) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }

  // Get total expenses (debits) for a date range
  Future<double> getTotalExpenses({
    DateTime? startDate,
    DateTime? endDate,
    int? accountId,
  }) async {
    final db = await _dbHelper.database;
    
    String whereClause = 'transaction_type = ?';
    List<dynamic> whereArgs = ['debit'];
    
    if (startDate != null && endDate != null) {
      whereClause += ' AND transaction_date BETWEEN ? AND ?';
      whereArgs.addAll([startDate.toIso8601String(), endDate.toIso8601String()]);
    }
    
    if (accountId != null) {
      whereClause += ' AND account_id = ?';
      whereArgs.add(accountId);
    }
    
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE $whereClause',
      whereArgs,
    );
    
    return result.first['total'] as double? ?? 0.0;
  }

  // Get total income (credits) for a date range
  Future<double> getTotalIncome({
    DateTime? startDate,
    DateTime? endDate,
    int? accountId,
  }) async {
    final db = await _dbHelper.database;
    
    String whereClause = 'transaction_type = ?';
    List<dynamic> whereArgs = ['credit'];
    
    if (startDate != null && endDate != null) {
      whereClause += ' AND transaction_date BETWEEN ? AND ?';
      whereArgs.addAll([startDate.toIso8601String(), endDate.toIso8601String()]);
    }
    
    if (accountId != null) {
      whereClause += ' AND account_id = ?';
      whereArgs.add(accountId);
    }
    
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE $whereClause',
      whereArgs,
    );
    
    return result.first['total'] as double? ?? 0.0;
  }

  // Get spending by category for a date range
  Future<Map<String, double>> getSpendingByCategory({
    DateTime? startDate,
    DateTime? endDate,
    int? accountId,
  }) async {
    final db = await _dbHelper.database;
    
    String whereClause = 'transaction_type = ?';
    List<dynamic> whereArgs = ['debit'];
    
    if (startDate != null && endDate != null) {
      whereClause += ' AND transaction_date BETWEEN ? AND ?';
      whereArgs.addAll([startDate.toIso8601String(), endDate.toIso8601String()]);
    }
    
    if (accountId != null) {
      whereClause += ' AND account_id = ?';
      whereArgs.add(accountId);
    }
    
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT category, SUM(amount) as total FROM transactions WHERE $whereClause GROUP BY category',
      whereArgs,
    );
    
    Map<String, double> spendingByCategory = {};
    for (var map in maps) {
      spendingByCategory[map['category'] as String] = map['total'] as double? ?? 0.0;
    }
    
    return spendingByCategory;
  }

  // Get spending by bank for a date range
  Future<Map<String, double>> getSpendingByBank({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _dbHelper.database;
    
    String whereClause = 'transaction_type = ?';
    List<dynamic> whereArgs = ['debit'];
    
    if (startDate != null && endDate != null) {
      whereClause += ' AND transaction_date BETWEEN ? AND ?';
      whereArgs.addAll([startDate.toIso8601String(), endDate.toIso8601String()]);
    }
    
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT bank_name, SUM(amount) as total FROM transactions WHERE $whereClause GROUP BY bank_name',
      whereArgs,
    );
    
    Map<String, double> spendingByBank = {};
    for (var map in maps) {
      spendingByBank[map['bank_name'] as String] = map['total'] as double? ?? 0.0;
    }
    
    return spendingByBank;
  }

  // Get daily spending for the last N days
  Future<Map<String, double>> getDailySpending(int days) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT DATE(transaction_date) as date, SUM(amount) as total 
      FROM transactions 
      WHERE transaction_type = ? 
        AND transaction_date >= DATE('now', '-$days days')
      GROUP BY DATE(transaction_date)
      ORDER BY date
      ''',
      ['debit'],
    );
    
    Map<String, double> dailySpending = {};
    for (var map in maps) {
      dailySpending[map['date'] as String] = map['total'] as double? ?? 0.0;
    }
    
    return dailySpending;
  }

  // Get count of transactions
  Future<int> getTransactionCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM transactions');
    
    return result.first['count'] as int;
  }

  // Search transactions by description or merchant
  Future<List<Transaction>> searchTransactions(String query) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'description LIKE ? OR merchant LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  // Get transactions for a specific month and year
  Future<List<Transaction>> getTransactionsByMonth(int year, int month) async {
    final db = await _dbHelper.database;
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0, 23, 59, 59);
    
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'transaction_date BETWEEN ? AND ?',
      whereArgs: [
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return Transaction.fromMap(maps[i]);
    });
  }

  // Get unique categories from transactions
  Future<List<String>> getCategoriesFromTransactions() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT DISTINCT category FROM transactions ORDER BY category',
    );
    
    return maps.map((map) => map['category'] as String).toList();
  }
}
