// Regression tests for SMS-to-account linking, built from real messages off
// a user's phone (HDFC credit card + ICICI savings/loan).
//
// The reported symptom was "every message shows up under Transactions but
// none of them are attached to an account, even though the account is added"
// — which is what happens when the inbox was synced *before* the account was
// registered: the rows are imported unassigned, and every later rescan then
// deduped against them by transaction_id and skipped, so they could never be
// claimed. See SMSParserService.saveTransaction.
//
// The other half of these tests pins the linking itself against the exact
// masking each bank uses ("Card x6955", "CARD ENDING WITH 6955",
// "Acct XX340"), on the assumption stated by the user: the account is always
// registered with just the last 4 digits.

import 'package:flutter_test/flutter_test.dart';

import 'package:expenditure_tracker/database/account_dao.dart';
import 'package:expenditure_tracker/database/transaction_dao.dart';
import 'package:expenditure_tracker/models/account.dart';
import 'package:expenditure_tracker/services/sms_parser_service.dart';

import 'support/db_test_helper.dart';

// Real message bodies, verbatim.
const hdfcCardSpend =
    'Rs.199 without OTP/PIN HDFC Bank Card x6955 At NETFLIX On '
    '2026-06-13:08:56:40.Not U? Block&Reissue:Call 18002586161/SMS BLOCK CC '
    '6955 to 7308080808';

const hdfcCardPayment =
    'DEAR HDFCBANK CARDMEMBER, PAYMENT OF Rs. 29393.00 RECEIVED TOWARDS YOUR '
    'CREDIT CARD ENDING WITH 6955 ON 7-7-2026.YOUR AVAILABLE LIMIT IS RS. '
    '686166.10';

const hdfcLoanAd = 'Best Deal Alert!\n\nUnlock Loan of Rs. 520000 via '
    'PayZapp, on your HDFC Bank Credit Card x6955.\n\nKnow More: '
    'https://1.hdfc.bank.in/HDFCBK/s/4J7Oa3j3\nT&C';

const iciciEmiReminder =
    'EMI of Rs 24688 for ICICI Bank Automobiles Loan XX9300 is due on '
    '10-Jul-26. Please maintain sufficient funds in your linked Account '
    'XX4340 to avoid 5% per annum penal charges and Rs 500 bounce charges. '
    'EMI will be debited on holidays too. Access your loan related services '
    'on iMobile at icici.co/ICICIT/k/DUvOd7lne0G';

const iciciUpiDebit =
    'ICICI Bank Acct XX340 debited for Rs 14.00 on 19-Jul-26; GANGA KUMAR '
    'YAD credited. UPI:620075350266. Call 18002662 for dispute. SMS BLOCK '
    '340 to 9215676766.';

// Account-level alerts that name no account number at all — the shape most of
// the older back-catalogue takes.
const iciciDigitlessAccountDebit =
    'Dear Customer, your ICICI Bank Account has been debited with Rs 1,230.00 '
    'towards BIL*PAYTM. Call 18002662 for dispute.';

const iciciDigitlessDatedDebit =
    'Dear Customer, your ICICI Bank Account has been debited with Rs 962.00 '
    'on 21-Dec-20 towards BIL*RECHARGE.';

// Names a card that was never registered.
const hdfcUnknownCardSpend =
    'Rs.450 without OTP/PIN HDFC Bank Card x2211 At SWIGGY On '
    '2026-06-14:19:02:11.Not U? Block&Reissue:Call 18002586161';

