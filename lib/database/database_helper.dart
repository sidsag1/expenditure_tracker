import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/category.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static DatabaseHelper get instance => _instance;
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  // Caches the in-flight open, not just the resolved Database: two callers
  // racing the getter before the first open completes (e.g. two DAOs' first
  // queries firing off `Future.wait`) both see `_database == null` and, without
  // this, would each call openDatabase() — the second one either explodes on
  // sqflite's single-open-per-path lock or silently opens the file twice.
  static Future<Database>? _openingFuture;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    return _openingFuture ??= _openOnce();
  }

  Future<Database> _openOnce() async {
    final db = await _initDatabase();
    _database = db;
    _openingFuture = null;
    return db;
  }

  Future<String> _databasePath() async =>
      join(await getDatabasesPath(), 'expenditure_tracker.db');

  Future<Database> _initDatabase() async {
    final path = await _databasePath();

    return await openDatabase(
      path,
      version: 7,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
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
        category TEXT NOT NULL DEFAULT 'Uncategorized',
        bank_name TEXT NOT NULL,
        account_type TEXT NOT NULL,
        is_manual INTEGER NOT NULL DEFAULT 0,
        is_pending INTEGER NOT NULL DEFAULT 0,
        balance_after REAL,
        is_transfer INTEGER NOT NULL DEFAULT 0,
        needs_review INTEGER NOT NULL DEFAULT 0,
        source TEXT NOT NULL DEFAULT 'manual',
        raw_message_hash TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE SET NULL
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_transactions_date ON transactions (transaction_date)');
    await db.execute('CREATE INDEX idx_transactions_account ON transactions (account_id)');
    await db.execute('CREATE INDEX idx_transactions_category ON transactions (category)');
    await db.execute('CREATE INDEX idx_transactions_transaction_id ON transactions (transaction_id)');
    await db.execute('CREATE INDEX idx_accounts_bank ON accounts (bank_name)');
    await db.execute('CREATE INDEX idx_accounts_type ON accounts (account_type)');
    await db.execute('CREATE INDEX idx_transactions_bank ON transactions (bank_name)');
    await db.execute(
        'CREATE INDEX idx_transactions_account_date ON transactions (account_id, transaction_date)');
    await db.execute(
        'CREATE INDEX idx_transactions_type_transfer_date ON transactions (transaction_type, is_transfer, transaction_date)');
    await db.execute(
        'CREATE INDEX idx_transactions_amount_type_date ON transactions (amount, transaction_type, transaction_date)');

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
    if (oldVersion < 4) {
      // v4: 'uncategorized' (old Transaction model/schema default) never
      // matched the seeded category name 'Uncategorized', which broke the
      // category dropdown for any transaction left at the default. Normalize
      // existing rows to the one canonical spelling.
      await db.update(
        'transactions',
        {'category': 'Uncategorized'},
        where: 'category = ?',
        whereArgs: ['uncategorized'],
      );
    }
    if (oldVersion < 5) {
      // v5: accounting-correctness columns (P2-1/P2-2/P2-3). balance_after
      // carries the account balance/limit parsed out of the SMS that produced
      // a row; is_transfer marks a leg of an internal money movement (e.g. a
      // credit-card bill payment) so income/expense aggregates can exclude it;
      // needs_review flags an ambiguous possible-duplicate that was imported
      // rather than silently dropped; source records how a row was created.
      await db.execute('ALTER TABLE transactions ADD COLUMN balance_after REAL');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN is_transfer INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE transactions ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          "ALTER TABLE transactions ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'");
      await db.execute('ALTER TABLE transactions ADD COLUMN raw_message_hash TEXT');
      await db.execute(
          'CREATE INDEX idx_transactions_transaction_id ON transactions (transaction_id)');

      // Every SMS-imported row on a pre-v5 install was produced by a parser
      // that predates the P0-3 (wrong month), P0-4 (fabricated dates) and
      // P0-5 (category casing) fixes — and, further back, predates account
      // matching altogether, so some rows never matched a registered account
      // at all. Rather than try to patch each historical row in place, wipe
      // every auto-imported row once and let SMSService.syncMessages's
      // unconditional full-inbox rescan reinsert everything through the
      // current parser on the next sync. Manual entries are untouched. This
      // folds what used to be a SharedPreferences-gated "have I already done
      // this?" one-time hack (_reimportFlagKey) plus a separate every-sync
      // cleanup query in SMSService into this one versioned migration, which
      // is inherently one-time and idempotent per install.
      //
      // The 'source' column is left at its ALTER-added default ('manual')
      // for every row still standing after this delete, which is correct:
      // nothing is_manual = 0 survives it, so there is nothing left to
      // backfill to 'sms'.
      await db.delete(
        'transactions',
        where: 'is_manual = 0',
      );
    }
    if (oldVersion < 6) {
      // v6: bank-filtered dashboard queries and paginated/aggregate
      // transaction fetches were doing full-table scans and an in-memory
      // filesort with no supporting index.
      await db.execute('CREATE INDEX idx_transactions_bank ON transactions (bank_name)');
      await db.execute(
          'CREATE INDEX idx_transactions_account_date ON transactions (account_id, transaction_date)');
      await db.execute(
          'CREATE INDEX idx_transactions_type_transfer_date ON transactions (transaction_type, is_transfer, transaction_date)');
    }
    if (oldVersion < 7) {
      // v7: index for findOffsettingTransaction
      await db.execute(
          'CREATE INDEX idx_transactions_amount_type_date ON transactions (amount, transaction_type, transaction_date)');
    }
  }

  Future<void> _insertPredefinedCategories(DatabaseExecutor db) async {
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

  // Close database.
  //
  // Deliberately does NOT go through the `database` getter: that would open
  // (and migrate, or create from scratch) a database purely in order to close
  // it, leaving a stray file behind on every close-when-already-closed —
  // including the second of two consecutive close() calls.
  Future<void> close() async {
    // An open already in flight: wait for it rather than leaving it to land
    // after close() returns, which would silently reopen the database.
    final pending = _openingFuture;
    if (pending != null) {
      _openingFuture = null;
      final db = await pending;
      _database = null;
      await db.close();
      return;
    }
    final db = _database;
    if (db == null) return;
    _database = null;
    await db.close();
  }

  // Clear all data (for testing). Wrapped in a single transaction so a crash
  // partway through can't leave the database with some tables wiped and
  // others (or the predefined-category reseed) not, which the app has no
  // way to detect or repair on next launch.
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('accounts');
      await txn.delete('categories');
      await _insertPredefinedCategories(txn);
    });
  }

  // Deletes the database file outright (as opposed to clearAllData, which
  // deletes rows). Used for a full app reset: close any open handle first so
  // the delete isn't fighting a live connection, then remove the file.
  Future<void> deleteDatabaseFile() async {
    await close();
    final path = await _databasePath();
    await deleteDatabase(path);
  }
}
