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

  // Sets the balance from a parsed SMS, but only if [asOf] (the SMS's
  // transaction date) is not older than the balance currently on record.
  // `accounts.updated_at` doubles as "balance as of <date>" once the balance
  // is being driven by SMS parsing rather than direct user edits, so a
  // historical inbox message processed out of order (the OS inbox cursor
  // isn't guaranteed chronological, and the whole inbox is rescanned on every
  // sync) can't clobber a fresher balance with a stale one. Returns whether
  // the update was applied.
  Future<bool> updateBalanceIfNewer(
    int accountId,
    double balance,
    DateTime asOf,
  ) async {
    final db = await _dbHelper.database;
    final rows =
        await db.query('accounts', where: 'id = ?', whereArgs: [accountId]);
    if (rows.isEmpty) return false;

    final current = Account.fromMap(rows.first);
    if (asOf.isBefore(current.updatedAt)) return false;

    await db.update(
      'accounts',
      {
        'current_balance': balance,
        'updated_at': asOf.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [accountId],
    );
    return true;
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
  // Money the user actually owns. Credit card "balances" are available
  // credit limits, not funds, so they are excluded.
  Future<double> getTotalBalance() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT SUM(current_balance) as total FROM accounts '
      "WHERE is_active = 1 AND account_type != 'credit_card'",
    );

    return result.first['total'] as double? ?? 0.0;
  }

  // Combined available limit across active credit cards
  Future<double> getTotalAvailableCredit() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT SUM(current_balance) as total FROM accounts '
      "WHERE is_active = 1 AND account_type = 'credit_card'",
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
