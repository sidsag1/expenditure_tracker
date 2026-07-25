import '../utils/formatters.dart';

class Transaction {
  final int? id;
  final int? accountId; // Foreign key to Account table
  final String transactionType; // 'credit', 'debit', 'transfer'
  final double amount;
  final String description;
  final String? merchant;
  final DateTime transactionDate;
  final String? referenceNumber;
  final String? transactionId; // For duplicate detection
  final String category; // 'food', 'shopping', 'transport', 'entertainment', 'bills', etc.
  final String bankName; // Source bank
  final String accountType; // 'bank_account', 'debit_card', 'credit_card', 'wallet'
  final bool isManual; // true if manually added
  final bool isPending; // true if transaction is pending
  final double? balanceAfter; // Account balance/limit parsed from the source SMS, if any
  final bool isTransfer; // true for a leg of an internal money movement (excluded from income/expense totals)
  final bool needsReview; // true for an ambiguous possible-duplicate that was imported rather than dropped
  final String source; // 'sms', 'notification' or 'manual'
  final String? rawMessageHash; // Hash of the source SMS body, for provenance
  final DateTime createdAt;
  final DateTime updatedAt;

  const Transaction({
    this.id,
    this.accountId,
    required this.transactionType,
    required this.amount,
    required this.description,
    this.merchant,
    required this.transactionDate,
    this.referenceNumber,
    this.transactionId,
    this.category = 'Uncategorized',
    required this.bankName,
    required this.accountType,
    this.isManual = false,
    this.isPending = false,
    this.balanceAfter,
    this.isTransfer = false,
    this.needsReview = false,
    this.source = 'manual',
    this.rawMessageHash,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert Transaction object to Map for database operations
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'transaction_type': transactionType,
      'amount': amount,
      'description': description,
      'merchant': merchant,
      'transaction_date': transactionDate.toIso8601String(),
      'reference_number': referenceNumber,
      'transaction_id': transactionId,
      'category': category,
      'bank_name': bankName,
      'account_type': accountType,
      'is_manual': isManual ? 1 : 0,
      'is_pending': isPending ? 1 : 0,
      'balance_after': balanceAfter,
      'is_transfer': isTransfer ? 1 : 0,
      'needs_review': needsReview ? 1 : 0,
      'source': source,
      'raw_message_hash': rawMessageHash,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Create Transaction object from Map
  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as int?,
      accountId: map['account_id'] as int?,
      transactionType: map['transaction_type'] as String,
      // SQLite stores REAL columns as int when the value has no fractional
      // part (e.g. 50.0 -> 50), so this must go through num, not double.
      amount: (map['amount'] as num).toDouble(),
      description: map['description'] as String,
      merchant: map['merchant'] as String?,
      transactionDate: DateTime.parse(map['transaction_date'] as String),
      referenceNumber: map['reference_number'] as String?,
      transactionId: map['transaction_id'] as String?,
      category: (map['category'] as String?) ?? 'Uncategorized',
      bankName: map['bank_name'] as String,
      accountType: map['account_type'] as String,
      isManual: map['is_manual'] == 1,
      isPending: map['is_pending'] == 1,
      balanceAfter: (map['balance_after'] as num?)?.toDouble(),
      isTransfer: map['is_transfer'] == 1,
      needsReview: map['needs_review'] == 1,
      source: (map['source'] as String?) ?? 'manual',
      rawMessageHash: map['raw_message_hash'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // Copy with modifications
  Transaction copyWith({
    int? id,
    int? accountId,
    String? transactionType,
    double? amount,
    String? description,
    String? merchant,
    DateTime? transactionDate,
    String? referenceNumber,
    String? transactionId,
    String? category,
    String? bankName,
    String? accountType,
    bool? isManual,
    bool? isPending,
    double? balanceAfter,
    bool? isTransfer,
    bool? needsReview,
    String? source,
    String? rawMessageHash,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      transactionType: transactionType ?? this.transactionType,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      merchant: merchant ?? this.merchant,
      transactionDate: transactionDate ?? this.transactionDate,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      transactionId: transactionId ?? this.transactionId,
      category: category ?? this.category,
      bankName: bankName ?? this.bankName,
      accountType: accountType ?? this.accountType,
      isManual: isManual ?? this.isManual,
      isPending: isPending ?? this.isPending,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      isTransfer: isTransfer ?? this.isTransfer,
      needsReview: needsReview ?? this.needsReview,
      source: source ?? this.source,
      rawMessageHash: rawMessageHash ?? this.rawMessageHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Check if transaction is an expense (debit)
  bool get isExpense => transactionType == 'debit';

  // Check if transaction is income (credit)
  bool get isIncome => transactionType == 'credit';

  // Get formatted amount with currency symbol, Indian grouping (2,89,502.00)
  String get formattedAmount {
    final sign = isExpense ? '-' : '+';
    return '$sign${formatINR(amount)}';
  }

  // Get category icon based on category type
  String get categoryIcon {
    final c = category.toLowerCase();
    if (c.contains('food') || c.contains('dining') || c.contains('restaurant')) {
      return '🍽️';
    }
    if (c.contains('grocer')) return '🛒';
    if (c.contains('transport') || c.contains('fuel')) return '🚗';
    if (c.contains('shopping') || c.contains('retail')) return '🛍️';
    if (c.contains('entertainment')) return '🎬';
    if (c.contains('bill') || c.contains('utilit')) return '💡';
    if (c.contains('health') || c.contains('medical')) return '🏥';
    if (c.contains('education')) return '📚';
    if (c.contains('travel')) return '✈️';
    if (c.contains('invest')) return '📈';
    if (c.contains('business')) return '💼';
    return '💰';
  }

  @override
  String toString() {
    return 'Transaction(id: $id, accountId: $accountId, transactionType: $transactionType, amount: $amount, description: $description, merchant: $merchant, transactionDate: $transactionDate, category: $category, bankName: $bankName)';
  }

  // Compares every field rather than just `id`: two unsaved transactions
  // (id == null) would otherwise compare equal to each other, which is what a
  // dropdown/list uses for item identity.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Transaction &&
        other.id == id &&
        other.accountId == accountId &&
        other.transactionType == transactionType &&
        other.amount == amount &&
        other.description == description &&
        other.merchant == merchant &&
        other.transactionDate == transactionDate &&
        other.referenceNumber == referenceNumber &&
        other.transactionId == transactionId &&
        other.category == category &&
        other.bankName == bankName &&
        other.accountType == accountType &&
        other.isManual == isManual &&
        other.isPending == isPending &&
        other.balanceAfter == balanceAfter &&
        other.isTransfer == isTransfer &&
        other.needsReview == needsReview &&
        other.source == source &&
        other.rawMessageHash == rawMessageHash &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        accountId,
        transactionType,
        amount,
        description,
        merchant,
        transactionDate,
        referenceNumber,
        transactionId,
        category,
        bankName,
        accountType,
        isManual,
        isPending,
        Object.hash(
          balanceAfter,
          isTransfer,
          needsReview,
          source,
          rawMessageHash,
          createdAt,
          updatedAt,
        ),
      );
}
