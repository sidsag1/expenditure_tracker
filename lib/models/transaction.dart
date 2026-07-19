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
    this.category = 'uncategorized',
    required this.bankName,
    required this.accountType,
    this.isManual = false,
    this.isPending = false,
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
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Create Transaction object from Map
  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      accountId: map['account_id'],
      transactionType: map['transaction_type'],
      amount: map['amount'],
      description: map['description'],
      merchant: map['merchant'],
      transactionDate: DateTime.parse(map['transaction_date']),
      referenceNumber: map['reference_number'],
      transactionId: map['transaction_id'],
      category: map['category'] ?? 'uncategorized',
      bankName: map['bank_name'],
      accountType: map['account_type'],
      isManual: map['is_manual'] == 1,
      isPending: map['is_pending'] == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Transaction && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
