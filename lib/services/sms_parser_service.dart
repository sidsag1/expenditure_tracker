import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../models/account.dart';
import '../database/transaction_dao.dart';
import '../database/account_dao.dart';

class SMSParserService {
  static final SMSParserService _instance = SMSParserService._internal();
  factory SMSParserService() => _instance;
  SMSParserService._internal();

  final TransactionDAO _transactionDAO = TransactionDAO();
  final AccountDAO _accountDAO = AccountDAO();
  final Uuid _uuid = const Uuid();

  // Parse SMS message and extract transaction information
  Future<Transaction?> parseSMS(String message, String sender) async {
    try {
      final bankName = _getBankNameFromSender(sender);
      if (bankName == null) {
        return null;
      }

      Transaction? transaction;

      // Parse based on bank
      switch (bankName) {
        case 'ICICI':
          transaction = _parseICICIMessage(message);
          break;
        case 'Kotak':
          transaction = _parseKotakMessage(message);
          break;
        case 'SBI':
          transaction = _parseSBIMessage(message);
          break;
        default:
          // Try generic parsing
          transaction = _parseGenericMessage(message, bankName);
      }

      if (transaction != null) {
        // Set bank name and account type
        transaction = transaction.copyWith(
          bankName: bankName,
          accountType: _determineAccountType(message, bankName),
          transactionId: _generateTransactionId(message, sender),
        );

        // Validate transaction
        if (_isValidTransaction(transaction)) {
          return transaction;
        }
      }

      return null;
    } catch (e) {
      print('Error parsing SMS: $e');
      return null;
    }
  }

  // Parse ICICI Bank messages
  Transaction? _parseICICIMessage(String message) {
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
      final accountNumber = match.group(1)!;
      final type = match.group(2)!.toLowerCase();
      final amount = _parseAmount(match.group(3)!);
      final date = _parseDate(match.group(4)!);

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
      final date = _parseDate(match.group(3)!);
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
      final date = _parseDate(match.group(3)!);
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
      final date = _parseDate(match.group(3)!);

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
  Transaction? _parseKotakMessage(String message) {
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
      final date = _extractDate(message);

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
      final date = _extractDate(message);

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
      final date = _extractDate(message);

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
  Transaction? _parseSBIMessage(String message) {
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
      final date = _parseSBIDate(match.group(4)!);

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
      final date = _parseSBIUpiDate(match.group(3)!);

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
      final date = _parseDate(match.group(3)!);

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
  Transaction? _parseGenericMessage(String message, String bankName) {
    // Try to extract amount
    RegExp amountRegex = RegExp(
      r'(?:Rs\.?|INR)\s*([\d,]+\.?\d*)',
      caseSensitive: false,
    );

    final amountMatch = amountRegex.firstMatch(message);
    if (amountMatch == null) return null;

    final amount = _parseAmount(amountMatch.group(1)!);
    final date = _extractDate(message);

    // Determine transaction type
    final isCredit = message.toLowerCase().contains('credited') || 
                    message.toLowerCase().contains('received') ||
                    message.toLowerCase().contains('payment received');

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

  // Save transaction to database
  Future<bool> saveTransaction(Transaction transaction) async {
    try {
      // Check for duplicates
      if (await isDuplicateTransaction(transaction)) {
        return false;
      }

      await _transactionDAO.insertOrIgnoreTransaction(transaction);
      return true;
    } catch (e) {
      print('Error saving transaction: $e');
      return false;
    }
  }

  // Process multiple SMS messages
  Future<List<Transaction>> processSMSMessages(List<String> messages, String sender) async {
    final List<Transaction> processedTransactions = [];

    for (final message in messages) {
      final transaction = await parseSMS(message, sender);
      if (transaction != null) {
        final saved = await saveTransaction(transaction);
        if (saved) {
          processedTransactions.add(transaction);
        }
      }
    }

    return processedTransactions;
  }

  // Helper methods
  String? _getBankNameFromSender(String sender) {
    final upperSender = sender.toUpperCase();
    
    if (upperSender.contains('ICICI')) return 'ICICI';
    if (upperSender.contains('KOTAK')) return 'Kotak';
    if (upperSender.contains('SBI')) return 'SBI';
    
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
    return _uuid.v5(Uuid.NAMESPACE_URL, content);
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

  DateTime _parseDate(String dateStr) {
    try {
      // Handle formats like "30-Sep-25", "09-Dec-25", etc.
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = _parseMonth(parts[1]);
        final year = int.parse('20${parts[2]}'); // Assuming 20xx
        
        return DateTime(year, month, day);
      }
    } catch (e) {
      print('Error parsing date: $dateStr');
    }
    
    return DateTime.now();
  }

  DateTime _parseSBIDate(String dateStr) {
    try {
      // Handle "01.12.25" format
      final parts = dateStr.split('.');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse('20${parts[2]}');
        return DateTime(year, month, day);
      }
    } catch (e) {
      print('Error parsing SBI date: $dateStr');
    }
    return DateTime.now();
  }

  DateTime _parseSBIUpiDate(String dateStr) {
    try {
      // Handle "30Sep24" format
      final regex = RegExp(r'(\d{1,2})([A-Za-z]{3})(\d{2})');
      final match = regex.firstMatch(dateStr);
      if (match != null) {
        final day = int.parse(match.group(1)!);
        final month = _parseMonth(match.group(2)!);
        final year = int.parse('20${match.group(3)!}');
        return DateTime(year, month, day);
      }
    } catch (e) {
      print('Error parsing SBI UPI date: $dateStr');
    }
    return DateTime.now();
  }

  DateTime _extractDate(String message) {
    // Try various date patterns
    final patterns = [
      RegExp(r'(\d{1,2})-([A-Za-z]{3})-(\d{2})'),  // 30-Sep-25
      RegExp(r'(\d{1,2})/(\d{1,2})/(\d{2,4})'),     // 30/09/25 or 30/09/2025
      RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{2})'),     // 01.12.25
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        try {
          final groups = match.groups([1, 2, 3]);
          if (groups[0] != null && groups[1] != null && groups[2] != null) {
            final day = int.parse(groups[0]!);
            int month;
            if (int.tryParse(groups[1]!) != null) {
              month = int.parse(groups[1]!);
            } else {
              month = _parseMonth(groups[1]!);
            }
            int year = int.parse(groups[2]!);
            if (year < 100) year += 2000;
            return DateTime(year, month, day);
          }
        } catch (e) {
          continue;
        }
      }
    }
    return DateTime.now();
  }

  int _parseMonth(String monthStr) {
    final months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    return months[monthStr.toLowerCase()] ?? 1;
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
      RegExp(r'Ref(?:\s+No\.?)?:?\s*(\d+)', caseSensitive: false),
      RegExp(r'Refno\s*(\d+)', caseSensitive: false),
      RegExp(r'UTR\s*(\d+)', caseSensitive: false),
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
}
