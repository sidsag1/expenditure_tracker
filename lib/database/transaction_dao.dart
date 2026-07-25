import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../models/transaction.dart' as models;

// Result of comparing a not-yet-saved transaction against rows already on
// the same account for the same type/amount/day.
enum DuplicateMatch {
  // No same-account/type/amount/day row exists at all.
  none,
  // A candidate exists and shares a strong signal (matching reference
  // number, matching normalised merchant, or both rows are the no-ref/
  // no-merchant "payment received" / "credited to your card" confirmation
  // pattern banks send twice for one bill payment) — the same real-world
  // event, safe to drop.
  confirmed,
  // A candidate exists but none of those signals agree (e.g. two same-day,
  // same-amount purchases with no reference number on either side). Import
  // it rather than silently discarding real money, but flag it for review.
  ambiguous,
}

class TransactionDAO {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Create a new transaction
  Future<int> insertTransaction(models.Transaction transaction) async {
    final db = await _dbHelper.database;
    return await db.insert(
      'transactions',
      transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  // Insert or ignore if transaction ID already exists (for duplicate prevention)
  Future<int> insertOrIgnoreTransaction(models.Transaction transaction) async {
    final db = await _dbHelper.database;
    return await db.insert(
      'transactions',
      transaction.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // Compares a not-yet-saved transaction against rows already on the same
  // account for the same type/amount/day. See DuplicateMatch for what each
  // outcome means. Matching purely on same account/type/amount/day (the old
  // behaviour) silently dropped genuinely distinct transactions — e.g. two
  // ₹50 coffees on the same card in one day — so a real signal is now
  // required to treat a candidate as confirmed.
  Future<DuplicateMatch> findDuplicateMatch(
      models.Transaction transaction) async {
    if (transaction.accountId == null) return DuplicateMatch.none;

    final db = await _dbHelper.database;
    final day = transaction.transactionDate;
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final rows = await db.query(
      'transactions',
      where: 'account_id = ? AND transaction_type = ? AND amount = ? '
          'AND transaction_date >= ? AND transaction_date < ?',
      whereArgs: [
        transaction.accountId,
        transaction.transactionType,
        transaction.amount,
        dayStart.toIso8601String(),
        dayEnd.toIso8601String(),
      ],
    );

    if (rows.isEmpty) return DuplicateMatch.none;

    final newRef = transaction.referenceNumber;
    final newMerchant = _normalizeMerchant(transaction.merchant);

    for (final row in rows) {
      final existingRef = row['reference_number'] as String?;
      if (existingRef != null && newRef != null && existingRef == newRef) {
        return DuplicateMatch.confirmed;
      }

      final existingMerchant = _normalizeMerchant(row['merchant'] as String?);
      if (existingMerchant != null &&
          newMerchant != null &&
          existingMerchant == newMerchant) {
        return DuplicateMatch.confirmed;
      }

      // Credit-card bill payment notifications ("payment received towards
      // your card" / "credited to your card") carry no reference number or
      // merchant on either message, so two such rows on the same day/amount
      // are the bank's own confirmation pair for one event, not a
      // coincidence.
      if (transaction.isTransfer && (row['is_transfer'] as int? ?? 0) == 1) {
        return DuplicateMatch.confirmed;
      }
    }

    return DuplicateMatch.ambiguous;
  }

  String? _normalizeMerchant(String? merchant) {
    if (merchant == null) return null;
    final trimmed = merchant.trim().toLowerCase();
    return trimmed.isEmpty ? null : trimmed;
  }

  // Finds a transaction on a *different* registered account, opposite
  // direction, same amount, within [window] of this one — the fingerprint of
  // one leg of an internal transfer (e.g. a credit-card bill payment: a debit
  // on the bank account and a credit on the card for the same amount).
  Future<models.Transaction?> findOffsettingTransaction(
    models.Transaction transaction, {
    Duration window = const Duration(days: 2),
  }) async {
    if (transaction.accountId == null) return null;

    final db = await _dbHelper.database;
    final oppositeType =
        transaction.transactionType == 'debit' ? 'credit' : 'debit';
    final start = transaction.transactionDate.subtract(window);
    final end = transaction.transactionDate.add(window);

    final rows = await db.query(
      'transactions',
      where: 'account_id IS NOT NULL AND account_id != ? AND '
          'transaction_type = ? AND amount = ? AND '
          'transaction_date >= ? AND transaction_date <= ?',
      whereArgs: [
        transaction.accountId,
        oppositeType,
        transaction.amount,
        start.toIso8601String(),
        end.toIso8601String(),
      ],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return models.Transaction.fromMap(rows.first);
  }

  // Marks both legs of an internal transfer so income/expense aggregates
  // exclude them while statements still show them.
  Future<void> markTransferPair(int id1, int id2) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    batch.update('transactions', {'is_transfer': 1},
        where: 'id = ?', whereArgs: [id1]);
    batch.update('transactions', {'is_transfer': 1},
        where: 'id = ?', whereArgs: [id2]);
    await batch.commit(noResult: true);
  }

  // Delete SMS-imported transactions that were never linked to a registered
  // account (saved by builds that predate account matching).
  Future<int> deleteUnlinkedAutoTransactions() async {
    final db = await _dbHelper.database;
    return await db.delete(
      'transactions',
      where: 'is_manual = 0 AND account_id IS NULL',
    );
  }

  // Delete ALL SMS-imported transactions. Used for a one-time clean
  // re-import after parser fixes; manual entries are untouched.
  Future<int> deleteAutoImportedTransactions() async {
    final db = await _dbHelper.database;
    return await db.delete(
      'transactions',
      where: 'is_manual = 0',
    );
  }

  // Get all transactions
  Future<List<models.Transaction>> getAllTransactions() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return models.Transaction.fromMap(maps[i]);
    });
  }

  // Get transactions by account
  Future<List<models.Transaction>> getTransactionsByAccount(int accountId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return models.Transaction.fromMap(maps[i]);
    });
  }

  // Get transactions in the half-open range [startDate, endDate).
  //
  // Half-open rather than BETWEEN: transaction_date is a full ISO-8601
  // timestamp, so an inclusive upper bound has to be fudged to 23:59:59 and
  // then silently drops anything in the last second of the range (a row at
  // 23:59:59.500). Callers pass the start of the day *after* the last day they
  // want. Matches _appendDateRange, which every other range query uses.
  Future<List<models.Transaction>> getTransactionsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'transaction_date >= ? AND transaction_date < ?',
      whereArgs: [
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return models.Transaction.fromMap(maps[i]);
    });
  }

  // Get transactions by category
  Future<List<models.Transaction>> getTransactionsByCategory(String category) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'category = ?',
      whereArgs: [category],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return models.Transaction.fromMap(maps[i]);
    });
  }

  // Get transactions by bank
  Future<List<models.Transaction>> getTransactionsByBank(String bankName) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'bank_name = ?',
      whereArgs: [bankName],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return models.Transaction.fromMap(maps[i]);
    });
  }

  // Get recent transactions (last N transactions)
  Future<List<models.Transaction>> getRecentTransactions({int limit = 10}) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      orderBy: 'transaction_date DESC',
      limit: limit,
    );
    
    return List.generate(maps.length, (i) {
      return models.Transaction.fromMap(maps[i]);
    });
  }

  // Get transaction by ID
  Future<models.Transaction?> getTransactionById(int id) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    
    if (maps.isNotEmpty) {
      return models.Transaction.fromMap(maps.first);
    }
    return null;
  }

  // Get transaction by transaction ID (for duplicate detection)
  Future<models.Transaction?> getTransactionByTransactionId(String transactionId) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
    
    if (maps.isNotEmpty) {
      return models.Transaction.fromMap(maps.first);
    }
    return null;
  }

  // Update transaction
  Future<int> updateTransaction(models.Transaction transaction) async {
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

  // Appends independent, half-open (>= start AND < end) date bounds to a
  // WHERE clause. Each bound applies on its own so a caller passing only
  // one of startDate/endDate still filters correctly.
  void _appendDateRange(
    List<String> clauses,
    List<dynamic> args,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    if (startDate != null) {
      clauses.add('transaction_date >= ?');
      args.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      clauses.add('transaction_date < ?');
      args.add(endDate.toIso8601String());
    }
  }

  // Get total expenses (debits) for a date range. Excludes transfers (e.g. a
  // credit-card bill payment debit) — those move money between the user's
  // own accounts rather than spending it.
  Future<double> getTotalExpenses({
    DateTime? startDate,
    DateTime? endDate,
    int? accountId,
  }) async {
    final db = await _dbHelper.database;

    final clauses = ['transaction_type = ?', 'is_transfer = 0'];
    final whereArgs = <dynamic>['debit'];

    _appendDateRange(clauses, whereArgs, startDate, endDate);

    if (accountId != null) {
      clauses.add('account_id = ?');
      whereArgs.add(accountId);
    }

    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE ${clauses.join(' AND ')}',
      whereArgs,
    );

    return result.first['total'] as double? ?? 0.0;
  }

  // Get total income (credits) for a date range. Excludes transfers (e.g. a
  // credit-card bill payment landing on the card) — those aren't new money.
  Future<double> getTotalIncome({
    DateTime? startDate,
    DateTime? endDate,
    int? accountId,
  }) async {
    final db = await _dbHelper.database;

    final clauses = ['transaction_type = ?', 'is_transfer = 0'];
    final whereArgs = <dynamic>['credit'];

    _appendDateRange(clauses, whereArgs, startDate, endDate);

    if (accountId != null) {
      clauses.add('account_id = ?');
      whereArgs.add(accountId);
    }

    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM transactions WHERE ${clauses.join(' AND ')}',
      whereArgs,
    );

    return result.first['total'] as double? ?? 0.0;
  }

  // Get spending by category for a date range. Excludes transfers.
  Future<Map<String, double>> getSpendingByCategory({
    DateTime? startDate,
    DateTime? endDate,
    int? accountId,
  }) async {
    final db = await _dbHelper.database;

    final clauses = ['transaction_type = ?', 'is_transfer = 0'];
    final whereArgs = <dynamic>['debit'];

    _appendDateRange(clauses, whereArgs, startDate, endDate);

    if (accountId != null) {
      clauses.add('account_id = ?');
      whereArgs.add(accountId);
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT category, SUM(amount) as total FROM transactions WHERE ${clauses.join(' AND ')} GROUP BY category',
      whereArgs,
    );

    Map<String, double> spendingByCategory = {};
    for (var map in maps) {
      spendingByCategory[map['category'] as String] = map['total'] as double? ?? 0.0;
    }

    return spendingByCategory;
  }

  // Get spending by bank for a date range. Excludes transfers.
  Future<Map<String, double>> getSpendingByBank({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _dbHelper.database;

    final clauses = ['transaction_type = ?', 'is_transfer = 0'];
    final whereArgs = <dynamic>['debit'];

    _appendDateRange(clauses, whereArgs, startDate, endDate);

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT bank_name, SUM(amount) as total FROM transactions WHERE ${clauses.join(' AND ')} GROUP BY bank_name',
      whereArgs,
    );

    Map<String, double> spendingByBank = {};
    for (var map in maps) {
      spendingByBank[map['bank_name'] as String] = map['total'] as double? ?? 0.0;
    }

    return spendingByBank;
  }

  // Get daily spending for the last N days. Excludes transfers.
  Future<Map<String, double>> getDailySpending(int days) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT DATE(transaction_date) as date, SUM(amount) as total
      FROM transactions
      WHERE transaction_type = ? AND is_transfer = 0
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
  Future<List<models.Transaction>> searchTransactions(String query) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'description LIKE ? OR merchant LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return models.Transaction.fromMap(maps[i]);
    });
  }

  // Get transactions for a specific month and year
  Future<List<models.Transaction>> getTransactionsByMonth(int year, int month) async {
    final db = await _dbHelper.database;
    // [first of this month, first of next month) — half-open, so the last
    // second of the last day can't fall outside the range. DateTime rolls
    // month 13 over to January of the next year on its own.
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 1);

    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'transaction_date >= ? AND transaction_date < ?',
      whereArgs: [
        startDate.toIso8601String(),
        endDate.toIso8601String(),
      ],
      orderBy: 'transaction_date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return models.Transaction.fromMap(maps[i]);
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
