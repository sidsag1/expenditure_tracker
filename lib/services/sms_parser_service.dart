import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../models/account.dart';
import '../database/transaction_dao.dart';
import '../database/account_dao.dart';
import '../utils/app_logger.dart';
import '../utils/constants.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;

class SMSParserService {
  static final SMSParserService _instance = SMSParserService._internal();
  factory SMSParserService() => _instance;
  SMSParserService._internal();

  final TransactionDAO _transactionDAO = TransactionDAO();
  final AccountDAO _accountDAO = AccountDAO();
  final Uuid _uuid = const Uuid();

  // Parse SMS message and extract transaction information.
  // [receivedAt] is when the SMS arrived; it is used as the transaction date
  // for messages whose body carries no date (common for wallet SMSes).
  Future<Transaction?> parseSMS(String message, String sender,
      {DateTime? receivedAt}) async {
    try {
      final bankName = _getBankNameFromSender(sender);
      if (bankName == null) {
        return null;
      }

      // Promotional / informational messages (offers, loan ads, EMI due
      // reminders, OTPs) must never become transactions.
      if (_isNonTransactionalMessage(message)) {
        return null;
      }

      Transaction? transaction;

      // Parse based on bank
      switch (bankName) {
        case 'ICICI':
          transaction = _parseICICIMessage(message, receivedAt);
          break;
        case 'Kotak':
          transaction = _parseKotakMessage(message, receivedAt);
          break;
        case 'SBI':
          transaction = _parseSBIMessage(message, receivedAt);
          break;
      }

      if (transaction == null) {
        // Try generic parsing
        transaction = _parseGenericMessage(message, bankName, receivedAt);
      }

      if (transaction != null) {
        // Set bank name, account type and the fields that don't depend on
        // which bank-specific branch produced the transaction.
        transaction = transaction.copyWith(
          bankName: bankName,
          accountType: _determineAccountType(message, bankName),
          transactionId: _generateTransactionId(message, sender),
          balanceAfter: _extractBalance(message),
          isTransfer: _isTransferPattern(message),
          source: 'sms',
          rawMessageHash: _hashMessage(message),
        );

        // Auto-categorize expenses from the merchant named in the message
        if (transaction.transactionType == 'debit') {
          final category =
              categorizeTransaction('$message ${transaction.merchant ?? ''}');
          if (category != null) {
            transaction = transaction.copyWith(category: category);
          }
        }

        // Validate transaction
        if (_isValidTransaction(transaction)) {
          return transaction;
        }
      }

      return null;
    } catch (e, stackTrace) {
      AppLogger.error('Error parsing SMS', e, stackTrace);
      return null;
    }
  }

