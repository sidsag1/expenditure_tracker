// DAO-level tests backed by a real (ffi) SQLite database. Covers every
// CategoryDAO method.

import 'package:flutter_test/flutter_test.dart';

import 'package:expenditure_tracker/database/category_dao.dart';
import 'package:expenditure_tracker/database/transaction_dao.dart';
import 'package:expenditure_tracker/database/account_dao.dart';
import 'package:expenditure_tracker/models/category.dart';

import 'support/db_test_helper.dart';

void main() {
  late CategoryDAO categoryDAO;

  setUp(() async {
    await resetTestDatabase();
    categoryDAO = CategoryDAO();
  });

  tearDownAll(disposeTestDatabase);

  test('a fresh database is seeded with the predefined categories', () async {
    final all = await categoryDAO.getAllCategories();
    expect(all, hasLength(Category.predefinedCategories.length));
    expect(all.every((c) => !c.isCustom), isTrue);
  });

  test('insertCategory / getCategoryById round-trips all fields', () async {
    final id = await categoryDAO.insertCategory(testCategory(
      name: 'Pets',
      icon: '🐾',
      color: '#AABBCC',
    ));

    final fetched = await categoryDAO.getCategoryById(id);
    expect(fetched, isNotNull);
    expect(fetched!.name, 'Pets');
    expect(fetched.icon, '🐾');
    expect(fetched.color, '#AABBCC');
    expect(fetched.isCustom, isTrue);
  });

  test('getCategoryById returns null for a missing id', () async {
    expect(await categoryDAO.getCategoryById(99999), isNull);
  });

  test('getPredefinedCategories / getCustomCategories partition correctly',
      () async {
    await categoryDAO.insertCategory(testCategory(name: 'Custom A'));

    final predefined = await categoryDAO.getPredefinedCategories();
    final custom = await categoryDAO.getCustomCategories();

    expect(predefined, hasLength(Category.predefinedCategories.length));
    expect(custom, hasLength(1));
    expect(custom.single.name, 'Custom A');
  });

  test('getCategoryByName finds a case-sensitive exact match', () async {
    final found = await categoryDAO.getCategoryByName('Uncategorized');
    expect(found, isNotNull);
    expect(found!.name, 'Uncategorized');

    expect(await categoryDAO.getCategoryByName('uncategorized'), isNull);
  });

  test('updateCategory persists changed fields', () async {
    final id = await categoryDAO.insertCategory(testCategory(name: 'Old'));
    final original = await categoryDAO.getCategoryById(id);

    await categoryDAO.updateCategory(original!.copyWith(name: 'Renamed'));

    final updated = await categoryDAO.getCategoryById(id);
    expect(updated!.name, 'Renamed');
  });

  test('deleteCategory removes the row regardless of custom status',
      () async {
    final id = await categoryDAO.insertCategory(testCategory());
    final deleted = await categoryDAO.deleteCategory(id);
    expect(deleted, 1);
    expect(await categoryDAO.getCategoryById(id), isNull);
  });

  test('deleteCustomCategory only removes custom categories', () async {
    final customId = await categoryDAO.insertCategory(testCategory(isCustom: true));
    final predefined = await categoryDAO.getCategoryByName('Uncategorized');

    expect(await categoryDAO.deleteCustomCategory(customId), 1);
    expect(await categoryDAO.deleteCustomCategory(predefined!.id!), 0);
    expect(await categoryDAO.getCategoryById(predefined.id!), isNotNull);
  });

  test('getCategoryCount / getCustomCategoryCount', () async {
    expect(await categoryDAO.getCategoryCount(), Category.predefinedCategories.length);
    await categoryDAO.insertCategory(testCategory());
    expect(await categoryDAO.getCategoryCount(), Category.predefinedCategories.length + 1);
    expect(await categoryDAO.getCustomCategoryCount(), 1);
  });

  test('categoryNameExists', () async {
    expect(await categoryDAO.categoryNameExists('Uncategorized'), isTrue);
    expect(await categoryDAO.categoryNameExists('Nope'), isFalse);
  });

  test('getCategoriesWithTransactionCounts joins transaction counts per category',
      () async {
    final accountDAO = AccountDAO();
    final transactionDAO = TransactionDAO();
    final accountId = await accountDAO.insertAccount(testAccount());
    await transactionDAO.insertTransaction(
        testTransaction(accountId: accountId, category: 'Shopping'));
    await transactionDAO.insertTransaction(
        testTransaction(accountId: accountId, category: 'Shopping'));

    final rows = await categoryDAO.getCategoriesWithTransactionCounts();
    final shopping = rows.firstWhere((r) => r['name'] == 'Shopping');
    expect(shopping['transaction_count'], 2);
  });

  test('getCategoriesByUsage orders by transaction count descending',
      () async {
    final accountDAO = AccountDAO();
    final transactionDAO = TransactionDAO();
    final accountId = await accountDAO.insertAccount(testAccount());
    await transactionDAO.insertTransaction(
        testTransaction(accountId: accountId, category: 'Groceries'));
    await transactionDAO.insertTransaction(
        testTransaction(accountId: accountId, category: 'Groceries'));
    await transactionDAO.insertTransaction(
        testTransaction(accountId: accountId, category: 'Travel'));

    final byUsage = await categoryDAO.getCategoriesByUsage();
    expect(byUsage.first.name, 'Groceries');
  });

  test('static getPredefinedCategoriesList returns the in-memory canonical list',
      () {
    expect(
      CategoryDAO.getPredefinedCategoriesList().map((c) => c.name),
      Category.predefinedCategories.map((c) => c.name),
    );
  });

  test('static getPredefinedCategoryByName is case-insensitive and null-safe',
      () {
    expect(CategoryDAO.getPredefinedCategoryByName('shopping')?.name, 'Shopping');
    expect(CategoryDAO.getPredefinedCategoryByName('does-not-exist'), isNull);
  });

  test('initializeDefaultCategories is a no-op once categories already exist',
      () async {
    final before = await categoryDAO.getCategoryCount();
    await categoryDAO.initializeDefaultCategories();
    expect(await categoryDAO.getCategoryCount(), before);
  });

  test('searchCategories matches a substring case-insensitively', () async {
    // SQLite's LIKE is case-insensitive for ASCII by default, so the old name
    // ("case-sensitively as stored") was simply wrong — and the test only ever
    // probed the exact stored casing, so it could not have caught either way.
    expect(
      (await categoryDAO.searchCategories('Bills')).map((c) => c.name),
      ['Bills & Utilities'],
    );
    expect(
      (await categoryDAO.searchCategories('bills')).map((c) => c.name),
      ['Bills & Utilities'],
    );
    expect(
      (await categoryDAO.searchCategories('BILLS')).map((c) => c.name),
      ['Bills & Utilities'],
    );

    // Substring, not prefix: matches in the middle of the name too.
    expect(
      (await categoryDAO.searchCategories('utilities')).map((c) => c.name),
      ['Bills & Utilities'],
    );

    expect(await categoryDAO.searchCategories('zzz-no-match'), isEmpty);
  });
}
