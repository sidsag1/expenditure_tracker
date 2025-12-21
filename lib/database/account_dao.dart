import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../models/account.dart';

class AccountDAO {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Create a new account
  Future<int> insertAccount(Account account) async {
    final db = await _dbHelper.database;
    return await db.insert(
      'accounts',
      account.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // Get all accounts
  Future<List<Account>> getAllAccounts() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('accounts');
    
    return List.generate(maps.length, (i) {
      return Account.fromMap(maps[i]);
    });
  }

  // Get active accounts only
  Future<List<Account>> getActiveAccounts() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'accounts',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'bank_name ASC',
    );
    
    return List.generate(maps.length, (i) {
      return Account.fromMap(maps[i]);
    });
  }

  // Get accounts by type
  Future<List<Account>> getAccountsByType(String accountType) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'accounts',
      where: 'account_type = ? AND is_active = ?',
      whereArgs: [accountType, 1],
      orderBy: 'bank_name ASC',
    );
    
    return List.generate(maps.length, (i) {
      return Account.fromMap(maps[i]);
    });
  }

  // Get accounts by bank
  Future<List<Account>> getAccountsByBank(String bankName) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'accounts',
      where: 'bank_name = ? AND is_active = ?',
      whereArgs: [bankName, 1],
      orderBy: 'account_type ASC',
    );
    
    return List.generate(maps.length, (i) {
      return Account.fromMap(maps[i]);
    });
  }

  // Get account by ID
  Future<Account?> getAccountById(int id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isNotEmpty) {
      return Account.fromMap(maps.first);
    }
    return null;
  }

  // Update account
  Future<int> updateAccount(Account account) async {
    final db = await _dbHelper.database;
    return await db.update(
      'accounts',
      account.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  // Update account balance
  Future<int> updateAccountBalance(int accountId, double newBalance) async {
    final db = await _dbHelper.database;
    return await db.update(
      'accounts',
      {
        'current_balance': newBalance,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  // Delete account (soft delete - set is_active to false)
  Future<int> deleteAccount(int accountId) async {
    final db = await _dbHelper.database;
    return await db.update(
      'accounts',
      {
        'is_active': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  // Hard delete account (for testing only)
  Future<int> hardDeleteAccount(int accountId) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'accounts',
      where: 'id = ?',
      whereArgs: [accountId],
    );
  }

  // Get total balance across all active accounts
  Future<double> getTotalBalance() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT SUM(current_balance) as total FROM accounts WHERE is_active = 1',
    );
    
    return result.first['total'] as double? ?? 0.0;
  }

  // Get accounts with total balance by bank
  Future<Map<String, double>> getBalanceByBank() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT bank_name, SUM(current_balance) as total FROM accounts WHERE is_active = 1 GROUP BY bank_name',
    );
    
    Map<String, double> balanceByBank = {};
    for (var map in maps) {
      balanceByBank[map['bank_name'] as String] = map['total'] as double? ?? 0.0;
    }
    
    return balanceByBank;
  }

  // Get accounts with total balance by type
  Future<Map<String, double>> getBalanceByAccountType() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT account_type, SUM(current_balance) as total FROM accounts WHERE is_active = 1 GROUP BY account_type',
    );
    
    Map<String, double> balanceByType = {};
    for (var map in maps) {
      balanceByType[map['account_type'] as String] = map['total'] as double? ?? 0.0;
    }
    
    return balanceByType;
  }

  // Check if account number already exists
  Future<bool> accountNumberExists(String accountNumber) async {
    final db = await _dbHelper.database;
    final result = await db.query(
      'accounts',
      where: 'account_number = ? AND is_active = ?',
      whereArgs: [accountNumber, 1],
    );
    
    return result.isNotEmpty;
  }

  // Get count of accounts
  Future<int> getAccountCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM accounts WHERE is_active = 1',
    );
    
    return result.first['count'] as int;
  }
}