const hdfcSender = 'AD-HDFCBK-S';
const iciciSender = 'AD-ICICIB-S';

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

  // The user registers accounts with the last 4 digits only, unmasked.
  Future<Account> registerHdfcCard() async {
    final id = await accountDAO.insertAccount(testAccount(
      accountType: 'credit_card',
      bankName: 'HDFC',
      accountNumber: '6955',
      accountName: 'HDFC Credit Card',
    ));
    return (await accountDAO.getAccountById(id))!;
  }

  Future<Account> registerIciciSavings() async {
    final id = await accountDAO.insertAccount(testAccount(
      bankName: 'ICICI',
      accountNumber: '4340',
      accountName: 'ICICI Savings',
    ));
    return (await accountDAO.getAccountById(id))!;
  }

  // Imports a message the way SMSService.syncMessages does.
  Future<bool> import(String message, String sender) async {
    final txn = await parser.parseSMS(message, sender);
    if (txn == null) return false;
    return parser.saveTransaction(txn, sourceMessage: message);
  }

  group('linking against an account registered with only the last 4 digits',
      () {
    test('HDFC "Card x6955" card spend lands on the card ending 6955',
        () async {
      final card = await registerHdfcCard();

      expect(await import(hdfcCardSpend, hdfcSender), isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, card.id);
      expect(saved.needsReview, isFalse);
      expect(saved.transactionType, 'debit');
      expect(saved.amount, 199);
      expect(saved.merchant, 'NETFLIX');
    });

    test('HDFC "CARD ENDING WITH 6955" bill payment lands on the same card '
        'as a credit', () async {
      final card = await registerHdfcCard();

      expect(await import(hdfcCardPayment, hdfcSender), isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, card.id);
      expect(saved.needsReview, isFalse);
      expect(saved.transactionType, 'credit');
      expect(saved.amount, 29393);
    });

    test('ICICI "Acct XX340" debit lands on the account registered as 4340 — '
        'the bank masks the same account to different lengths, so the '
        'shorter run has to match as a suffix', () async {
      final savings = await registerIciciSavings();

      expect(await import(iciciUpiDebit, iciciSender), isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, savings.id);
      expect(saved.needsReview, isFalse);
      expect(saved.transactionType, 'debit');
      expect(saved.amount, 14);
    });

    test('a card spend does not leak onto a same-bank account whose digits '
        'it does not name', () async {
      final card = await registerHdfcCard();
      await accountDAO.insertAccount(testAccount(
        bankName: 'HDFC',
        accountNumber: '1234',
        accountName: 'HDFC Savings',
      ));

      expect(await import(hdfcCardSpend, hdfcSender), isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, card.id);
    });
  });

  // A user holds at most one deposit account per bank, so a message that says
  // it happened on "your account" and names no digits can only be that one --
  // even when the same bank has issued them several cards.
  group('a message that names no account, at a bank holding several', () {
    Future<Account> registerIciciSavingsAndTwoCards() async {
      final savings = await registerIciciSavings();
      for (final last4 in ['4016', '4017']) {
        await accountDAO.insertAccount(testAccount(
          accountType: 'credit_card',
          bankName: 'ICICI',
          accountNumber: last4,
          accountName: 'ICICI Card $last4',
        ));
      }
      return savings;
    }

    test('an account debit lands on the only deposit account at that bank',
        () async {
      final savings = await registerIciciSavingsAndTwoCards();

      expect(await import(iciciDigitlessAccountDebit, iciciSender), isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, savings.id);
      expect(saved.needsReview, isFalse);
      expect(saved.transactionType, 'debit');
      expect(saved.amount, 1230);
    });

    test('a date in the body does not stop the narrowing', () async {
      // The digits banks scatter through these (dates, helpline numbers) sit
      // too far from any account keyword to be read as naming an account, so
      // the narrowing still applies. A run that *is* adjacent to one — "Card
      // 18" — does count as naming an account and is left in review instead;
      // see sms_parser_service_persistence_test.
      final savings = await registerIciciSavingsAndTwoCards();

      expect(await import(iciciDigitlessDatedDebit, iciciSender), isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, savings.id);
      expect(saved.needsReview, isFalse);
    });

    test('two deposit accounts at one bank stay ambiguous rather than being '
        'guessed at', () async {
      // The narrowing only resolves what is genuinely unambiguous. The user's
      // "one account per bank" premise is what makes the test above safe, so
      // where it does not hold, the old behaviour must survive.
      await registerIciciSavingsAndTwoCards();
      await accountDAO.insertAccount(testAccount(
        bankName: 'ICICI',
        accountNumber: '8888',
        accountName: 'ICICI Second Savings',
      ));

      expect(await import(iciciDigitlessAccountDebit, iciciSender), isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, isNull);
      expect(saved.needsReview, isTrue);
    });

    test('a card spend naming a card the user has not registered is still not '
        'attributed to their one card', () async {
      // Digits that name *something* are a real signal even when they match
      // nothing on file — the message is about a card the app does not know
      // about, and silently filing it under the registered one would put a
      // stranger's spending on the user's statement.
      await registerHdfcCard();

      expect(await import(hdfcUnknownCardSpend, hdfcSender), isTrue);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, isNull);
      expect(saved.needsReview, isTrue);
    });
  });

  group('messages that must never become transactions', () {
    test('a PayZapp loan ad naming the card is not an expense', () async {
      await registerHdfcCard();

      expect(await import(hdfcLoanAd, hdfcSender), isFalse);
      expect(await transactionDAO.getTransactionCount(), 0);
    });

    test('an EMI *due* reminder is not a debit, even though it names an '
        'amount, an account and says the EMI "will be debited"', () async {
      await registerIciciSavings();

      expect(await import(iciciEmiReminder, iciciSender), isFalse);
      expect(await transactionDAO.getTransactionCount(), 0);
    });
  });

  group('re-linking messages imported before the account was added', () {
    test('a rescan attaches an HDFC card spend that was imported while no '
        'account existed', () async {
      // First sync: nothing registered yet, so the row is imported unassigned.
      expect(await import(hdfcCardSpend, hdfcSender), isTrue);

      final orphan = (await transactionDAO.getAllTransactions()).single;
      expect(orphan.accountId, isNull);
      expect(orphan.needsReview, isTrue);

      // The user now adds the card, and the rescan re-reads the same inbox.
      final card = await registerHdfcCard();
      // Nothing *new* is imported -- the point is that the existing row is
      // claimed rather than skipped as a duplicate.
      expect(await import(hdfcCardSpend, hdfcSender), isFalse);

      final relinked = (await transactionDAO.getAllTransactions()).single;
      expect(relinked.id, orphan.id, reason: 'adopted, not re-inserted');
      expect(relinked.accountId, card.id);
      expect(relinked.needsReview, isFalse);
      expect(await transactionDAO.getTransactionCount(), 1);
    });

    test('a rescan attaches an ICICI debit imported under a different bank\'s '
        'account', () async {
      await registerHdfcCard();
      expect(await import(iciciUpiDebit, iciciSender), isTrue);
      expect((await transactionDAO.getAllTransactions()).single.accountId,
          isNull);

      final savings = await registerIciciSavings();
      expect(await import(iciciUpiDebit, iciciSender), isFalse);

      expect((await transactionDAO.getAllTransactions()).single.accountId,
          savings.id);
    });

    test('a rescan leaves an already-linked transaction on its account', () async {
      final card = await registerHdfcCard();
      expect(await import(hdfcCardSpend, hdfcSender), isTrue);

      expect(await import(hdfcCardSpend, hdfcSender), isFalse);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, card.id);
      expect(await transactionDAO.getTransactionCount(), 1);
    });

    test('a rescan does not guess an account for a row it still cannot '
        'resolve', () async {
      expect(await import(hdfcCardSpend, hdfcSender), isTrue);

      // An HDFC account, but not the card the message names.
      await accountDAO.insertAccount(testAccount(
        bankName: 'HDFC',
        accountNumber: '1234',
        accountName: 'HDFC Savings',
      ));
      expect(await import(hdfcCardSpend, hdfcSender), isFalse);

      final saved = (await transactionDAO.getAllTransactions()).single;
      expect(saved.accountId, isNull);
      expect(saved.needsReview, isTrue);
    });
  });

  group('a full inbox in one pass', () {
    test('every real message ends up on the right account, and the two ads '
        'end up nowhere', () async {
      final card = await registerHdfcCard();
      final savings = await registerIciciSavings();

      for (final entry in const [
        [hdfcCardSpend, hdfcSender],
        [hdfcCardPayment, hdfcSender],
        [hdfcLoanAd, hdfcSender],
        [iciciEmiReminder, iciciSender],
        [iciciUpiDebit, iciciSender],
      ]) {
        await import(entry[0], entry[1]);
      }

      final all = await transactionDAO.getAllTransactions();
      expect(all.length, 3);
      expect(all.where((t) => t.accountId == null), isEmpty,
          reason: 'this is the bug being fixed — nothing may be left orphaned');

      final byAmount = {for (final t in all) t.amount: t};
      expect(byAmount[199]!.accountId, card.id);
      expect(byAmount[29393]!.accountId, card.id);
      expect(byAmount[14]!.accountId, savings.id);
    });
  });
}
