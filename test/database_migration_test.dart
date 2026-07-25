// Schema-migration tests. Each test hand-builds a database file matching a
// historical schema version (mirroring the real onCreate/onUpgrade history
// in lib/database/database_helper.dart), then opens it through the real
// DatabaseHelper singleton at the current version so the actual
// _upgradeDatabase code runs — not a reimplementation of it.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:expenditure_tracker/database/database_helper.dart';
import 'package:expenditure_tracker/models/category.dart';

import 'support/db_test_helper.dart';

// Every shipped version created the categories table and seeded it, and
// created these five indexes. _upgradeDatabase only ALTERs and UPDATEs — it
// never CREATEs — so a fixture that omits them produces a post-upgrade schema
// that can never exist in production: category-related migrations would look
// correct against it, and any later CategoryDAO/clearAllData() assertion would
// fail with "no such table: categories" and read as a production bug.
//
// The categories table itself is unchanged across v1..v4; only the transaction
// `category` *values* changed in v4, which is exactly what makes seeding it
// here load-bearing.
Future<void> _createLegacyCategoriesAndIndexes(Database db) async {
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
  final now = DateTime.now().toIso8601String();
  for (final category in Category.predefinedCategories) {
    await db.insert('categories', {
      'name': category.name,
      'icon': category.icon,
      'color': category.color,
      'is_custom': 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  await db.execute(
      'CREATE INDEX idx_transactions_date ON transactions (transaction_date)');
  await db.execute(
      'CREATE INDEX idx_transactions_account ON transactions (account_id)');
  await db.execute(
      'CREATE INDEX idx_transactions_category ON transactions (category)');
  await db.execute('CREATE INDEX idx_accounts_bank ON accounts (bank_name)');
  await db.execute('CREATE INDEX idx_accounts_type ON accounts (account_type)');
}

// Matches the very first shipped schema (see git history / test_deferred
// predecessor): no parent_account_id, no debit_card_1/2, category defaults
// to the old (buggy) 'uncategorized' spelling.
Future<Database> _createV1Schema(String path) {
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_type TEXT NOT NULL,
            bank_name TEXT NOT NULL,
            account_number TEXT NOT NULL,
            account_name TEXT NOT NULL,
            current_balance REAL NOT NULL DEFAULT 0.0,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
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
        await _createLegacyCategoriesAndIndexes(db);
      },
    ),
  );
}

// v2 added parent_account_id so a standalone debit_card "account" row could
// point back at the bank account it draws from.
Future<Database> _createV2Schema(String path) {
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_type TEXT NOT NULL,
            bank_name TEXT NOT NULL,
            account_number TEXT NOT NULL,
            account_name TEXT NOT NULL,
            current_balance REAL NOT NULL DEFAULT 0.0,
            parent_account_id INTEGER,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
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
        await _createLegacyCategoriesAndIndexes(db);
      },
    ),
  );
}

// v3 folded standalone debit-card accounts into debit_card_1/2 columns on
// the parent; this is the shape immediately before the v4 category fix.
Future<Database> _createV3Schema(String path) {
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_type TEXT NOT NULL,
            bank_name TEXT NOT NULL,
            account_number TEXT NOT NULL,
            account_name TEXT NOT NULL,
            current_balance REAL NOT NULL DEFAULT 0.0,
            parent_account_id INTEGER,
            debit_card_1 TEXT,
            debit_card_2 TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
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
        await _createLegacyCategoriesAndIndexes(db);
      },
    ),
  );
}

