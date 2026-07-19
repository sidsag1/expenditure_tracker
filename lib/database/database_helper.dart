import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../models/category.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static DatabaseHelper get instance => _instance;
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'expenditure_tracker.db');
    
    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    // Create Accounts table
    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_type TEXT NOT NULL,
        bank_name TEXT NOT NULL,
        account_number TEXT NOT NULL,
        account_name TEXT NOT NULL,
        current_balance REAL NOT NULL DEFAULT 0.0,
        debit_card_1 TEXT,
        debit_card_2 TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Create Categories table
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color TEXT NOT NULL,
        is_custom INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Create Transactions table
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER,
        transaction_type TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT NOT NULL,
        merchant TEXT,
        transaction_date TEXT NOT NULL,
        reference_number TEXT,
        transaction_id TEXT UNIQUE,
        category TEXT NOT NULL DEFAULT 'uncategorized',
        bank_name TEXT NOT NULL,
        account_type TEXT NOT NULL,
        is_manual INTEGER NOT NULL DEFAULT 0,
        is_pending INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE SET NULL
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_transactions_date ON transactions (transaction_date)');
    await db.execute('CREATE INDEX idx_transactions_account ON transactions (account_id)');
    await db.execute('CREATE INDEX idx_transactions_category ON transactions (category)');
    await db.execute('CREATE INDEX idx_accounts_bank ON accounts (bank_name)');
    await db.execute('CREATE INDEX idx_accounts_type ON accounts (account_type)');

    // Insert predefined categories
    await _insertPredefinedCategories(db);
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2: debit cards can be linked to the bank account they draw from
      await db.execute('ALTER TABLE accounts ADD COLUMN parent_account_id INTEGER');
    }
    if (oldVersion < 3) {
      // v3: debit cards are no longer separate accounts; they live on the
      // bank account itself as up to two card numbers. Fold existing
      // debit-card rows into their parent and remove them.
      await db.execute('ALTER TABLE accounts ADD COLUMN debit_card_1 TEXT');
      await db.execute('ALTER TABLE accounts ADD COLUMN debit_card_2 TEXT');

      final cards = await db.query(
        'accounts',
        where: "account_type = 'debit_card'",
      );
      for (final card in cards) {
        final parentId = card['parent_account_id'];
        if (parentId != null) {
          final parents = await db.query(
            'accounts',
            where: 'id = ?',
            whereArgs: [parentId],
          );
          if (parents.isNotEmpty) {
            final parent = parents.first;
            final slot =
                parent['debit_card_1'] == null ? 'debit_card_1' : 'debit_card_2';
            await db.update(
              'accounts',
              {slot: card['account_number']},
              where: 'id = ?',
              whereArgs: [parentId],
            );
          }
        }
        // Their transactions already point at the parent bank account
        await db.delete('accounts', where: 'id = ?', whereArgs: [card['id']]);
      }
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

  // Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  // Clear all data (for testing)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('accounts');
    await db.delete('categories');
    await _insertPredefinedCategories(db);
  }
}
