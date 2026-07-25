import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../models/account.dart';
import '../database/transaction_dao.dart';
import '../database/account_dao.dart';
import '../utils/app_logger.dart';

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
        default:
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
      r'(?:INR|Rs\.)\s*([\d,]+\.?\d*)\s+spent\s+(?:using\s+)?ICICI Bank Card ([A-Z]{2}\d+).*?on\s+(\d{1,2}-[A-Za-z]{3}-\d{2})\s+on\s+(.+?)(?:\.|$)',
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
      final merchant = match.group(4)!.trim();

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
      r'Rs\.?([\d,]+\.?\d*)\s+spent\s+via Kotak Debit Card ([A-Z]{2}\d+).*?at\s+(.+?)(?:\.|\s+on)',
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
      final merchant = match.group(3)!.trim();
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
      final recipient = match.group(3)!.trim();
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
      r'A\/C\s+([A-Z]\d+)\s+debited\s+by\s+([\d,]+\.?\d*).*?date\s+(\d{1,2}[A-Za-z]{2}\d{2}).*?trf\s+to\s+(.+?)\s+Refno',
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
      final merchant = match.group(4)!.trim();
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

    // Try to extract amount
    RegExp amountRegex = RegExp(
      r'(?:Rs\.?|INR)\s*([\d,]+\.?\d*)',
      caseSensitive: false,
    );

    final amountMatch = amountRegex.firstMatch(message);
    if (amountMatch == null) return null;

    final amount = _parseAmount(amountMatch.group(1)!);
    // Wallet SMSes often carry no date; fall back to when the SMS arrived
    final date = _extractDate(message) ?? receivedAt ?? DateTime.now();

    // Determine transaction type
    final isCredit = message.toLowerCase().contains('credited') ||
                    message.toLowerCase().contains('received') ||
                    message.toLowerCase().contains('payment received') ||
                    message.toLowerCase().contains('added to');

    return Transaction(
      transactionType: isCredit ? 'credit' : 'debit',
      amount: amount,
      description: isCredit ? 'Credit transaction' : 'Debit transaction',
      merchant: _extractMerchant(message),
      transactionDate: date,
      referenceNumber: _extractReferenceNumber(message),
      bankName: bankName,
      accountType: 'bank_account',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  // Check if transaction already exists (duplicate detection)
  Future<bool> isDuplicateTransaction(Transaction transaction) async {
    if (transaction.transactionId == null) return false;
    
    final existingTransaction = await _transactionDAO
        .getTransactionByTransactionId(transaction.transactionId!);
    
    return existingTransaction != null;
  }

  // Save transaction to database. Only transactions that belong to an
  // account the user has registered are saved; [sourceMessage] is the raw
  // SMS body, used to match the account/card number in the message against
  // the registered accounts.
  Future<bool> saveTransaction(Transaction transaction,
      {String? sourceMessage}) async {
    try {
      // Check for duplicates
      if (await isDuplicateTransaction(transaction)) {
        return false;
      }

      // Only keep transactions for accounts the user has added. A match on a
      // linked debit card lands on the bank account itself, so the
      // transaction goes straight onto that account's statement.
      final account =
          await _findRegisteredAccount(transaction, sourceMessage ?? '');
      if (account == null) {
        return false;
      }

      var linked = transaction.copyWith(accountId: account.id);

      // Banks often send two SMSes for the same event; keep only a confirmed
      // duplicate off the books entirely. An ambiguous same-day/same-amount
      // candidate is still imported (dropping it risks losing real money)
      // but flagged so the user can resolve it later.
      final duplicateMatch = await _transactionDAO.findDuplicateMatch(linked);
      if (duplicateMatch == DuplicateMatch.confirmed) {
        return false;
      }
      if (duplicateMatch == DuplicateMatch.ambiguous) {
        linked = linked.copyWith(needsReview: true);
      }

      final insertedId = await _transactionDAO.insertOrIgnoreTransaction(linked);
      if (insertedId == 0) {
        // Lost a race against another sync inserting the same transaction_id.
        return false;
      }

      // Update the account's balance from the message, if it carried one and
      // isn't older than what's already on record.
      if (linked.balanceAfter != null) {
        await _accountDAO.updateBalanceIfNewer(
          account.id!,
          linked.balanceAfter!,
          linked.transactionDate,
        );
      }

      // Look for the other leg of an internal transfer (e.g. a credit-card
      // bill payment debited from a bank account and credited to the card)
      // among the user's other registered accounts, and mark both rows so
      // income/expense aggregates exclude them. Always attempted, even when
      // this leg is already pattern-flagged: whichever leg saves *first* has
      // no counterpart to find yet, so this is what retroactively marks it
      // once the second leg (pattern-flagged or not) arrives.
      final offset = await _transactionDAO
          .findOffsettingTransaction(linked.copyWith(id: insertedId));
      if (offset != null && offset.id != null) {
        await _transactionDAO.markTransferPair(insertedId, offset.id!);
      }

      return true;
    } catch (e, stackTrace) {
      AppLogger.error('Error saving transaction', e, stackTrace);
      return false;
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

  // Find the registered (active) account this message belongs to, or null if
  // the user has not added a matching account.
  Future<Account?> _findRegisteredAccount(
      Transaction transaction, String message) async {
    final accounts = await _accountDAO.getActiveAccounts();
    final bankAccounts = accounts
        .where((a) => _bankNamesMatch(a.bankName, transaction.bankName))
        .toList();
    if (bankAccounts.isEmpty) return null;

    final messageDigits = _extractAccountDigits(message);
    if (messageDigits.isEmpty) {
      // Message names no account/card number; the bank itself is registered,
      // so attach the transaction to that bank's account.
      return bankAccounts.first;
    }

    for (final account in bankAccounts) {
      // A message naming a linked debit card belongs to the bank account
      final numbers = [account.accountNumber, ...account.debitCards];
      for (final number in numbers) {
        final stored = number.replaceAll(RegExp(r'\D'), '');
        if (stored.isEmpty) continue;
        for (final digits in messageDigits) {
          // Banks mask numbers to different lengths (XX340 vs XX4340), so one
          // side being the suffix of the other counts as a match.
          if (stored.endsWith(digits) || digits.endsWith(stored)) {
            return account;
          }
        }
      }
    }

    // Wallets (Blinkit, Paytm, ...) are often registered without a number
    // because their SMSes rarely name one; a brand match is enough.
    for (final account in bankAccounts) {
      if (account.accountType == 'wallet' &&
          account.accountNumber.replaceAll(RegExp(r'\D'), '').isEmpty) {
        return account;
      }
    }

    return null;
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
  bool _isNonTransactionalMessage(String message) {
    final lower = message.toLowerCase();
    const markers = [
      'best deal',
      'deal alert',
      'unlock loan',
      'pre-approved',
      'pre approved',
      'apply now',
      'know more',
      'click here',
      't&c',
      'offer',
      'discount',
      'cashback offer',
      'congratulations',
      'is due on',
      'due on',
      'otp is',
      'otp for',
      'is your otp',
      'one time password',
      'do not share',
      // Loan/cash ads phrased in the future tense ("ready to be credited")
      'instant cash',
      'cash alert',
      'ready to be credited',
      'will be credited',
      'ready to be disbursed',
      'avail now',
      // Credit card bill "convert to EMI" nudges quote the bill amount
      // without any money having moved
      'can be paid in parts',
      'convert txns into emi',
      'convert txn into emi',
      'convert to emi',
      'check eligibility',
    ];
    return markers.any(lower.contains);
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

    // Banks with dedicated parsers
    if (upperSender.contains('ICICI')) return 'ICICI';
    if (upperSender.contains('KOTAK')) return 'Kotak';
    if (upperSender.contains('SBI')) return 'SBI';

    // Banks/wallets handled by the generic parser
    const genericSenders = {
      'HDFC': 'HDFC',
      'AXIS': 'Axis Bank',
      'BOB': 'Bank of Baroda',
      'PNB': 'Punjab National Bank',
      'CNRB': 'Canara Bank',
      'CANBK': 'Canara Bank',
      'IDBI': 'IDBI Bank',
      'YESB': 'Yes Bank',
      'INDB': 'IndusInd Bank',
      'FEDB': 'Federal Bank',
      'RBLB': 'RBL Bank',
      'SOUTHB': 'South Indian Bank',
      'AMZPAY': 'Amazon Pay',
      'AMAZON': 'Amazon Pay',
      'GPAY': 'Google Pay',
      'GOOGPAY': 'Google Pay',
      'PHONEPE': 'PhonePe',
      'PPLTFIP': 'PhonePe',
      'PYTM': 'Paytm',
      'BLNKIT': 'Blinkit',
      'BLINKIT': 'Blinkit',
      'ZEPTO': 'Zepto',
      'MOBIKWIK': 'MobiKwik',
      'MBKWIK': 'MobiKwik',
      'FREECHARGE': 'Freecharge',
      'FRECHG': 'Freecharge',
    };
    for (final entry in genericSenders.entries) {
      if (upperSender.contains(entry.key)) return entry.value;
    }

    return null;
  }

  String _determineAccountType(String message, String bankName) {
    final lowerMessage = message.toLowerCase();
    
    if (lowerMessage.contains('credit card') || lowerMessage.contains('card xx')) {
      return 'credit_card';
    } else if (lowerMessage.contains('debit card')) {
      return 'debit_card';
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
    final markerMatch = RegExp(
      r'\b(?:on|dt|dated|date)\b[:\s]+(\S+)',
      caseSensitive: false,
    ).firstMatch(message);
    if (markerMatch != null) {
      final fromMarker = _extractDateFromText(markerMatch.group(1)!);
      if (fromMarker != null) return fromMarker;
    }
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
    final named = months[monthStr.toLowerCase()];
    if (named != null) return named;
    final numeric = int.tryParse(monthStr);
    if (numeric != null && numeric >= 1 && numeric <= 12) return numeric;
    return null;
  }

  String? _extractMerchant(String message) {
    // Try to extract merchant name from common patterns
    final patterns = [
      RegExp(r'at\s+(.+?)(?:\.|on|$)', caseSensitive: false),
      RegExp(r'to\s+(.+?)(?:\.|on|$)', caseSensitive: false),
      RegExp(r'from\s+(.+?)(?:\.|on|$)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        final merchant = match.group(1)?.trim();
        if (merchant != null && merchant.isNotEmpty && merchant.length < 100) {
          return merchant;
        }
      }
    }
    return null;
  }

  String? _extractReferenceNumber(String message) {
    final patterns = [
      RegExp(r'Ref(?:\s+No\.?)?[:#]?\s*(\w*\d\w*)', caseSensitive: false),
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
      RegExp(r'Avl\.?\s*[Bb]al(?:ance)?\.?\s*(?:Rs\.?|INR)\s*([\d,]+\.?\d*)',
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
