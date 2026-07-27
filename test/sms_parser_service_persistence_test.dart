// DB-backed tests for SMSParserService.saveTransaction. The pure-parsing
// tests in sms_parser_service_test.dart used to disclaim persistence-path
// coverage as needing an on-device run, but that predates the
// sqflite_common_ffi test infrastructure (P7-1) — saveTransaction only
// touches TransactionDAO/AccountDAO, no platform channel, so it runs fine
// here.

import 'package:flutter_test/flutter_test.dart';

import 'package:expenditure_tracker/database/account_dao.dart';
import 'package:expenditure_tracker/database/database_helper.dart';
import 'package:expenditure_tracker/database/transaction_dao.dart';
import 'package:expenditure_tracker/models/account.dart';
import 'package:expenditure_tracker/services/sms_parser_service.dart';

import 'support/db_test_helper.dart';

void main() {
  late AccountDAO accountDAO;
  late TransactionDAO transactionDAO;
  late SMSParserService parser;

  setUp(() async {
    await resetTestDatabase();
    accountDAO = AccountDAO();
    transactionDAO = TransactionDAO();
    parser = SMSParserService();
  });

  tearDownAll(disposeTestDatabase);

  Future<Account> registerAccount({
    String bankName = 'ICICI',
    String accountNumber = 'XX340',
    double currentBalance = 0,
    DateTime? updatedAt,
  }) async {
    final id = await accountDAO.insertAccount(testAccount(
      bankName: bankName,
      accountNumber: accountNumber,
      currentBalance: currentBalance,
      updatedAt: updatedAt,
    ));
    return (await accountDAO.getAccountById(id))!;
  }

  group('duplicate handling (P2-3)', () {
    test('a confirmed duplicate (matching reference number) is not saved twice',
        () async {
      await registerAccount();
      const message =
          'ICICI Bank Acct XX340 debited for Rs 50.00 on 11-Oct-25; VENDOR credited. UPI:528407948322.';

      final first = await parser.parseSMS(message, 'ICICIB');
      expect(await parser.saveTransaction(first!, sourceMessage: message), isTrue);

      // A slightly different message wording for the same UPI reference, as
      // a bank re-send might produce; the parser generates a different
      // transaction_id (it hashes the whole message), so this isn't caught
      // by the transaction_id dedup and must fall through to
      // findDuplicateMatch.
      const secondMessage =
          'ICICI Bank Acct XX340 debited for Rs 50.00 on 11-Oct-25 by UPI. UPI:528407948322. Call 18002662 for dispute.';
      final second = await parser.parseSMS(secondMessage, 'ICICIB');
      final saved = await parser.saveTransaction(second!, sourceMessage: secondMessage);

      expect(saved, isFalse);
      expect(await transactionDAO.getTransactionCount(), 1);
    });

    test('an ambiguous same-day/same-amount debit with no shared signal is '
        'imported and flagged needs_review, not dropped', () async {
      await registerAccount();
      const firstMessage =
          'ICICI Bank Acct XX340 debited for Rs 50.00 on 11-Oct-25; COFFEE SHOP A credited.';
      const secondMessage =
          'ICICI Bank Acct XX340 debited for Rs 50.00 on 11-Oct-25; COFFEE SHOP B credited.';

      final first = await parser.parseSMS(firstMessage, 'ICICIB');
      expect(await parser.saveTransaction(first!, sourceMessage: firstMessage),
          isTrue);

      final second = await parser.parseSMS(secondMessage, 'ICICIB');
      expect(
          await parser.saveTransaction(second!, sourceMessage: secondMessage),
          isTrue);

      expect(await transactionDAO.getTransactionCount(), 2);
      final all = await transactionDAO.getAllTransactions();
      expect(all.where((t) => t.needsReview).length, 1);
    });
  });

  group('account matching (P3-3)', () {
    test(
        'a digit run shorter than 3 digits does not bind to an account; the '
        'transaction is imported unassigned and flagged needs_review instead '
        'of being silently dropped', () async {
      await registerAccount(
          bankName: 'Punjab National Bank', accountNumber: 'XX9318');
      // The only digits near an account/card keyword are "18" -- a 2-digit
      // suffix, which used to be enough to (wrongly) bind to an account
      // ending in ...318.
      const message =
          'Rs.500.00 debited from PNB Bank Card 18 on 12-Jul-26 towards POS purchase.';

      final txn = await parser.parseSMS(message, 'PNB');
      expect(await parser.saveTransaction(txn!, sourceMessage: message),
          isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, isNull);
      expect(saved.needsReview, isTrue);
    });

    test(
        'multiple accounts at the same bank with no identifying digits in '
        'the message is imported unassigned and flagged needs_review, not '
        "guessed at (the old bankAccounts.first behaviour)", () async {
      await registerAccount(
          bankName: 'Punjab National Bank', accountNumber: 'XX1111');
      await registerAccount(
          bankName: 'Punjab National Bank', accountNumber: 'XX2222');
      const message =
          'Rs.500.00 debited from your PNB Bank on 12-Jul-26 towards UPI payment to merchant.';

      final txn = await parser.parseSMS(message, 'PNB');
      expect(await parser.saveTransaction(txn!, sourceMessage: message),
          isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, isNull);
      expect(saved.needsReview, isTrue);
    });

    test('a message for a bank the user has not registered any account for '
        'is imported unassigned and flagged, so adding the account later can '
        'claim it', () async {
      // No account registered at all. Dropping the message would be
      // unrecoverable -- the sync high-water mark means it is never offered
      // again -- so it is kept for the account the user has yet to add.
      const message =
          'Rs.500.00 debited from your PNB Bank on 12-Jul-26 towards UPI payment to merchant.';

      final txn = await parser.parseSMS(message, 'PNB');
      expect(await parser.saveTransaction(txn!, sourceMessage: message),
          isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, isNull);
      expect(saved.needsReview, isTrue);
    });

    test('a confident 3+ digit suffix match still binds normally', () async {
      final account = await registerAccount(
          bankName: 'Punjab National Bank', accountNumber: 'XX9318');
      const message =
          'Rs.500.00 debited from PNB Bank Card 318 on 12-Jul-26 towards POS purchase.';

      final txn = await parser.parseSMS(message, 'PNB');
      expect(await parser.saveTransaction(txn!, sourceMessage: message),
          isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, account.id);
      expect(saved.needsReview, isFalse);
    });
  });

  group('activeAccounts caching (batch sync query thrashing fix)', () {
    test(
        'a pre-fetched activeAccounts list is used for matching instead of '
        're-querying the DB, so it still matches even after the account is '
        'deactivated in between the fetch and the save', () async {
      final account = await registerAccount(
          bankName: 'Punjab National Bank', accountNumber: 'XX9318');
      final snapshot = await parser.loadActiveAccounts();

      // Deactivate after the snapshot was taken -- getActiveAccounts()
      // called fresh at save time would no longer return this account.
      await accountDAO.deleteAccount(account.id!);

      const message =
          'Rs.500.00 debited from PNB Bank Card 318 on 12-Jul-26 towards POS purchase.';
      final txn = await parser.parseSMS(message, 'PNB');
      expect(
          await parser.saveTransaction(txn!,
              sourceMessage: message, activeAccounts: snapshot),
          isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, account.id);
    });

    test('omitting activeAccounts falls back to querying the DB as before',
        () async {
      final account = await registerAccount(
          bankName: 'Punjab National Bank', accountNumber: 'XX9318');
      const message =
          'Rs.500.00 debited from PNB Bank Card 318 on 12-Jul-26 towards POS purchase.';

      final txn = await parser.parseSMS(message, 'PNB');
      expect(await parser.saveTransaction(txn!, sourceMessage: message),
          isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, account.id);
    });
  });

  group('balance propagation (P2-1)', () {
    test('a parsed balance updates the account when newer than the current one',
        () async {
      final account = await registerAccount(
        currentBalance: 1000,
        updatedAt: DateTime(2020, 1, 1),
      );
      const message =
          'ICICI Bank Account XX340 credited:Rs. 2,45,687.00 on 30-Sep-25. Info NEFT-HSBCN52025093079143616-. Available Balance is Rs. 2,97,158.22.';

      final txn = await parser.parseSMS(message, 'ICICIB');
      expect(await parser.saveTransaction(txn!, sourceMessage: message), isTrue);

      final updated = await accountDAO.getAccountById(account.id!);
      expect(updated!.currentBalance, 297158.22);
    });
  });

  group('transfer detection (P2-2)', () {
    test('offsetting legs on two registered accounts are both marked as transfers',
        () async {
      final bank = await registerAccount(bankName: 'ICICI', accountNumber: 'XX340');
      await accountDAO.insertAccount(testAccount(
        accountType: 'credit_card',
        bankName: 'ICICI',
        accountNumber: 'XX4016',
      ));

      const debitMessage =
          'ICICI Bank Acct XX340 debited for Rs 5000.00 on 09-Dec-25; CRED CLUB credited. UPI:611111111111.';
      const creditMessage =
          'Payment of Rs 5000.00 has been received on your ICICI Bank Credit Card XX4016 through Bharat Bill Payment System on 09-DEC-25.';

      final debitTxn = await parser.parseSMS(debitMessage, 'ICICIB');
      expect(
          await parser.saveTransaction(debitTxn!, sourceMessage: debitMessage),
          isTrue);
      final creditTxn = await parser.parseSMS(creditMessage, 'ICICIB');
      expect(
          await parser.saveTransaction(creditTxn!, sourceMessage: creditMessage),
          isTrue);

      final all = await transactionDAO.getAllTransactions();
      expect(all.every((t) => t.isTransfer), isTrue);
      expect(await transactionDAO.getTotalExpenses(accountId: bank.id), 0.0);
    });

    test('an ordinary merchant debit is never marked a transfer', () async {
      await registerAccount();
      const message =
          'ICICI Bank Acct XX340 debited for Rs 499.00 on 19-Oct-25; SWIGGY credited. UPI:700000000000.';

      final txn = await parser.parseSMS(message, 'ICICIB');
      expect(await parser.saveTransaction(txn!, sourceMessage: message), isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.isTransfer, isFalse);
    });
  });

  group('batched sync does not deadlock (P4-1 regression)', () {
    test(
        'saveTransaction completes when called from inside db.transaction(), '
        'the same way SMSService.syncMessages batches a sync -- every DB call '
        'it makes (duplicate checks, insert, balance update, transfer '
        'matching) must go through the passed txn rather than a fresh '
        'db.database call, or this deadlocks against the open transaction',
        () async {
      await registerAccount();
      const firstMessage =
          'ICICI Bank Acct XX340 debited for Rs 50.00 on 11-Oct-25; VENDOR A credited. UPI:100000000001.';
      const secondMessage =
          'ICICI Bank Acct XX340 debited for Rs 75.00 on 12-Oct-25; VENDOR B credited. UPI:100000000002.';

      final first = await parser.parseSMS(firstMessage, 'ICICIB');
      final second = await parser.parseSMS(secondMessage, 'ICICIB');

      final db = await DatabaseHelper().database;
      await db.transaction((txn) async {
        expect(
            await parser.saveTransaction(first!,
                sourceMessage: firstMessage, txn: txn),
            isTrue);
        expect(
            await parser.saveTransaction(second!,
                sourceMessage: secondMessage, txn: txn),
            isTrue);
      });

      expect(await transactionDAO.getTransactionCount(), 2);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
