// DAO-level tests backed by a real (ffi) SQLite database. Covers every
// AccountDAO method.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import 'package:expenditure_tracker/database/account_dao.dart';

import 'support/db_test_helper.dart';

void main() {
  late AccountDAO accountDAO;

  setUp(() async {
    await resetTestDatabase();
    accountDAO = AccountDAO();
  });

  tearDownAll(disposeTestDatabase);

  test('insertAccount / getAccountById round-trips all fields', () async {
    final id = await accountDAO.insertAccount(testAccount(
      accountType: 'bank_account',
      bankName: 'Kotak',
      accountNumber: 'XX9999',
      accountName: 'Salary Account',
      currentBalance: 25000,
      debitCard1: '4321',
    ));

    final fetched = await accountDAO.getAccountById(id);
    expect(fetched, isNotNull);
    expect(fetched!.bankName, 'Kotak');
    expect(fetched.accountNumber, 'XX9999');
    expect(fetched.currentBalance, 25000);
    expect(fetched.debitCard1, '4321');
  });

  test('getAccountById returns null for a missing id', () async {
    expect(await accountDAO.getAccountById(99999), isNull);
  });

  test('insertAccount rejects a hard conflict on the same primary key',
      () async {
    // Account.toMap() always writes `id`, so re-inserting a row that carries
    // an existing id is a real PK collision. ConflictAlgorithm.abort must
    // surface that as an exception rather than silently replacing or ignoring
    // the row — the existing account's balance has to survive.
    final id = await accountDAO.insertAccount(testAccount());

    await expectLater(
      accountDAO.insertAccount(testAccount(
        id: id,
        bankName: 'HDFC',
        accountNumber: 'XX0000',
        currentBalance: 1,
      )),
      throwsA(isA<DatabaseException>()),
    );

    final survivor = await accountDAO.getAccountById(id);
    expect(survivor!.bankName, 'ICICI');
    expect(survivor.currentBalance, 10000);
    expect(await accountDAO.getAccountCount(), 1);
  });

  group('getAllAccounts / getActiveAccounts', () {
    test('getAllAccounts includes inactive accounts, getActiveAccounts excludes them',
        () async {
      await accountDAO.insertAccount(testAccount(bankName: 'ICICI'));
      final inactiveId =
          await accountDAO.insertAccount(testAccount(bankName: 'HDFC'));
      await accountDAO.deleteAccount(inactiveId);

      expect(await accountDAO.getAllAccounts(), hasLength(2));
      final active = await accountDAO.getActiveAccounts();
      expect(active, hasLength(1));
      expect(active.single.bankName, 'ICICI');
    });
  });

  test('getAccountsByType filters by type and active status', () async {
    await accountDAO.insertAccount(testAccount(accountType: 'bank_account'));
    await accountDAO.insertAccount(testAccount(
      accountType: 'credit_card',
      bankName: 'HDFC',
      accountNumber: 'XX0001',
    ));

    final cards = await accountDAO.getAccountsByType('credit_card');
    expect(cards, hasLength(1));
    expect(cards.single.accountType, 'credit_card');
  });

  test('getAccountsByBank filters by bank name and active status', () async {
    await accountDAO.insertAccount(testAccount(bankName: 'ICICI'));
    await accountDAO.insertAccount(testAccount(
      bankName: 'HDFC',
      accountNumber: 'XX0002',
    ));

    final hdfc = await accountDAO.getAccountsByBank('HDFC');
    expect(hdfc, hasLength(1));
    expect(hdfc.single.bankName, 'HDFC');
  });

  test('updateAccount persists changed fields and bumps updatedAt', () async {
    // Insert with a stale timestamp: with `now` on both sides the insert and
    // the update can land in the same millisecond, and the assertion below
    // would pass whether or not updateAccount touched updatedAt at all.
    final stale = DateTime(2020, 1, 1);
    final id = await accountDAO.insertAccount(
      testAccount(accountName: 'Old Name', createdAt: stale, updatedAt: stale),
    );
    final original = await accountDAO.getAccountById(id);
    expect(original!.updatedAt, stale);

    await accountDAO.updateAccount(original.copyWith(accountName: 'New Name'));

    final updated = await accountDAO.getAccountById(id);
    expect(updated!.accountName, 'New Name');
    expect(updated.updatedAt.isAfter(original.updatedAt), isTrue);
    // createdAt is not a mutable field — the update must leave it alone.
    expect(updated.createdAt, stale);
  });

  test('updateAccountBalance updates only the balance', () async {
    final id = await accountDAO.insertAccount(testAccount(currentBalance: 100));
    await accountDAO.updateAccountBalance(id, 500);

    final updated = await accountDAO.getAccountById(id);
    expect(updated!.currentBalance, 500);
  });

  group('updateBalanceIfNewer (P2-1)', () {
    test('a newer message updates the balance and the as-of date', () async {
      final id = await accountDAO.insertAccount(testAccount(
        currentBalance: 1000,
        updatedAt: DateTime(2026, 1, 1),
      ));

      final applied =
          await accountDAO.updateBalanceIfNewer(id, 2000, DateTime(2026, 1, 5));

      expect(applied, isTrue);
      final updated = await accountDAO.getAccountById(id);
      expect(updated!.currentBalance, 2000);
      expect(updated.updatedAt, DateTime(2026, 1, 5));
    });

    test('an older message does not update the balance or the as-of date',
        () async {
      final id = await accountDAO.insertAccount(testAccount(
        currentBalance: 1000,
        updatedAt: DateTime(2026, 1, 10),
      ));

      final applied =
          await accountDAO.updateBalanceIfNewer(id, 999, DateTime(2026, 1, 1));

      expect(applied, isFalse);
      final updated = await accountDAO.getAccountById(id);
      expect(updated!.currentBalance, 1000);
      expect(updated.updatedAt, DateTime(2026, 1, 10));
    });

    test('returns false for a missing account', () async {
      final applied = await accountDAO.updateBalanceIfNewer(
          99999, 500, DateTime.now());
      expect(applied, isFalse);
    });
  });

  test('deleteAccount soft-deletes (is_active = 0) rather than removing the row',
      () async {
    final id = await accountDAO.insertAccount(testAccount());
    final deleted = await accountDAO.deleteAccount(id);
    expect(deleted, 1);

    final stillThere = await accountDAO.getAccountById(id);
    expect(stillThere, isNotNull);
    expect(stillThere!.isActive, isFalse);
  });

  test('hardDeleteAccount removes the row entirely', () async {
    final id = await accountDAO.insertAccount(testAccount());
    final deleted = await accountDAO.hardDeleteAccount(id);
    expect(deleted, 1);
    expect(await accountDAO.getAccountById(id), isNull);
  });

  test('getTotalBalance sums active non-credit-card accounts only', () async {
    await accountDAO.insertAccount(testAccount(
      accountType: 'bank_account',
      bankName: 'ICICI',
      currentBalance: 1000,
    ));
    await accountDAO.insertAccount(testAccount(
      accountType: 'credit_card',
      bankName: 'HDFC',
      accountNumber: 'XX0003',
      currentBalance: 50000,
    ));
    final inactiveId = await accountDAO.insertAccount(testAccount(
      accountType: 'bank_account',
      bankName: 'SBI',
      accountNumber: 'XX0004',
      currentBalance: 2000,
    ));
    await accountDAO.deleteAccount(inactiveId);

    expect(await accountDAO.getTotalBalance(), 1000.0);
  });

  test('getTotalAvailableCredit sums active credit-card accounts only',
      () async {
    await accountDAO.insertAccount(testAccount(
      accountType: 'credit_card',
      bankName: 'HDFC',
      currentBalance: 50000,
    ));
    await accountDAO.insertAccount(testAccount(
      accountType: 'bank_account',
      bankName: 'ICICI',
      accountNumber: 'XX0005',
      currentBalance: 1000,
    ));

    expect(await accountDAO.getTotalAvailableCredit(), 50000.0);
  });

  test('getBalanceByBank groups active accounts by bank', () async {
    await accountDAO.insertAccount(testAccount(bankName: 'ICICI', currentBalance: 1000));
    await accountDAO.insertAccount(testAccount(
      bankName: 'ICICI',
      accountNumber: 'XX0006',
      currentBalance: 500,
    ));
    await accountDAO.insertAccount(testAccount(
      bankName: 'HDFC',
      accountNumber: 'XX0007',
      currentBalance: 2000,
    ));

    final byBank = await accountDAO.getBalanceByBank();
    expect(byBank['ICICI'], 1500.0);
    expect(byBank['HDFC'], 2000.0);
  });

  test('getBalanceByAccountType groups active accounts by type', () async {
    await accountDAO.insertAccount(testAccount(accountType: 'bank_account', currentBalance: 1000));
    await accountDAO.insertAccount(testAccount(
      accountType: 'credit_card',
      bankName: 'HDFC',
      accountNumber: 'XX0008',
      currentBalance: 5000,
    ));

    final byType = await accountDAO.getBalanceByAccountType();
    expect(byType['bank_account'], 1000.0);
    expect(byType['credit_card'], 5000.0);
  });

  test('accountNumberExists only matches active accounts', () async {
    final id = await accountDAO.insertAccount(testAccount(accountNumber: 'XX7777'));
    expect(await accountDAO.accountNumberExists('XX7777'), isTrue);

    await accountDAO.deleteAccount(id);
    expect(await accountDAO.accountNumberExists('XX7777'), isFalse);
  });

  test('getAccountCount counts only active accounts', () async {
    await accountDAO.insertAccount(testAccount());
    final inactiveId = await accountDAO.insertAccount(testAccount(
      bankName: 'HDFC',
      accountNumber: 'XX0009',
    ));
    await accountDAO.deleteAccount(inactiveId);

    expect(await accountDAO.getAccountCount(), 1);
  });
}