  // Parse ICICI Bank messages
  Transaction? _parseICICIMessage(String message, DateTime? receivedAt) {
    // ICICI Bank Account Credit/Debit
    RegExp accountRegex = RegExp(
      r'ICICI Bank (?:Account|Acct) ([A-Z]{2}\d+)\s+(credited|debited).*?Rs\.?[\s]*([\d,]+\.?\d*).*?on\s+(\d{1,2}-[A-Za-z]{3}-\d{2})',
      caseSensitive: false,
    );

    // ICICI Debit Card Transaction
    RegExp debitCardRegex = RegExp(
      r'ICICI Bank (?:Debit Card|Card) ([A-Z]{2}\d+)\s+debited.*?Rs\.?\s*([\d,]+\.?\d*).*?on\s+(\d{1,2}-[A-Za-z]{3}-\d{2}).*?at\s+(.+?)(?:\.|on|$)',
      caseSensitive: false,
    );

    // ICICI Credit Card Transaction
    RegExp creditCardRegex = RegExp(
      r'(?:INR|Rs\.?)\s*([\d,]+\.?\d*)\s+spent\s+(?:using\s+)?ICICI Bank Card ([A-Z]{2}\d+).*?on\s+(\d{1,2}-[A-Za-z]{3}-\d{2})\s+on\s+(.+?)(?:\.|$)',
      caseSensitive: false,
    );

    // ICICI Credit Card Payment
    RegExp creditCardPaymentRegex = RegExp(
      r'Payment of Rs\.?\s*([\d,]+\.?\d*)\s+has been received.*?ICICI Bank Credit Card ([A-Z]{2}\d+).*?on\s+(\d{1,2}-[A-Za-z]{3}-\d{2})',
      caseSensitive: false,
    );

    Match? match;

    // Try account message
    match = accountRegex.firstMatch(message);
    if (match != null) {
      final type = match.group(2)!.toLowerCase();
      final amount = _parseAmount(match.group(3)!);
      final date = _parseDate(match.group(4)!) ?? receivedAt ?? DateTime.now();

      return Transaction(
        transactionType: type == 'credited' ? 'credit' : 'debit',
        amount: amount,
        description: type == 'credited' ? 'Account credit' : 'Account debit',
        merchant: type == 'debited' ? _extractMerchant(message) : null,
        transactionDate: date,
        referenceNumber: _extractReferenceNumber(message),
        bankName: 'ICICI',
        accountType: 'bank_account',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // Try debit card message
    match = debitCardRegex.firstMatch(message);
    if (match != null) {
      final amount = _parseAmount(match.group(2)!);
      final date = _parseDate(match.group(3)!) ?? receivedAt ?? DateTime.now();
      final merchant = match.group(4)!.trim();

      return Transaction(
        transactionType: 'debit',
        amount: amount,
        description: 'Debit card transaction',
        merchant: merchant,
        transactionDate: date,
        referenceNumber: _extractReferenceNumber(message),
        bankName: 'ICICI',
        accountType: 'debit_card',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // Try credit card message
    match = creditCardRegex.firstMatch(message);
    if (match != null) {
      final amount = _parseAmount(match.group(1)!);
      final date = _parseDate(match.group(3)!) ?? receivedAt ?? DateTime.now();
      final merchant = _normalizeMerchantText(match.group(4));

      return Transaction(
        transactionType: 'debit',
        amount: amount,
        description: 'Credit card purchase',
        merchant: merchant,
        transactionDate: date,
        referenceNumber: _extractReferenceNumber(message),
        bankName: 'ICICI',
        accountType: 'credit_card',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // Try credit card payment message
    match = creditCardPaymentRegex.firstMatch(message);
    if (match != null) {
      final amount = _parseAmount(match.group(1)!);
      final date = _parseDate(match.group(3)!) ?? receivedAt ?? DateTime.now();

      return Transaction(
        transactionType: 'credit',
        amount: amount,
        description: 'Credit card payment received',
        transactionDate: date,
        referenceNumber: _extractReferenceNumber(message),
        bankName: 'ICICI',
        accountType: 'credit_card',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    return null;
  }

  // Parse Kotak Bank messages
  Transaction? _parseKotakMessage(String message, DateTime? receivedAt) {
    // Kotak Debit Card Transaction
    RegExp debitCardRegex = RegExp(
      r'Rs\.?\s*([\d,]+\.?\d*)\s+spent\s+via Kotak Debit Card ([A-Z]{2}\d+).*?at\s+(.+?)(?:\.|\s+on)',
      caseSensitive: false,
    );

    // Kotak UPI Transaction
    RegExp upiRegex = RegExp(
      r'(?:Sent|Received)\s+Rs\.?\s*([\d,]+\.?\d*)\s+(?:from|to).*?Kotak.*?AC\s+([A-Z]\d+).*?(?:to|from)\s+(.+?)(?:\.|\s+on)',
      caseSensitive: false,
    );

    // Kotak IMPS Transaction
    RegExp impsRegex = RegExp(
      r'(?:Received|IMPS from).*?Rs\.?\s*([\d,]+\.?\d*).*?(?:on|in).*?Kotak.*?A\/C\s+([A-Z]\d+).*?(?:\.|\s+IMPS)',
      caseSensitive: false,
    );

    Match? match;

    // Try debit card message
    match = debitCardRegex.firstMatch(message);
    if (match != null) {
      final amount = _parseAmount(match.group(1)!);
      final merchant = _normalizeMerchantText(match.group(3));
      final date = _extractDate(message) ?? receivedAt ?? DateTime.now();

      return Transaction(
        transactionType: 'debit',
        amount: amount,
        description: 'Debit card transaction',
        merchant: merchant,
        transactionDate: date,
        referenceNumber: _extractReferenceNumber(message),
        bankName: 'Kotak',
        accountType: 'debit_card',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // Try UPI message
    match = upiRegex.firstMatch(message);
    if (match != null) {
      final amount = _parseAmount(match.group(1)!);
      final isSent = message.toLowerCase().contains('sent');
      final recipient = _normalizeMerchantText(match.group(3));
      final date = _extractDate(message) ?? receivedAt ?? DateTime.now();

      return Transaction(
        transactionType: isSent ? 'debit' : 'credit',
        amount: amount,
        description: isSent ? 'UPI payment sent' : 'UPI payment received',
        merchant: recipient,
        transactionDate: date,
        referenceNumber: _extractReferenceNumber(message),
        bankName: 'Kotak',
        accountType: 'bank_account',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // Try IMPS message
    match = impsRegex.firstMatch(message);
    if (match != null) {
      final amount = _parseAmount(match.group(1)!);
      final isReceived = message.toLowerCase().contains('received');
      final date = _extractDate(message) ?? receivedAt ?? DateTime.now();

      return Transaction(
        transactionType: isReceived ? 'credit' : 'debit',
        amount: amount,
        description: isReceived ? 'IMPS received' : 'IMPS transfer',
        transactionDate: date,
        referenceNumber: _extractReferenceNumber(message),
        bankName: 'Kotak',
        accountType: 'bank_account',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    return null;
  }

  // Parse SBI Bank messages
  Transaction? _parseSBIMessage(String message, DateTime? receivedAt) {
    // SBI IMPS Transfer
    RegExp impsRegex = RegExp(
      r'IMPS from Ac ([A-Z]\d+)\s+for Rs\.?\s*([\d,]+\.?\d*).*?Ref\s+(\d+).*?dt\s+(\d{1,2}\.\d{1,2}\.\d{2})',
      caseSensitive: false,
    );

    // SBI UPI Transaction
    RegExp upiRegex = RegExp(
      // The date token is a 3-letter month abbreviation ("09Dec25"), matching
      // what _parseSBIUpiDate itself expects -- a stray {2} here used to make
      // this whole regex (and therefore the message) fail to match at all.
      r'A\/C\s+([A-Z]\d+)\s+debited\s+by\s+(?:Rs\.?|INR)?\s*([\d,]+\.?\d*).*?date\s+(\d{1,2}[A-Za-z]{3}\d{2}).*?trf\s+to\s+(.+?)\s+Refno',
      caseSensitive: false,
    );

    // SBI Account Credit
    RegExp creditRegex = RegExp(
      r'Your a\/c.*?(\d+)\s+is credited\s+by\s+Rs\.?\s*([\d,]+\.?\d*).*?on\s+(\d{1,2}-\d{2}-\d{2})',
      caseSensitive: false,
    );

    Match? match;

    // Try IMPS message
    match = impsRegex.firstMatch(message);
    if (match != null) {
      final amount = _parseAmount(match.group(2)!);
      final date = _parseSBIDate(match.group(4)!) ?? receivedAt ?? DateTime.now();

      return Transaction(
        transactionType: 'debit',
        amount: amount,
        description: 'IMPS transfer',
        transactionDate: date,
        referenceNumber: match.group(3),
        bankName: 'SBI',
        accountType: 'bank_account',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // Try UPI message
    match = upiRegex.firstMatch(message);
    if (match != null) {
      final amount = _parseAmount(match.group(2)!);
      final merchant = _normalizeMerchantText(match.group(4));
      final date = _parseSBIUpiDate(match.group(3)!) ?? receivedAt ?? DateTime.now();

      return Transaction(
        transactionType: 'debit',
        amount: amount,
        description: 'UPI transaction',
        merchant: merchant,
        transactionDate: date,
        referenceNumber: _extractReferenceNumber(message),
        bankName: 'SBI',
        accountType: 'bank_account',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // Try credit message
    match = creditRegex.firstMatch(message);
    if (match != null) {
      final amount = _parseAmount(match.group(2)!);
      final date = _parseDate(match.group(3)!) ?? receivedAt ?? DateTime.now();

      return Transaction(
        transactionType: 'credit',
        amount: amount,
        description: 'Account credit',
        transactionDate: date,
        referenceNumber: _extractReferenceNumber(message),
        bankName: 'SBI',
        accountType: 'bank_account',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    return null;
  }

  // Generic parser for unsupported banks
  Transaction? _parseGenericMessage(
      String message, String bankName, DateTime? receivedAt) {
    // Only treat the message as a transaction if it describes money actually
    // moving; an amount alone (e.g. in a loan or cashback ad) is not enough.
    if (!_containsTransactionVerb(message)) return null;

    // Strip out balance phrases before scanning for amount
    String messageWithoutBalance = message;
    final balancePatterns = [
      RegExp(r'Avl\.?\s*[Bb]al(?:ance)?[:.]?\s*(?:Rs\.?|INR)\s*[\d,]+\.?\d*', caseSensitive: false),
      RegExp(r'Available\s+Balance\s+is\s+(?:Rs\.?|INR)\s*[\d,]+\.?\d*', caseSensitive: false),
      RegExp(r'Avl\.?\s*Limit\s*:?\s*(?:Rs\.?|INR)\s*[\d,]+\.?\d*', caseSensitive: false),
      RegExp(r'Available\s+Limit\s+is\s+(?:Rs\.?|INR)\s*[\d,]+\.?\d*', caseSensitive: false),
    ];
    for (final pattern in balancePatterns) {
      messageWithoutBalance = messageWithoutBalance.replaceAll(pattern, '');
    }

    // Try to extract amount
    RegExp amountRegex = RegExp(
      r'(?:Rs\.?|INR|Rupees)\s*([\d,]+\.?\d*)',
      caseSensitive: false,
    );

    final amountMatch = amountRegex.firstMatch(messageWithoutBalance);
    if (amountMatch == null) return null;

    final amount = _parseAmount(amountMatch.group(1)!);
    // Wallet SMSes often carry no date; fall back to when the SMS arrived
    final date = _extractDate(message) ?? receivedAt ?? DateTime.now();

    final sign = _determineGenericSign(message);
    if (sign == null) return null; // a declined/failed txn moved no money

    return Transaction(
      transactionType: sign,
      amount: amount,
      description: sign == 'credit' ? 'Credit transaction' : 'Debit transaction',
      merchant: _extractMerchant(message),
      transactionDate: date,
      referenceNumber: _extractReferenceNumber(message),
      bankName: bankName,
      accountType: 'bank_account',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // Whether a generic-bank message is a credit or a debit, or null if it
  // describes money that never actually moved (a declined/failed attempt).
  // Checked as an ordered set of explicit cases rather than a flat
  // bag-of-words OR-chain: the old `contains('credited')` check mis-signed
  // "not credited" and "refund received" as ordinary credits, and had no way
  // to represent "this never happened" for a declined transaction at all.
  String? _determineGenericSign(String message) {
    final lower = message.toLowerCase();

    if (RegExp(r'\b(?:declined|failed)\b').hasMatch(lower) &&
        !lower.contains('refund')) {
      return null;
    }
    if (lower.contains('not credited') || lower.contains('not debited')) {
      return null;
    }
    // "Payment request received" / "collect request" is a UPI collect
    // *request* landing on the device -- an ask for money, not money that has
    // actually moved. The bare 'received' check below would otherwise mark
    // it a credit even though nothing has been paid yet.
    if (lower.contains('payment request') ||
        lower.contains('collect request') ||
        lower.contains('requested money')) {
      return null;
    }
    if (lower.contains('refund') || RegExp(r'\breversed\b').hasMatch(lower)) {
      return 'credit';
    }
    if (lower.contains('credited') ||
        lower.contains('received') ||
        lower.contains('added to')) {
      return 'credit';
    }
    return 'debit';
  }

  // Fetches the active-accounts list once so a caller processing many
  // messages in one sync batch can pass it into repeated saveTransaction
  // calls instead of re-querying per message (see saveTransaction).
  Future<List<Account>> loadActiveAccounts({DatabaseExecutor? txn}) {
    return _accountDAO.getActiveAccounts(txn: txn);
  }

  // Check if transaction already exists (duplicate detection)
  Future<bool> isDuplicateTransaction(Transaction transaction,
      {DatabaseExecutor? txn}) async {
    if (transaction.transactionId == null) return false;

    final existingTransaction = await _transactionDAO
        .getTransactionByTransactionId(transaction.transactionId!, txn: txn);

    return existingTransaction != null;
  }

  // Save transaction to database. [sourceMessage] is the raw SMS body, used
  // to match the account/card number named in the message against the
  // registered accounts — always pass it, or nothing can be linked.
  //
  // Returns true only for a *newly imported* row. A message already on file
  // returns false but is still re-linked if the account can now be resolved
  // and wasn't before, which is what makes a rescan repair earlier imports.
  //
  // [activeAccounts], when passed, is used instead of re-querying the DB for
  // the active-accounts list -- a caller processing many messages in one
  // sync batch (see SMSService.syncMessages) fetches it once per batch and
  // reuses it here, rather than hitting SQLite on every single message.
  Future<bool> saveTransaction(Transaction transaction,
      {String? sourceMessage,
      DatabaseExecutor? txn,
      List<Account>? activeAccounts}) async {
    try {
      // A match on a linked debit card lands on the bank account itself, so
      // the transaction goes straight onto that account's statement; a
      // message whose bank isn't registered, or whose account is ambiguous
      // within a tracked bank, is still imported (see _matchAccount) rather
      // than dropped, just unassigned and flagged for the user to resolve.
      final match = await _matchAccount(transaction, sourceMessage ?? '',
          txn: txn, activeAccounts: activeAccounts);

      // Already imported? Re-linking, not re-inserting, is the point here.
      // Messages read before the user had registered the account they belong
      // to were stored unassigned, and their transaction_id (a hash of the
      // message) never changes — so a rescan after adding the account would
      // otherwise dedup against those rows and leave them orphaned forever,
      // with no way in the app to ever attach them. Adopt them instead.
      final existing = await _findExistingTransaction(transaction, txn: txn);
      if (existing != null) {
        if (existing.id != null &&
            existing.accountId == null &&
            match.account?.id != null) {
          await _adoptUnassignedTransaction(existing, match.account!,
              needsReview: match.needsReview, txn: txn);
        }
        return false;
      }

      var linked = transaction.copyWith(
        accountId: match.account?.id,
        needsReview: transaction.needsReview || match.needsReview || match.account == null,
      );

      // Banks often send two SMSes for the same event; keep only a confirmed
      // duplicate off the books entirely. An ambiguous same-day/same-amount
      // candidate is still imported (dropping it risks losing real money)
      // but flagged so the user can resolve it later. (No-op when the
      // account itself is unassigned -- there's nothing yet to compare
      // against.)
      final duplicateMatch =
          await _transactionDAO.findDuplicateMatch(linked, txn: txn);
      if (duplicateMatch == DuplicateMatch.confirmed) {
        return false;
      }
      if (duplicateMatch == DuplicateMatch.ambiguous) {
        linked = linked.copyWith(needsReview: true);
      }

      final insertedId =
          await _transactionDAO.insertOrIgnoreTransaction(linked, txn: txn);
      if (insertedId == 0) {
        // Lost a race against another sync inserting the same transaction_id.
        return false;
      }

      // Update the account's balance from the message, if it carried one and
      // isn't older than what's already on record.
      if (linked.accountId != null && linked.balanceAfter != null) {
        await _accountDAO.updateBalanceIfNewer(
          linked.accountId!,
          linked.balanceAfter!,
          linked.transactionDate,
          txn: txn,
        );
      }

      await _pairTransferLeg(linked.copyWith(id: insertedId), txn: txn);

      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Error saving transaction', e, stackTrace);
      return false;
    }
  }

  // The row already on file for this message, if any. Keyed on
  // transaction_id, which is a hash of the message body plus sender, so the
  // same SMS re-read by a later rescan always resolves to the same row.
  Future<Transaction?> _findExistingTransaction(Transaction transaction,
      {DatabaseExecutor? txn}) async {
    if (transaction.transactionId == null) return null;
    return _transactionDAO
        .getTransactionByTransactionId(transaction.transactionId!, txn: txn);
  }

  // Attach a previously unassigned row to the account a rescan has now
  // resolved for it, and give it the same follow-up treatment a fresh import
  // gets: the balance the message carried is only useful once there's an
  // account to put it on, and the row only becomes eligible to pair with the
  // other leg of a transfer now that it sits on an account.
  Future<void> _adoptUnassignedTransaction(
      Transaction existing, Account account,
      {required bool needsReview, DatabaseExecutor? txn}) async {
    await _transactionDAO.linkTransactionToAccount(existing.id!, account.id!,
        needsReview: needsReview, txn: txn);

    final adopted =
        existing.copyWith(accountId: account.id, needsReview: needsReview);

    if (adopted.balanceAfter != null) {
      await _accountDAO.updateBalanceIfNewer(
        account.id!,
        adopted.balanceAfter!,
        adopted.transactionDate,
        txn: txn,
      );
    }

    await _pairTransferLeg(adopted, txn: txn);
  }

  // Look for the other leg of an internal transfer (e.g. a credit-card bill
  // payment debited from a bank account and credited to the card) among the
  // user's other registered accounts, and mark both rows so income/expense
  // aggregates exclude them. Always attempted, even when this leg is already
  // pattern-flagged: whichever leg lands *first* has no counterpart to find
  // yet, so this is what retroactively marks it once the second leg
  // (pattern-flagged or not) arrives.
  Future<void> _pairTransferLeg(Transaction leg, {DatabaseExecutor? txn}) async {
    if (leg.id == null) return;
    final offset =
        await _transactionDAO.findOffsettingTransaction(leg, txn: txn);
    if (offset != null && offset.id != null) {
      await _transactionDAO.markTransferPair(leg.id!, offset.id!, txn: txn);
    }
  }

  // Process multiple SMS messages
  Future<List<Transaction>> processSMSMessages(List<String> messages, String sender) async {
    final List<Transaction> processedTransactions = [];

    for (final message in messages) {
      final transaction = await parseSMS(message, sender);
      if (transaction != null) {
        final saved = await saveTransaction(transaction, sourceMessage: message);
        if (saved) {
          processedTransactions.add(transaction);
        }
      }
    }

    return processedTransactions;
  }

  // Find the registered (active) account this message belongs to.
  //
  // `account` is only ever non-null for a *confident* match; `needsReview`
  // means the message's bank is tracked but which specific account it
  // belongs to is unclear (multiple accounts at that bank and nothing in the
  // message to disambiguate, or a digit run that's too short/ambiguous to
  // trust) or was never resolved at all (digits present but none of them
  // match a registered account/card). `(null, false)` means the bank itself
  // isn't tracked -- no account of that bank registered at all, typically
  // because the user hasn't added it *yet*.
  //
  // Every one of those cases is imported unassigned rather than guessed at
  // or dropped: the money is real either way, and a later rescan re-runs
  // this match and adopts the row once the account exists (see
  // saveTransaction).
  Future<({Account? account, bool needsReview})> _matchAccount(
      Transaction transaction, String message,
      {DatabaseExecutor? txn, List<Account>? activeAccounts}) async {
    final accounts =
        activeAccounts ?? await _accountDAO.getActiveAccounts(txn: txn);
    final bankAccounts = accounts
        .where((a) => _bankNamesMatch(a.bankName, transaction.bankName))
        .toList();
    if (bankAccounts.isEmpty) {
      return (account: null, needsReview: false);
    }

    // Deliberately not filtered to runs the matcher below can act on: a run
    // too short to bind ("Card 18") still means the message named an account,
    // and the narrowing below must not then treat it as though it named none.
    final messageDigits = _extractAccountDigits(message);
    if (messageDigits.isEmpty) {
      if (bankAccounts.length == 1) {
        return (account: bankAccounts.first, needsReview: false);
      }

      // Nothing in the message names a specific account, but the message
      // itself says what *kind* of account it happened on (see
      // _determineAccountType and the per-pattern accountType each parser
      // branch sets). If exactly one registered account at this bank is of
      // that kind, there is nothing left to guess at: a savings-account debit
      // can only be the one savings account, whatever else the user holds at
      // the same bank.
      //
      // This is what the digit-less back-catalogue depends on. Banks quote the
      // card's last four on essentially every card alert, so a message that
      // names no digits at all is overwhelmingly an account-level one; before
      // this, a user with a savings account and two credit cards at one bank
      // had every such message flagged for manual review forever.
      //
      // Still a narrowing, not a fallback: two accounts of the same kind at
      // one bank stay ambiguous and land in review, because that is the case
      // where guessing would misattribute real money.
      final sameKind = bankAccounts
          .where((a) => a.accountType == transaction.accountType)
          .toList();
      if (sameKind.length == 1) {
        return (account: sameKind.first, needsReview: false);
      }

      // Multiple accounts at this bank and nothing in the message names
      // which one -- guessing (the old behaviour) silently misattributes
      // real money to the wrong account's statement.
      return (account: null, needsReview: true);
    }

    // Require at least 3 matching digits and prefer the longest match: a
    // 2-digit suffix (e.g. "18" lifted from a helpline number elsewhere in
    // the message) is common enough by chance to bind to the wrong account.
    Account? bestAccount;
    int bestLen = 0;
    var tie = false;
    for (final account in bankAccounts) {
      final numbers = [account.accountNumber, ...account.debitCards];
      var accountBestLen = 0;
      for (final number in numbers) {
        final stored = number.replaceAll(RegExp(r'\D'), '');
        if (stored.isEmpty) continue;
        for (final digits in messageDigits) {
          if (digits.length < 3) continue;
          // Banks mask numbers to different lengths (XX340 vs XX4340), so
          // one side being the suffix of the other counts as a match.
          if (stored.endsWith(digits) || digits.endsWith(stored)) {
            final matchedLen =
                stored.length < digits.length ? stored.length : digits.length;
            if (matchedLen > accountBestLen) accountBestLen = matchedLen;
          }
        }
      }
      if (accountBestLen > bestLen) {
        bestLen = accountBestLen;
        bestAccount = account;
        tie = false;
      } else if (accountBestLen > 0 && accountBestLen == bestLen) {
        tie = true;
      }
    }

    if (bestAccount != null) {
      return tie
          ? (account: null, needsReview: true)
          : (account: bestAccount, needsReview: false);
    }

    // Wallets (Blinkit, Paytm, ...) are often registered without a number
    // because their SMSes rarely name one; a brand match is enough.
    for (final account in bankAccounts) {
      if (account.accountType == 'wallet' &&
          account.accountNumber.replaceAll(RegExp(r'\D'), '').isEmpty) {
        return (account: account, needsReview: false);
      }
    }

    // The message named account/card digits but none matched a registered
    // account -- don't silently discard the money, flag it for the user to
    // assign manually.
    return (account: null, needsReview: true);
  }

  bool _bankNamesMatch(String a, String b) {
    final first = a.toLowerCase().trim();
    final second = b.toLowerCase().trim();
    if (first.isEmpty || second.isEmpty) return false;
    // 'Kotak Mahindra' should match 'Kotak', 'HDFC' should match 'HDFC Bank'
    return first.contains(second) || second.contains(first);
  }

  // Pull masked account/card numbers like "Card x6955", "Acct XX340",
  // "A/C X2285" or "CARD ENDING WITH 6955" out of a message.
  List<String> _extractAccountDigits(String message) {
    final regex = RegExp(
      r'\b(?:account|acct|a\/c|card|ac)\b[^0-9]{0,20}?(\d{2,8})',
      caseSensitive: false,
    );
    return regex
        .allMatches(message)
        .map((m) => m.group(1)!)
        .toList();
  }

  // True for offers, ads, EMI due reminders, OTPs and other messages that
  // mention money without an actual transaction having happened.
  //
  // Two-stage: a message with a strong transaction signature (amount + verb
  // + account/card token + a real date) is a genuine alert even though real
  // bank templates routinely also carry "Do not share your OTP/CVV" or a
  // "Know more" link -- so the broad marker list below must not veto it. Only
  // the narrow, unambiguous denylist can override a strong signature: phrasing
  // (an OTP delivery, a loan ad, a due-date reminder, an EMI-conversion offer)
  // that never describes money having already moved, however transaction-shaped
  // the rest of the message looks.
  bool _isNonTransactionalMessage(String message) {
    final lower = message.toLowerCase();

    const hardVeto = [
      'otp is',
      'otp for',
      'is your otp',
      'one time password',
      'unlock loan',
      'pre-approved',
      'pre approved',
      // Instalment/bill reminders. These carry a full transaction signature
      // by accident -- an amount, an account token, and a verb, because the
      // body goes on to explain the money "will be debited" -- so the softer
      // marker list below can't veto them and an EMI reminder would import
      // as a real debit on its due date.
      'is due on',
      'payment is due',
      'due date',
      'amount due',
      'maintain sufficient funds',
      'maintain sufficient balance',
      // "Convert your bill into EMIs" nudges hit the same problem from the
      // other side: they quote the bill amount, name the card, and say
      // "convert txns", and 'txn' is a transaction verb.
      'can be paid in parts',
      'convert txns into emi',
      'convert txn into emi',
      'convert to emi',
      'check eligibility',
      'instant cash',
      'cash alert',
      'ready to be credited',
      'ready to be disbursed',
    ];
    if (hardVeto.any(lower.contains)) return true;

    if (_isStatementNotification(lower)) return true;

    if (_hasStrongTransactionSignature(message)) return false;

    const markers = [
      'best deal',
      'deal alert',
      'apply now',
      'know more',
      'click here',
      't&c',
      'offer',
      'discount',
      'cashback offer',
      'congratulations',
      'due on',
      'do not share',
      'will be credited',
      'avail now',
    ];
    return markers.any(lower.contains);
  }

  // True for "your statement has been sent to <email>" style notifications.
  // The figure they quote is the whole cycle's outstanding balance -- the sum
  // of purchases already imported one by one from their own alerts -- so
  // importing the summary as well double-counts the entire month. They reach
  // here carrying a full transaction signature (amount, card token, and the
  // verb 'sent' out of "has been sent to"), so only a hard veto stops them.
  //
  // Deliberately narrow, and a conjunction rather than either half alone.
  // Card alerts routinely mention a statement in passing ("this will reflect
  // in your next statement"), quote cycle totals alongside a real
  // transaction, and say 'sent' about ordinary payments -- "Rs 500 sent to
  // Ravi" is a UPI debit. Widening this to those phrasings swallowed every
  // refund on the account: a refund alert names the same statement the
  // purchase landed on, so the only thing that reliably separates a
  // statement notification from a transaction is that it announces the
  // statement being *delivered* somewhere.
  //
  // [lower] must already be lower-cased.
  bool _isStatementNotification(String lower) {
    if (!lower.contains('statement')) return false;
    const deliveryMarkers = [
      'sent to',
      'has been sent',
      'emailed',
      'email id',
    ];
    return deliveryMarkers.any(lower.contains);
  }

  // Amount + a transaction verb + an account/card token + a resolvable date,
  // all present -- the shape every genuine bank transaction alert has, and
  // ad/reminder copy essentially never does by accident (see hardVeto above
  // for the cases that do).
  bool _hasStrongTransactionSignature(String message) {
    final hasAmount =
        RegExp(r'(?:Rs\.?|INR|Rupees)\s*[\d,]+\.?\d*', caseSensitive: false)
            .hasMatch(message);
    final hasAccountToken =
        RegExp(r'\b(?:a\/c|acct|account|card|ac)\b', caseSensitive: false)
            .hasMatch(message);
    return hasAmount &&
        hasAccountToken &&
        _containsTransactionVerb(message);
  }

  // True when the message describes money actually moving.
  bool _containsTransactionVerb(String message) {
    final lower = message.toLowerCase();
    const verbs = [
      'debited',
      'credited',
      'spent',
      'sent',
      'received',
      'paid',
      'payment',
      'withdrawn',
      'deposited',
      'transferred',
      'purchase',
      'txn',
      'added', // wallet top-ups: "Rs X added to your ... account"
      'without otp', // card autopay format: "Rs.X without OTP/PIN ... At <merchant>"
    ];
    return verbs.any(lower.contains);
  }

  // Guess a spending category from the merchant/brand named in the text.
  // Returns a name from Category.predefinedCategories, or null if unknown.
  // Whole-word matching so e.g. 'ola' doesn't fire inside 'chocolate'.
  String? categorizeTransaction(String text) {
    final lower = text.toLowerCase();

    // Order matters: more specific brands first ('amazon fresh' is
    // Groceries even though 'amazon' alone is Shopping).
    const categoryKeywords = <String, List<String>>{
      'Groceries': [
        'amazon fresh', 'zepto', 'blinkit', 'blnkit', 'bigbasket',
        'big basket', 'instamart', 'jiomart', 'dmart', 'd-mart', 'grofers',
        'nature basket', 'grocery', 'groceries', 'kirana', 'supermarket',
        'more retail', 'star bazaar',
      ],
      'Food & Dining': [
        'zomato', 'swiggy', 'eatsure', 'faasos', 'box8', 'dominos',
        "domino's", 'pizza hut', 'mcdonald', 'mcdonalds', 'kfc',
        'burger king', 'subway', 'starbucks', 'cafe coffee day', 'ccd',
        'barbeque nation', 'haldiram', 'biryani', 'restaurant', 'eatery',
        'dhaba', 'cafe', 'bakery', 'dunkin', 'wow momo', 'behrouz',
      ],
      'Travel': [
        'indigo', 'goindigo', 'air india', 'airindia', 'spicejet',
        'vistara', 'akasa air', 'akasaair', 'emirates', 'qatar airways',
        'lufthansa', 'airline', 'airlines', 'airways', 'irctc',
        'makemytrip', 'goibibo', 'cleartrip', 'ixigo', 'yatra',
        'easemytrip', 'redbus', 'abhibus', 'oyo', 'airbnb', 'agoda',
        'booking.com', 'treebo', 'fabhotels', 'hotel', 'resort',
      ],
      'Transportation': [
        'uber', 'ola cabs', 'olacabs', 'rapido', 'blusmart', 'meru',
        'fastag', 'metro card', 'namma metro', 'dmrc', 'petrol', 'diesel',
        'fuel', 'indian oil', 'indianoil', 'iocl', 'hpcl', 'bpcl',
        'bharat petroleum', 'hindustan petroleum', 'shell', 'parking',
      ],
      'Entertainment': [
        'netflix', 'hotstar', 'prime video', 'primevideo', 'sonyliv',
        'zee5', 'jiocinema', 'jiohotstar', 'spotify', 'gaana', 'wynk',
        'youtube premium', 'bookmyshow', 'pvr', 'inox', 'cinepolis',
        'multiplex', 'playstation', 'steam games', 'xbox',
      ],
      'Health & Medical': [
        'apollo', 'pharmeasy', '1mg', 'tata 1mg', 'netmeds', 'medplus',
        'practo', 'pharmacy', 'chemist', 'hospital', 'clinic',
        'diagnostic', 'pathology', 'medical', 'medicals', 'cult.fit',
        'cultfit', 'healthifyme',
      ],
      'Education': [
        'udemy', 'coursera', 'upgrad', 'byjus', "byju's", 'unacademy',
        'vedantu', 'physics wallah', 'skillshare', 'school fee',
        'college fee', 'tuition', 'university',
      ],
      'Bills & Utilities': [
        'electricity', 'power bill', 'water bill', 'gas bill',
        'broadband', 'wifi bill', 'postpaid', 'prepaid recharge',
        'recharge', 'dth', 'tata sky', 'tatasky', 'tata play', 'airtel',
        'jio', 'vodafone', 'bsnl', 'bescom', 'mseb', 'tneb', 'bses',
        'tata power', 'adani electricity', 'indane', 'hp gas', 'lpg',
      ],
      'Shopping': [
        'amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa',
        'snapdeal', 'tata cliq', 'tatacliq', 'croma', 'reliance digital',
        'vijay sales', 'decathlon', 'ikea', 'lifestyle', 'pantaloons',
        'westside', 'zudio', 'max fashion', 'shoppers stop',
        'reliance trends', 'firstcry', 'lenskart', 'titan', 'tanishq',
      ],
      'Investment': [
        'zerodha', 'groww', 'upstox', 'angel one', 'angelone',
        'mutual fund', 'sip installment', 'nps ', 'ppf ', 'etmoney',
        'indmoney', 'smallcase',
      ],
    };

    for (final entry in categoryKeywords.entries) {
      for (final keyword in entry.value) {
        final pattern =
            RegExp('\\b${RegExp.escape(keyword)}', caseSensitive: false);
        if (pattern.hasMatch(lower)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  // Helper methods
  String? _getBankNameFromSender(String sender) {
    final upperSender = sender.toUpperCase();

    for (final entry in AppConstants.bankSenderNumbers.entries) {
      for (final number in entry.value) {
        if (upperSender.contains(number.toUpperCase())) {
          return entry.key;
        }
      }
    }

    return null;
  }

  String _determineAccountType(String message, String bankName) {
    final lowerMessage = message.toLowerCase();
    
    if (lowerMessage.contains('debit card')) {
      return 'debit_card';
    } else if (lowerMessage.contains('credit card') || lowerMessage.contains('card xx')) {
      return 'credit_card';
    } else if (lowerMessage.contains('upi')) {
      return 'bank_account';
    }
    
    return 'bank_account';
  }

  String _generateTransactionId(String message, String sender) {
    // Create a unique ID based on message content and sender
    final content = message + sender;
    return _uuid.v5(Namespace.url.value, content);
  }

  bool _isValidTransaction(Transaction transaction) {
    // Basic validation
    if (transaction.amount <= 0) return false;
    if (transaction.bankName.isEmpty) return false;
    if (transaction.transactionType.isEmpty) return false;
    
    return true;
  }

  double _parseAmount(String amountStr) {
    // Remove commas and parse
    final cleanAmount = amountStr.replaceAll(',', '');
    return double.tryParse(cleanAmount) ?? 0.0;
  }

  // Parses "dd-MMM-yy" (ICICI) or "dd-MM-yy" (SBI account credit) dates.
  // Returns null on anything that doesn't resolve to a real calendar date so
  // callers fall back to the SMS's received time instead of fabricating one.
  DateTime? _parseDate(String dateStr) {
    final parts = dateStr.split('-');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = _parseMonth(parts[1]);
    final year = _composeYear(parts[2]);
    if (day == null || month == null || year == null) return null;
    return _validDate(year, month, day);
  }

  // Handles SBI's "01.12.25" format.
  DateTime? _parseSBIDate(String dateStr) {
    final parts = dateStr.split('.');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = _composeYear(parts[2]);
    if (day == null || month == null || year == null) return null;
    return _validDate(year, month, day);
  }

  // Handles SBI UPI's "30Sep24" format.
  DateTime? _parseSBIUpiDate(String dateStr) {
    final match = RegExp(r'(\d{1,2})([A-Za-z]{3})(\d{2})').firstMatch(dateStr);
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final month = _parseMonth(match.group(2)!);
    final year = _composeYear(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    return _validDate(year, month, day);
  }

  // Returns null when the message body carries no recognizable date. A date
  // immediately following a marker keyword (on/dt/dated/date) is preferred
  // over the first digit-triplet found anywhere in the message, so a
  // reference or phone number elsewhere in the text isn't mistaken for one.
  DateTime? _extractDate(String message) {
    final markerMatches = RegExp(
      r'\b(?:on|dt|dated|date)\b[:\s]+(\S+)',
      caseSensitive: false,
    ).allMatches(message);

    DateTime? bestDate;
    for (final markerMatch in markerMatches) {
      final fromMarker = _extractDateFromText(markerMatch.group(1)!);
      if (fromMarker != null) {
        bestDate = fromMarker;
      }
    }
    if (bestDate != null) return bestDate;

    return _extractDateFromText(message);
  }

  DateTime? _extractDateFromText(String text) {
    // ISO order first: 2026-06-13 (also seen in HDFC card alerts)
    final isoMatch =
        RegExp(r'(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)').firstMatch(text);
    if (isoMatch != null) {
      final date = _validDate(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
      if (date != null) return date;
    }

    // Day-first patterns. Boundary guards keep these from matching inside a
    // longer digit run (e.g. a reference or phone number).
    final patterns = [
      RegExp(r'(?<!\d)(\d{1,2})-([A-Za-z]{3})-(\d{2,4})(?!\d)'), // 30-Sep-25
      RegExp(r'(?<!\d)(\d{1,2})/([A-Za-z]{3})/(\d{2,4})(?!\d)'), // 07/JUL/2026
      RegExp(r'(?<!\d)(\d{1,2})/(\d{1,2})/(\d{2,4})(?!\d)'),     // 30/09/25
      RegExp(r'(?<!\d)(\d{1,2})-(\d{1,2})-(\d{2,4})(?!\d)'),     // 15-07-26
      RegExp(r'(?<!\d)(\d{1,2})\.(\d{1,2})\.(\d{2,4})(?!\d)'),   // 01.12.25
      RegExp(r'(?<!\d)(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{2,4})(?!\d)'), // 30 Sep 25 / 30 September 2025
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final groups = match.groups([1, 2, 3]);
      final day = int.tryParse(groups[0]!);
      final month = int.tryParse(groups[1]!) ?? _parseMonth(groups[1]!);
      final year = _composeYear(groups[2]!);
      if (day == null || month == null || year == null) continue;
      final date = _validDate(year, month, day);
      if (date != null) return date;
    }
    return null;
  }

  // Builds a calendar date, rejecting out-of-range components and the silent
  // month/day rollover DateTime() would otherwise perform (e.g. day 32).
  // Also rejects dates more than a day in the future — bank SMSes never
  // describe transactions that haven't happened yet, so a "future" date here
  // means the parse latched onto the wrong digits (e.g. a 2-digit year read
  // as 2099) — callers fall back to receivedAt instead.
  DateTime? _validDate(int year, int month, int day) {
    if (year < 2000 || year > 2100) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    if (date.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      return null;
    }
    return date;
  }

  // Two-digit years from bank SMSes are always 20xx.
  int? _composeYear(String yearStr) {
    final value = int.tryParse(yearStr);
    if (value == null) return null;
    return value < 100 ? 2000 + value : value;
  }

  // Returns the 1-12 month number for a name ('sep') or numeric ('09')
  // token, or null when it's neither — e.g. a bad/unknown abbreviation must
  // not silently resolve to January.
  int? _parseMonth(String monthStr) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final lower = monthStr.toLowerCase();
    // Full month names ("September") reduce to the same 3-letter key as the
    // abbreviation ("sep") the map is keyed on.
    final named = months[lower] ?? (lower.length > 3 ? months[lower.substring(0, 3)] : null);
    if (named != null) return named;
    final numeric = int.tryParse(monthStr);
    if (numeric != null && numeric >= 1 && numeric <= 12) return numeric;
    return null;
  }

  // Stops the merchant capture at the footer boilerplate every bank SMS
  // template appends right after the payee name, plus a *word-boundary*
  // 'on'/'dated' -- the old unanchored `(?:\.|on|$)` terminator matched the
  // literal letters "on" anywhere, including mid-word ("MONITOR" -> "M",
  // "ONLINE" -> "").
  static const String _merchantStopPattern =
      r'(?=\s*(?:\b(?:on|dated)\b|[.;]|Ref|UPI|Avl|Not you|Not U|Call|Block|SMS|A\/c|Acct|Account)|$)';

  String? _extractMerchant(String message) {
    // Try to extract merchant name from common patterns
    final patterns = [
      RegExp(r'\bat\s+(.+?)' + _merchantStopPattern, caseSensitive: false),
      RegExp(r'\bto\s+(.+?)' + _merchantStopPattern, caseSensitive: false),
      RegExp(r'\bfrom\s+(.+?)' + _merchantStopPattern, caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        final merchant = _normalizeMerchantText(match.group(1));
        // A genuine merchant name has a letter in it; a bare digit run means
        // the "to"/"at"/"from" anchor latched onto something else entirely,
        // e.g. the dispute-line phone number in "...SMS BLOCK 340 to
        // 9215676766." A merchant candidate that's all digits is discarded
        // rather than returned.
        if (merchant != null &&
            merchant.isNotEmpty &&
            merchant.length < 100 &&
            RegExp(r'[A-Za-z]').hasMatch(merchant)) {
          return merchant;
        }
      }
    }
    return null;
  }

  // Strips the UPI merchant-code prefixes and trailing masked card digits
  // banks glue onto the raw payee string, and collapses whitespace, so
  // "PYU*SAFRESH TECHNOLOGY  PR" and "MERCHANT 6955" read as a name rather
  // than a wire-format token.
  String? _normalizeMerchantText(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    text =
        text.replaceFirst(RegExp(r'^(?:PYU\*|UPI\/)', caseSensitive: false), '');
    text = text.replaceFirst(RegExp(r'\s+[xX]{0,2}\d{3,6}$'), '');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? null : text;
  }

  String? _extractReferenceNumber(String message) {
    final patterns = [
      RegExp(r'Ref(?:[.\s]*No\.?)?[:#]?\s*([\w-]*\d[\w-]*)', caseSensitive: false),
      RegExp(r'Refno\s*(\d+)', caseSensitive: false),
      RegExp(r'UTR\s*(\d+)', caseSensitive: false),
      RegExp(r'UPI[:\s]+(\d+)', caseSensitive: false),
      RegExp(r'Txn\s*(?:ID|No\.?)?\s*:?\s*(\d+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  // Pulls the trailing account balance / available credit limit out of a
  // message body ("Avl bal Rs.247.77", "Available Balance is Rs. 2,97,158.22",
  // "Avl Limit: INR 1,45,739.72", "YOUR AVAILABLE LIMIT IS RS. 686166.10").
  // Bank-agnostic: applied to every parsed transaction regardless of which
  // bank-specific branch produced it.
  double? _extractBalance(String message) {
    final patterns = [
      RegExp(r'Avl\.?\s*[Bb]al(?:ance)?[:.]?\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)',
          caseSensitive: false),
      RegExp(r'Available\s+Balance\s+is\s+(?:Rs\.?|INR)\s*([\d,]+\.?\d*)',
          caseSensitive: false),
      RegExp(r'Avl\.?\s*Limit\s*:?\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)',
          caseSensitive: false),
      RegExp(r'Available\s+Limit\s+is\s+(?:Rs\.?|INR)\s*([\d,]+\.?\d*)',
          caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        return _parseAmount(match.group(1)!);
      }
    }
    return null;
  }

  // True for messages describing an internal movement of the user's own
  // money rather than genuine income/spending: a credit-card bill payment
  // (debited from a bank account, credited to the card), including one paid
  // through BBPS. Matched on the raw message text since these notifications
  // carry no reference number or merchant to cross-reference against.
  bool _isTransferPattern(String message) {
    final lower = message.toLowerCase();
    const explicitMarkers = [
      'credit card payment received',
      'payment received towards your card',
      'received towards your credit card',
      'credited to your card',
    ];
    if (explicitMarkers.any(lower.contains)) return true;

    // BBPS is also the rail banks use for ordinary third-party bill payments
    // (electricity, gas, DTH) debited straight from a bank account — a
    // genuine expense, not an internal transfer. A bare 'bbps'/'bharat bill
    // payment system' substring match can't tell the two apart, so only
    // treat it as a transfer when the message is specifically a payment
    // *received* on a *card* (the credit-card-bill-payment pattern above,
    // phrased slightly differently) rather than any BBPS-mentioning message.
    final mentionsBbps = lower.contains('bharat bill payment system') ||
        lower.contains('bbps');
    final isCardPaymentReceived =
        lower.contains('card') && lower.contains('received');
    return mentionsBbps && isCardPaymentReceived;
  }

  // SHA-256 of the raw SMS body, kept on the transaction row for provenance
  // (e.g. tracing a row back to the exact message that produced it).
  String _hashMessage(String message) =>
      sha256.convert(utf8.encode(message)).toString();
}
