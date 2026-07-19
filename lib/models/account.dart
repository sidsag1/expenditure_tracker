class Account {
  final int? id;
  final String accountType; // 'bank_account', 'credit_card', 'wallet'
  final String bankName; // 'ICICI', 'Kotak', 'SBI', etc.
  final String accountNumber; // Masked account number
  final String accountName;
  final double currentBalance; // For credit cards: available credit limit
  final String? debitCard1; // Bank accounts: last digits of a linked debit card
  final String? debitCard2; // Bank accounts: second linked debit card (max 2)
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Account({
    this.id,
    required this.accountType,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
    required this.currentBalance,
    this.debitCard1,
    this.debitCard2,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  // Convert Account object to Map for database operations
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_type': accountType,
      'bank_name': bankName,
      'account_number': accountNumber,
      'account_name': accountName,
      'current_balance': currentBalance,
      'debit_card_1': debitCard1,
      'debit_card_2': debitCard2,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Create Account object from Map
  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'],
      accountType: map['account_type'],
      bankName: map['bank_name'],
      accountNumber: map['account_number'],
      accountName: map['account_name'],
      currentBalance: map['current_balance'],
      debitCard1: map['debit_card_1'],
      debitCard2: map['debit_card_2'],
      isActive: map['is_active'] == 1,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  // Copy with modifications
  Account copyWith({
    int? id,
    String? accountType,
    String? bankName,
    String? accountNumber,
    String? accountName,
    double? currentBalance,
    String? debitCard1,
    String? debitCard2,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Account(
      id: id ?? this.id,
      accountType: accountType ?? this.accountType,
      bankName: bankName ?? this.bankName,
      accountNumber: accountNumber ?? this.accountNumber,
      accountName: accountName ?? this.accountName,
      currentBalance: currentBalance ?? this.currentBalance,
      debitCard1: debitCard1 ?? this.debitCard1,
      debitCard2: debitCard2 ?? this.debitCard2,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Non-empty debit card numbers linked to this account
  List<String> get debitCards => [
        if (debitCard1 != null && debitCard1!.trim().isNotEmpty) debitCard1!,
        if (debitCard2 != null && debitCard2!.trim().isNotEmpty) debitCard2!,
      ];

  // The label for what currentBalance represents for this account type
  String get balanceLabel =>
      accountType == 'credit_card' ? 'Available Credit Limit' : 'Current Balance';

  @override
  String toString() {
    return 'Account(id: $id, accountType: $accountType, bankName: $bankName, accountNumber: $accountNumber, accountName: $accountName, currentBalance: $currentBalance, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Account && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