// v4 is structurally identical to v3 (v4 only normalized transaction
// `category` *values*, adding no columns), so a v4 install already has
// canonical-spelled categories baked in — unlike the v3 fixture, which
// deliberately seeds the old 'uncategorized' to prove the v4 step runs.
Future<Database> _createV4Schema(String path) {
  return databaseFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            account_type TEXT NOT NULL,
            bank_name TEXT NOT NULL,
            account_number TEXT NOT NULL,
            account_name TEXT NOT NULL,
            current_balance REAL NOT NULL DEFAULT 0.0,
            parent_account_id INTEGER,
            debit_card_1 TEXT,
            debit_card_2 TEXT,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
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
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE SET NULL
          )
        ''');
        await _createLegacyCategoriesAndIndexes(db);
      },
    ),
  );
}

void main() {
  setUp(() async {
    await resetTestDatabase();
  });

  tearDownAll(disposeTestDatabase);

  test('v1 -> v4: adds the new account columns and normalizes category',
      () async {
    final path = await testDatabasePath();
    final legacy = await _createV1Schema(path);
    final accountId = await legacy.insert('accounts', {
      'account_type': 'bank_account',
      'bank_name': 'ICICI',
      'account_number': 'XX1234',
      'account_name': 'Primary',
      'current_balance': 1000.0,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    // is_manual: 1 — this test is about the account-column/category-value
    // migrations, not the v5 step that purges is_manual = 0 rows (see the
    // 'v4 -> v5' group below), so the fixture must not collide with that.
    await legacy.insert('transactions', {
      'account_id': accountId,
      'transaction_type': 'debit',
      'amount': 50.0,
      'description': 'legacy row',
      'transaction_date': DateTime.now().toIso8601String(),
      'category': 'uncategorized',
      'bank_name': 'ICICI',
      'account_type': 'bank_account',
      'is_manual': 1,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await legacy.close();

    // Reopening through the real DatabaseHelper singleton triggers the
    // actual production onUpgrade path (v1 -> v4).
    final db = await DatabaseHelper.instance.database;

    final columns = await db.rawQuery('PRAGMA table_info(accounts)');
    final columnNames = columns.map((c) => c['name']).toSet();
    expect(columnNames, containsAll(['parent_account_id', 'debit_card_1', 'debit_card_2']));

    final accounts = await db.query('accounts');
    expect(accounts, hasLength(1));
    expect(accounts.single['bank_name'], 'ICICI');
    expect(accounts.single['current_balance'], 1000.0);

    final transactions = await db.query('transactions');
    expect(transactions, hasLength(1));
    expect(transactions.single['category'], 'Uncategorized');
    expect(transactions.single['description'], 'legacy row');

    // The upgrade path never CREATEs, so the pre-existing categories table has
    // to come through untouched — including the seeded row that the normalized
    // transaction category now points at.
    final categories = await db.query('categories');
    expect(categories, hasLength(Category.predefinedCategories.length));
    expect(
      categories.map((c) => c['name']),
      contains(transactions.single['category']),
    );

    // Indexes created in v1 are still present after upgrading.
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'",
    );
    expect(
      indexes.map((i) => i['name']).toSet(),
      containsAll([
        'idx_transactions_date',
        'idx_transactions_account',
        'idx_transactions_category',
        'idx_accounts_bank',
        'idx_accounts_type',
      ]),
    );
  });

  test('v1 -> v4: a user-created custom category survives the upgrade',
      () async {
    final path = await testDatabasePath();
    final legacy = await _createV1Schema(path);
    final now = DateTime.now().toIso8601String();
    await legacy.insert('categories', {
      'name': 'Aquarium Supplies',
      'icon': '🐠',
      'color': '#00BCD4',
      'is_custom': 1,
      'created_at': now,
      'updated_at': now,
    });
    await legacy.close();

    final db = await DatabaseHelper.instance.database;

    final custom = await db.query(
      'categories',
      where: 'is_custom = 1',
    );
    expect(custom, hasLength(1));
    expect(custom.single['name'], 'Aquarium Supplies');
    expect(custom.single['icon'], '🐠');

    // The seeded rows must not have been duplicated by re-running the seed.
    final all = await db.query('categories');
    expect(all, hasLength(Category.predefinedCategories.length + 1));
  });

  test('v2 -> v4: folds a single standalone debit-card account into the parent',
      () async {
    final path = await testDatabasePath();
    final legacy = await _createV2Schema(path);
    final now = DateTime.now().toIso8601String();
    final parentId = await legacy.insert('accounts', {
      'account_type': 'bank_account',
      'bank_name': 'Kotak',
      'account_number': 'XX5555',
      'account_name': 'Primary',
      'current_balance': 2000.0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    await legacy.insert('accounts', {
      'account_type': 'debit_card',
      'bank_name': 'Kotak',
      'account_number': '1234567890123',
      'account_name': 'Debit Card',
      'current_balance': 0.0,
      'parent_account_id': parentId,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    // Its transactions already point at the parent bank account, per the
    // real migration's assumption. is_manual: 1 so this row isn't swept up
    // by the unrelated v5 is_manual = 0 purge (see the 'v4 -> v5' group).
    await legacy.insert('transactions', {
      'account_id': parentId,
      'transaction_type': 'debit',
      'amount': 75.0,
      'description': 'card spend',
      'transaction_date': now,
      'category': 'uncategorized',
      'bank_name': 'Kotak',
      'account_type': 'debit_card',
      'is_manual': 1,
      'created_at': now,
      'updated_at': now,
    });
    await legacy.close();

    final db = await DatabaseHelper.instance.database;

    final cardRows = await db.query('accounts', where: "account_type = 'debit_card'");
    expect(cardRows, isEmpty);

    final parent = await db.query('accounts', where: 'id = ?', whereArgs: [parentId]);
    expect(parent.single['debit_card_1'], '1234567890123');
    expect(parent.single['debit_card_2'], isNull);

    final transactions = await db.query('transactions');
    expect(transactions.single['category'], 'Uncategorized');
  });

  test('v2 -> v4: folds two standalone debit-card accounts into both slots',
      () async {
    final path = await testDatabasePath();
    final legacy = await _createV2Schema(path);
    final now = DateTime.now().toIso8601String();
    final parentId = await legacy.insert('accounts', {
      'account_type': 'bank_account',
      'bank_name': 'Kotak',
      'account_number': 'XX5555',
      'account_name': 'Primary',
      'current_balance': 2000.0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    for (final cardNumber in ['1111', '2222']) {
      await legacy.insert('accounts', {
        'account_type': 'debit_card',
        'bank_name': 'Kotak',
        'account_number': cardNumber,
        'account_name': 'Debit Card',
        'current_balance': 0.0,
        'parent_account_id': parentId,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    }
    await legacy.close();

    final db = await DatabaseHelper.instance.database;

    final parent = await db.query('accounts', where: 'id = ?', whereArgs: [parentId]);
    final slots = {parent.single['debit_card_1'], parent.single['debit_card_2']};
    expect(slots, {'1111', '2222'});

    final cardRows = await db.query('accounts', where: "account_type = 'debit_card'");
    expect(cardRows, isEmpty);
  });

  test('v3 -> v4: only normalizes category, leaves existing columns untouched',
      () async {
    final path = await testDatabasePath();
    final legacy = await _createV3Schema(path);
    final now = DateTime.now().toIso8601String();
    final accountId = await legacy.insert('accounts', {
      'account_type': 'bank_account',
      'bank_name': 'SBI',
      'account_number': 'XX7777',
      'account_name': 'Primary',
      'current_balance': 3000.0,
      'debit_card_1': '9999',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
    });
    // is_manual: 1 so this row isn't swept up by the unrelated v5
    // is_manual = 0 purge (see the 'v4 -> v5' group).
    await legacy.insert('transactions', {
      'account_id': accountId,
      'transaction_type': 'credit',
      'amount': 500.0,
      'description': 'salary',
      'transaction_date': now,
      'category': 'uncategorized',
      'bank_name': 'SBI',
      'account_type': 'bank_account',
      'is_manual': 1,
      'created_at': now,
      'updated_at': now,
    });
    await legacy.close();

    final db = await DatabaseHelper.instance.database;

    final accounts = await db.query('accounts');
    expect(accounts.single['debit_card_1'], '9999');

    final transactions = await db.query('transactions');
    expect(transactions.single['category'], 'Uncategorized');
  });

  test('a fresh v4 install seeds the predefined categories with the canonical spelling',
      () async {
    final db = await DatabaseHelper.instance.database;
    final categories = await db.query('categories', where: 'name = ?', whereArgs: ['Uncategorized']);
    expect(categories, hasLength(1));
  });

  group('v4 -> v5 (P2-1/P2-2/P2-3/P2-4/P2-5)', () {
    test('adds the new columns and index, and defaults a surviving manual row\'s source to manual',
        () async {
      final path = await testDatabasePath();
      final legacy = await _createV4Schema(path);
      final now = DateTime.now().toIso8601String();
      final accountId = await legacy.insert('accounts', {
        'account_type': 'bank_account',
        'bank_name': 'ICICI',
        'account_number': 'XX1234',
        'account_name': 'Primary',
        'current_balance': 1000.0,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      final manualRowId = await legacy.insert('transactions', {
        'account_id': accountId,
        'transaction_type': 'debit',
        'amount': 75.0,
        'description': 'manual entry',
        'transaction_date': now,
        'category': 'Uncategorized',
        'bank_name': 'ICICI',
        'account_type': 'bank_account',
        'is_manual': 1,
        'created_at': now,
        'updated_at': now,
      });
      await legacy.close();

      final db = await DatabaseHelper.instance.database;

      final columns = await db.rawQuery('PRAGMA table_info(transactions)');
      final columnNames = columns.map((c) => c['name']).toSet();
      expect(
        columnNames,
        containsAll([
          'balance_after',
          'is_transfer',
          'needs_review',
          'source',
          'raw_message_hash',
        ]),
      );

      final manualRow = (await db.query('transactions',
              where: 'id = ?', whereArgs: [manualRowId]))
          .single;
      expect(manualRow['source'], 'manual');
      expect(manualRow['is_transfer'], 0);
      expect(manualRow['needs_review'], 0);
      expect(manualRow['balance_after'], isNull);

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_transactions_transaction_id'",
      );
      expect(indexes, hasLength(1));
    });

    test(
        'deletes every SMS-imported (is_manual = 0) row, linked or not, so the '
        'next sync reinserts them through the current parser; manual rows survive',
        () async {
      final path = await testDatabasePath();
      final legacy = await _createV4Schema(path);
      final now = DateTime.now().toIso8601String();
      final accountId = await legacy.insert('accounts', {
        'account_type': 'bank_account',
        'bank_name': 'ICICI',
        'account_number': 'XX1234',
        'account_name': 'Primary',
        'current_balance': 1000.0,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      // Stale: an old build's auto-import that never matched an account.
      await legacy.insert('transactions', {
        'account_id': null,
        'transaction_type': 'debit',
        'amount': 10.0,
        'description': 'unlinked auto import',
        'transaction_date': now,
        'category': 'Uncategorized',
        'bank_name': 'ICICI',
        'account_type': 'bank_account',
        'is_manual': 0,
        'created_at': now,
        'updated_at': now,
      });
      // A parser bug that predates this migration (e.g. P0-3's December ->
      // January bug) may have produced a *linked*, otherwise normal-looking
      // auto-import; it must be wiped too, not just the unlinked ones, so the
      // next full-inbox sync can re-parse it correctly.
      await legacy.insert('transactions', {
        'account_id': accountId,
        'transaction_type': 'debit',
        'amount': 30.0,
        'description': 'linked auto import from a buggy parser',
        'transaction_date': now,
        'category': 'Uncategorized',
        'bank_name': 'ICICI',
        'account_type': 'bank_account',
        'is_manual': 0,
        'created_at': now,
        'updated_at': now,
      });
      // A manual entry with no account is a deliberate user choice, not
      // stale data, and must survive.
      final manualUnlinkedId = await legacy.insert('transactions', {
        'account_id': null,
        'transaction_type': 'debit',
        'amount': 20.0,
        'description': 'manual, no account',
        'transaction_date': now,
        'category': 'Uncategorized',
        'bank_name': '',
        'account_type': '',
        'is_manual': 1,
        'created_at': now,
        'updated_at': now,
      });
      final manualLinkedId = await legacy.insert('transactions', {
        'account_id': accountId,
        'transaction_type': 'debit',
        'amount': 40.0,
        'description': 'manual, with account',
        'transaction_date': now,
        'category': 'Uncategorized',
        'bank_name': 'ICICI',
        'account_type': 'bank_account',
        'is_manual': 1,
        'created_at': now,
        'updated_at': now,
      });
      await legacy.close();

      final db = await DatabaseHelper.instance.database;

      final remainingIds =
          (await db.query('transactions')).map((r) => r['id']).toSet();
      expect(remainingIds, {manualUnlinkedId, manualLinkedId});
    });
  });
}
