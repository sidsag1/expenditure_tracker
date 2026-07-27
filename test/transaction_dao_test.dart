// DAO-level tests backed by a real (ffi) SQLite database rather than mocks,
// so the SQL itself is exercised. Covers every TransactionDAO method.
//
// Includes regression coverage for P0-1: getTotalExpenses/getTotalIncome/
// getSpendingByCategory/getSpendingByBank silently ignored the date range
// whenever only one of startDate/endDate was supplied (the dashboard passes
// startDate only for "Last 30 Days"), so those totals were actually
// all-time totals.

import 'package:flutter_test/flutter_test.dart';

import 'package:expenditure_tracker/database/account_dao.dart';
import 'package:expenditure_tracker/database/transaction_dao.dart';

import 'support/db_test_helper.dart';

void main() {
  late TransactionDAO transactionDAO;
  late AccountDAO accountDAO;
  late int accountId;

  setUp(() async {
    await resetTestDatabase();
    transactionDAO = TransactionDAO();
    accountDAO = AccountDAO();
    accountId = await accountDAO.insertAccount(testAccount());
  });

  tearDownAll(disposeTestDatabase);

  group('date range filtering (P0-1 regression)', () {
    setUp(() async {
      final now = DateTime.now();
      // 60 days ago: outside a 30-day window.
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'debit',
        amount: 1000,
        date: now.subtract(const Duration(days: 60)),
      ));
      // 10 days ago: inside a 30-day window.
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'debit',
        amount: 200,
        date: now.subtract(const Duration(days: 10)),
        category: 'Shopping',
      ));
      // Today.
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 5000,
        date: now,
      ));
    });

    test('getTotalExpenses: startDate only excludes older transactions',
        () async {
      final total = await transactionDAO.getTotalExpenses(
        startDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(total, 200.0);
    });

    test('getTotalExpenses: endDate only excludes newer transactions',
        () async {
      final total = await transactionDAO.getTotalExpenses(
        endDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(total, 1000.0);
    });

    test('getTotalExpenses: both bounds narrow to the window', () async {
      final total = await transactionDAO.getTotalExpenses(
        startDate: DateTime.now().subtract(const Duration(days: 90)),
        endDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(total, 1000.0);
    });

    test('getTotalExpenses: no bounds returns the all-time total', () async {
      final total = await transactionDAO.getTotalExpenses();
      expect(total, 1200.0);
    });

    test('getTotalExpenses: accountId filters to that account', () async {
      final otherAccountId =
          await accountDAO.insertAccount(testAccount(bankName: 'HDFC'));
      await transactionDAO.insertTransaction(testTransaction(
        accountId: otherAccountId,
        type: 'debit',
        amount: 999,
        bankName: 'HDFC',
      ));
      final total =
          await transactionDAO.getTotalExpenses(accountId: accountId);
      expect(total, 1200.0);
    });

    test('getTotalIncome: startDate only excludes older credits', () async {
      final total = await transactionDAO.getTotalIncome(
        startDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(total, 5000.0);
    });

    test('getSpendingByCategory: startDate only excludes older category spend',
        () async {
      final byCategory = await transactionDAO.getSpendingByCategory(
        startDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(byCategory['Shopping'], 200.0);
      expect(byCategory.containsKey('Uncategorized'), isFalse);
    });

    test('getSpendingByBank: startDate only excludes older bank spend',
        () async {
      final byBank = await transactionDAO.getSpendingByBank(
        startDate: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(byBank['ICICI'], 200.0);
    });
  });

  group('insertTransaction / getTransactionById', () {
    test('round-trips all fields', () async {
      final id = await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        amount: 42.5,
        merchant: 'Coffee Shop',
        referenceNumber: 'REF123',
        transactionId: 'TXN-abc',
      ));

      final fetched = await transactionDAO.getTransactionById(id);
      expect(fetched, isNotNull);
      expect(fetched!.amount, 42.5);
      expect(fetched.merchant, 'Coffee Shop');
      expect(fetched.referenceNumber, 'REF123');
      expect(fetched.transactionId, 'TXN-abc');
      expect(fetched.accountId, accountId);
    });

    test('getTransactionById returns null for a missing id', () async {
      final fetched = await transactionDAO.getTransactionById(99999);
      expect(fetched, isNull);
    });
  });

  test('insertTransaction rejects a duplicate transaction_id', () async {
    await transactionDAO.insertTransaction(
      testTransaction(accountId: accountId, transactionId: 'DUP-1'),
    );
    expect(
      () => transactionDAO.insertTransaction(
        testTransaction(accountId: accountId, transactionId: 'DUP-1'),
      ),
      throwsA(anything),
    );
  });

  test('insertOrIgnoreTransaction silently skips a duplicate transaction_id',
      () async {
    await transactionDAO.insertTransaction(
      testTransaction(accountId: accountId, transactionId: 'DUP-2'),
    );
    final result = await transactionDAO.insertOrIgnoreTransaction(
      testTransaction(accountId: accountId, transactionId: 'DUP-2'),
    );
    expect(result, 0);
    expect(await transactionDAO.getTransactionCount(), 1);
  });

  group('findDuplicateMatch (P2-3)', () {
    test('none when nothing on the account matches account/type/amount/day',
        () async {
      final match = await transactionDAO.findDuplicateMatch(
        testTransaction(accountId: accountId, amount: 50),
      );
      expect(match, DuplicateMatch.none);
    });

    test('confirmed when reference numbers match', () async {
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        amount: 50,
        referenceNumber: 'A',
      ));
      final match = await transactionDAO.findDuplicateMatch(
        testTransaction(accountId: accountId, amount: 50, referenceNumber: 'A'),
      );
      expect(match, DuplicateMatch.confirmed);
    });

    test('confirmed when normalised merchant names match', () async {
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        amount: 50,
        merchant: 'Coffee Shop',
      ));
      final match = await transactionDAO.findDuplicateMatch(
        testTransaction(accountId: accountId, amount: 50, merchant: '  coffee shop  '),
      );
      expect(match, DuplicateMatch.confirmed);
    });

    test(
        'confirmed when both rows are credit-card payment confirmations with '
        'no ref/merchant on either side (a genuine bank double-SMS)', () async {
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 29393,
        isTransfer: true,
      ));
      final match = await transactionDAO.findDuplicateMatch(
        testTransaction(
          accountId: accountId,
          type: 'credit',
          amount: 29393,
          isTransfer: true,
        ),
      );
      expect(match, DuplicateMatch.confirmed);
    });

    test(
        'ambiguous (not dropped) for two unrelated same-day/same-amount rows '
        'with no reference number or merchant on either side', () async {
      // The P2-3 bug: two unrelated ₹50 coffees on the same card in one day
      // used to be silently collapsed into one. They must now both persist
      // (this DAO method only classifies; saveTransaction is what imports and
      // flags), not disappear.
      await transactionDAO.insertTransaction(
        testTransaction(accountId: accountId, amount: 50),
      );
      final match = await transactionDAO.findDuplicateMatch(
        testTransaction(accountId: accountId, amount: 50),
      );
      expect(match, DuplicateMatch.ambiguous);
    });

    test('ambiguous when reference numbers differ', () async {
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        amount: 50,
        referenceNumber: 'A',
      ));
      final match = await transactionDAO.findDuplicateMatch(
        testTransaction(accountId: accountId, amount: 50, referenceNumber: 'B'),
      );
      expect(match, DuplicateMatch.ambiguous);
    });

    test('none without an accountId', () async {
      final match = await transactionDAO.findDuplicateMatch(
        testTransaction(accountId: null, amount: 50),
      );
      expect(match, DuplicateMatch.none);
    });
  });

  group('findOffsettingTransaction / markTransferPair (P2-2)', () {
    test(
        'finds the opposite-direction, same-amount leg on another account when '
        'a credit card is involved — the bill-payment case', () async {
      final otherAccountId =
          await accountDAO.insertAccount(testAccount(bankName: 'HDFC'));
      final creditId = await transactionDAO.insertTransaction(testTransaction(
        accountId: otherAccountId,
        bankName: 'HDFC',
        accountType: 'credit_card',
        type: 'credit',
        amount: 500,
        date: DateTime(2026, 3, 10),
      ));

      final offset = await transactionDAO.findOffsettingTransaction(
        testTransaction(
          accountId: accountId,
          type: 'debit',
          amount: 500,
          date: DateTime(2026, 3, 11),
        ),
      );

      expect(offset, isNotNull);
      expect(offset!.id, creditId);
    });

    test(
        'two same-amount bank-to-bank movements with nothing corroborating '
        'them are not paired — pairing them would erase both from the '
        'income/expense totals', () async {
      final otherAccountId =
          await accountDAO.insertAccount(testAccount(bankName: 'HDFC'));
      await transactionDAO.insertTransaction(testTransaction(
        accountId: otherAccountId,
        bankName: 'HDFC',
        type: 'credit',
        amount: 500,
        date: DateTime(2026, 3, 10),
      ));

      final offset = await transactionDAO.findOffsettingTransaction(
        testTransaction(
          accountId: accountId,
          type: 'debit',
          amount: 500,
          date: DateTime(2026, 3, 11),
        ),
      );

      expect(offset, isNull);
    });

    test('does not match a same-account row', () async {
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 500,
      ));

      final offset = await transactionDAO.findOffsettingTransaction(
        testTransaction(accountId: accountId, type: 'debit', amount: 500),
      );

      expect(offset, isNull);
    });

    test('does not match outside the time window', () async {
      final otherAccountId =
          await accountDAO.insertAccount(testAccount(bankName: 'HDFC'));
      await transactionDAO.insertTransaction(testTransaction(
        accountId: otherAccountId,
        bankName: 'HDFC',
        type: 'credit',
        amount: 500,
        date: DateTime(2026, 3, 1),
      ));

      final offset = await transactionDAO.findOffsettingTransaction(
        testTransaction(
          accountId: accountId,
          type: 'debit',
          amount: 500,
          date: DateTime(2026, 3, 10),
        ),
      );

      expect(offset, isNull);
    });

    test('a real merchant debit with no matching opposite leg is never marked a transfer',
        () async {
      final offset = await transactionDAO.findOffsettingTransaction(
        testTransaction(accountId: accountId, type: 'debit', amount: 499),
      );
      expect(offset, isNull);
    });

    test('markTransferPair sets is_transfer on both rows', () async {
      final id1 = await transactionDAO.insertTransaction(
        testTransaction(accountId: accountId, type: 'debit', amount: 500),
      );
      final otherAccountId =
          await accountDAO.insertAccount(testAccount(bankName: 'HDFC'));
      final id2 = await transactionDAO.insertTransaction(testTransaction(
        accountId: otherAccountId,
        bankName: 'HDFC',
        type: 'credit',
        amount: 500,
      ));

      await transactionDAO.markTransferPair(id1, id2);

      expect((await transactionDAO.getTransactionById(id1))!.isTransfer, isTrue);
      expect((await transactionDAO.getTransactionById(id2))!.isTransfer, isTrue);
    });
  });

  group('is_transfer exclusion from aggregates (P2-2)', () {
    test('getTotalExpenses/getTotalIncome exclude transfer-flagged rows',
        () async {
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'debit',
        amount: 500,
        isTransfer: true,
      ));
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'debit',
        amount: 100,
      ));
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 500,
        isTransfer: true,
      ));
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 200,
      ));

      expect(await transactionDAO.getTotalExpenses(), 100.0);
      expect(await transactionDAO.getTotalIncome(), 200.0);
      // The amount the two totals above leave out, which the account screen
      // names so the user can reconcile a large visible credit against an
      // income figure that didn't move.
      expect(await transactionDAO.getTotalTransfers(), 1000.0);
    });

    test('getTotalTransfers is scoped by account and date range', () async {
      final otherAccountId = await accountDAO.insertAccount(
          testAccount(accountNumber: '9999', accountName: 'other'));
      final now = DateTime.now();

      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 700,
        isTransfer: true,
        date: now,
      ));
      // Same account, outside a 30-day window.
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 400,
        isTransfer: true,
        date: now.subtract(const Duration(days: 60)),
      ));
      // Different account entirely.
      await transactionDAO.insertTransaction(testTransaction(
        accountId: otherAccountId,
        type: 'credit',
        amount: 999,
        isTransfer: true,
        date: now,
      ));

      expect(
        await transactionDAO.getTotalTransfers(accountId: accountId),
        1100.0,
      );
      expect(
        await transactionDAO.getTotalTransfers(
          accountId: accountId,
          startDate: now.subtract(const Duration(days: 30)),
        ),
        700.0,
      );
    });

    test('hasAutoImportedTransactions distinguishes a purged table from a populated one',
        () async {
      // What SMSService uses to decide its stored sync high-water mark has
      // gone stale: after a migration purges auto-imported rows, an
      // incremental sync would skip the entire back-catalogue instead of
      // rebuilding it.
      expect(await transactionDAO.hasAutoImportedTransactions(), isFalse);

      // A manual entry is not an import and must not make the mark look valid.
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        isManual: true,
      ));
      expect(await transactionDAO.hasAutoImportedTransactions(), isFalse);

      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        isManual: false,
      ));
      expect(await transactionDAO.hasAutoImportedTransactions(), isTrue);
    });

    test('getTotalIncome counts transfers in when asked, and only then',
        () async {
      // A credit card's own summary folds the bill payments that clear it into
      // Total Income -- they are the card's largest credits, and leaving them
      // out describes almost nothing that happened on it. Every cross-account
      // total must still leave them out, or the user's own cash paying a bill
      // is counted a second time as household income.
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 50000,
        isTransfer: true,
      ));
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 644,
      ));
      // A transfer on the debit side must not be added to income by the flag.
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'debit',
        amount: 900,
        isTransfer: true,
      ));

      expect(await transactionDAO.getTotalIncome(), 644.0);
      expect(
        await transactionDAO.getTotalIncome(includeTransfers: true),
        50644.0,
      );
      // Expenses are unaffected either way.
      expect(await transactionDAO.getTotalExpenses(), 0.0);
    });

    test('getTotalTransfers can name a single leg', () async {
      // The account screen quotes this next to Total Income, so it has to
      // cover the same rows that total does -- summing both directions would
      // print a figure that doesn't reconcile with the one above it.
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 50000,
        isTransfer: true,
      ));
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'debit',
        amount: 900,
        isTransfer: true,
      ));

      expect(await transactionDAO.getTotalTransfers(), 50900.0);
      expect(
        await transactionDAO.getTotalTransfers(transactionType: 'credit'),
        50000.0,
      );
      expect(
        await transactionDAO.getTotalTransfers(transactionType: 'debit'),
        900.0,
      );
    });

    test('getTotalTransfers is zero when nothing is flagged', () async {
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'credit',
        amount: 300,
      ));
      expect(await transactionDAO.getTotalTransfers(), 0.0);
    });

    test('getSpendingByCategory/getSpendingByBank exclude transfer-flagged rows',
        () async {
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'debit',
        amount: 500,
        category: 'Bills & Utilities',
        isTransfer: true,
      ));
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        type: 'debit',
        amount: 100,
        category: 'Shopping',
      ));

      final byCategory = await transactionDAO.getSpendingByCategory();
      expect(byCategory.containsKey('Bills & Utilities'), isFalse);
      expect(byCategory['Shopping'], 100.0);

      final byBank = await transactionDAO.getSpendingByBank();
      expect(byBank['ICICI'], 100.0);
    });
  });

  test('deleteUnlinkedAutoTransactions removes only unlinked auto imports',
      () async {
    await transactionDAO.insertTransaction(
      testTransaction(accountId: null, isManual: false),
    );
    await transactionDAO.insertTransaction(
      testTransaction(accountId: accountId, isManual: false),
    );
    await transactionDAO.insertTransaction(
      testTransaction(accountId: null, isManual: true),
    );

    final deleted = await transactionDAO.deleteUnlinkedAutoTransactions();
    expect(deleted, 1);
    expect(await transactionDAO.getTransactionCount(), 2);
  });

  test('deleteAutoImportedTransactions removes every non-manual row',
      () async {
    await transactionDAO.insertTransaction(
      testTransaction(accountId: accountId, isManual: false),
    );
    await transactionDAO.insertTransaction(
      testTransaction(accountId: accountId, isManual: true),
    );

    final deleted = await transactionDAO.deleteAutoImportedTransactions();
    expect(deleted, 1);
    expect(await transactionDAO.getTransactionCount(), 1);
  });

  test('getAllTransactions orders newest first', () async {
    final now = DateTime.now();
    await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId, date: now.subtract(const Duration(days: 2))));
    await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId, date: now));

    final all = await transactionDAO.getAllTransactions();
    expect(all, hasLength(2));
    expect(all.first.transactionDate.isAfter(all.last.transactionDate), isTrue);
  });

  test('getTransactionsByAccount only returns that account\'s rows', () async {
    final otherAccountId = await accountDAO.insertAccount(testAccount(bankName: 'HDFC'));
    await transactionDAO.insertTransaction(testTransaction(accountId: accountId));
    await transactionDAO.insertTransaction(testTransaction(accountId: otherAccountId, bankName: 'HDFC'));

    final rows = await transactionDAO.getTransactionsByAccount(accountId);
    expect(rows, hasLength(1));
    expect(rows.single.accountId, accountId);
  });

  test('getTransactionsByDateRange includes the start bound and excludes the end bound',
      () async {
    // Fixed dates, and rows placed exactly ON each bound — with the previous
    // "5 days ago vs 40 days ago" data no row was anywhere near a boundary,
    // so the test passed under any bound semantics at all.
    final start = DateTime(2026, 3, 1);
    final end = DateTime(2026, 4, 1);

    for (final date in [
      start.subtract(const Duration(microseconds: 1)), // just before start
      start, // exactly on the inclusive lower bound
      end.subtract(const Duration(milliseconds: 500)), // last half-second
      end, // exactly on the exclusive upper bound
    ]) {
      await transactionDAO.insertTransaction(
        testTransaction(accountId: accountId, date: date),
      );
    }

    final rows = await transactionDAO.getTransactionsByDateRange(start, end);

    expect(
      rows.map((r) => r.transactionDate).toSet(),
      {start, end.subtract(const Duration(milliseconds: 500))},
    );
  });

  test('getTransactionsByCategory filters by exact category name', () async {
    await transactionDAO.insertTransaction(testTransaction(accountId: accountId, category: 'Shopping'));
    await transactionDAO.insertTransaction(testTransaction(accountId: accountId, category: 'Uncategorized'));

    final rows = await transactionDAO.getTransactionsByCategory('Shopping');
    expect(rows, hasLength(1));
    expect(rows.single.category, 'Shopping');
  });

  test('getTransactionsByBank filters by bank name', () async {
    final hdfcAccountId = await accountDAO.insertAccount(testAccount(bankName: 'HDFC'));
    await transactionDAO.insertTransaction(testTransaction(accountId: accountId, bankName: 'ICICI'));
    await transactionDAO.insertTransaction(testTransaction(accountId: hdfcAccountId, bankName: 'HDFC'));

    final rows = await transactionDAO.getTransactionsByBank('HDFC');
    expect(rows, hasLength(1));
    expect(rows.single.bankName, 'HDFC');
  });

  test('getRecentTransactions respects the limit and newest-first order', () async {
    final now = DateTime.now();
    for (var i = 0; i < 5; i++) {
      await transactionDAO.insertTransaction(testTransaction(
        accountId: accountId,
        date: now.subtract(Duration(days: i)),
      ));
    }
    final recent = await transactionDAO.getRecentTransactions(limit: 2);
    expect(recent, hasLength(2));
    expect(recent.first.transactionDate, now);
  });

  test('getTransactionByTransactionId finds the matching row', () async {
    await transactionDAO.insertTransaction(
      testTransaction(accountId: accountId, transactionId: 'FIND-ME'),
    );
    final found = await transactionDAO.getTransactionByTransactionId('FIND-ME');
    expect(found, isNotNull);
    expect(found!.transactionId, 'FIND-ME');

    final missing = await transactionDAO.getTransactionByTransactionId('NOPE');
    expect(missing, isNull);
  });

  test('updateTransaction persists changed fields', () async {
    final id = await transactionDAO.insertTransaction(
      testTransaction(accountId: accountId, amount: 10, description: 'old'),
    );
    final original = await transactionDAO.getTransactionById(id);
    await transactionDAO.updateTransaction(
      original!.copyWith(amount: 20, description: 'new'),
    );

    final updated = await transactionDAO.getTransactionById(id);
    expect(updated!.amount, 20);
    expect(updated.description, 'new');
  });

  test('updateTransactionCategory updates only the category', () async {
    final id = await transactionDAO.insertTransaction(
      testTransaction(accountId: accountId, category: 'Uncategorized'),
    );
    await transactionDAO.updateTransactionCategory(id, 'Groceries');

    final updated = await transactionDAO.getTransactionById(id);
    expect(updated!.category, 'Groceries');
  });

  test('deleteTransaction removes the row', () async {
    final id = await transactionDAO.insertTransaction(testTransaction(accountId: accountId));
    final deleted = await transactionDAO.deleteTransaction(id);
    expect(deleted, 1);
    expect(await transactionDAO.getTransactionById(id), isNull);
  });

  test('getDailySpending buckets debits by calendar day within N days', () async {
    final now = DateTime.now();
    await transactionDAO.insertTransaction(testTransaction(
      accountId: accountId,
      type: 'debit',
      amount: 30,
      date: now,
    ));
    await transactionDAO.insertTransaction(testTransaction(
      accountId: accountId,
      type: 'credit',
      amount: 999,
      date: now,
    ));

    final daily = await transactionDAO.getDailySpending(7);
    final total = daily.values.fold<double>(0, (sum, v) => sum + v);
    expect(total, 30.0);
  });

  test('getTransactionCount reflects inserts and deletes', () async {
    expect(await transactionDAO.getTransactionCount(), 0);
    final id = await transactionDAO.insertTransaction(testTransaction(accountId: accountId));
    expect(await transactionDAO.getTransactionCount(), 1);
    await transactionDAO.deleteTransaction(id);
    expect(await transactionDAO.getTransactionCount(), 0);
  });

  test('searchTransactions matches description or merchant', () async {
    await transactionDAO.insertTransaction(testTransaction(
      accountId: accountId,
      description: 'Grocery run',
      merchant: 'BigMart',
    ));
    await transactionDAO.insertTransaction(testTransaction(
      accountId: accountId,
      description: 'Movie night',
      merchant: 'Cineplex',
    ));

    expect(await transactionDAO.searchTransactions('grocery'), hasLength(1));
    expect(await transactionDAO.searchTransactions('cineplex'), hasLength(1));
    expect(await transactionDAO.searchTransactions('nomatch'), isEmpty);
  });

  test('getTransactionsByMonth returns the whole calendar month, last second included',
      () async {
    // The old inclusive `BETWEEN start AND <last day> 23:59:59` bound dropped
    // anything in the final second of the month.
    final lastMoment = DateTime(2026, 3, 31, 23, 59, 59, 500);
    for (final date in [
      DateTime(2026, 2, 28, 23, 59, 59, 500), // last moment of the month before
      DateTime(2026, 3, 1), // first moment of March
      DateTime(2026, 3, 15),
      lastMoment,
      DateTime(2026, 4, 1), // first moment of April
    ]) {
      await transactionDAO.insertTransaction(
        testTransaction(accountId: accountId, date: date),
      );
    }

    final marchRows = await transactionDAO.getTransactionsByMonth(2026, 3);
    expect(
      marchRows.map((r) => r.transactionDate).toSet(),
      {DateTime(2026, 3, 1), DateTime(2026, 3, 15), lastMoment},
    );
  });

  test('getTransactionsByMonth rolls December over into the next January',
      () async {
    // DateTime(year, 13, 1) is January of year+1; the exclusive upper bound
    // depends on that, so pin it.
    final december = DateTime(2026, 12, 31, 23, 59, 59, 500);
    await transactionDAO.insertTransaction(
      testTransaction(accountId: accountId, date: december),
    );
    await transactionDAO.insertTransaction(
      testTransaction(accountId: accountId, date: DateTime(2027, 1, 1)),
    );

    final rows = await transactionDAO.getTransactionsByMonth(2026, 12);
    expect(rows.map((r) => r.transactionDate), [december]);
  });

  test('getCategoriesFromTransactions returns distinct sorted categories', () async {
    await transactionDAO.insertTransaction(testTransaction(accountId: accountId, category: 'Shopping'));
    await transactionDAO.insertTransaction(testTransaction(accountId: accountId, category: 'Shopping'));
    await transactionDAO.insertTransaction(testTransaction(accountId: accountId, category: 'Bills & Utilities'));

    final categories = await transactionDAO.getCategoriesFromTransactions();
    expect(categories, ['Bills & Utilities', 'Shopping']);
  });
}
