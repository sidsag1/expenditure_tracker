class Account {
  final int? id;
  final String accountType; // 'bank_account', 'debit_card', 'credit_card', 'wallet'
  final String bankName; // 'ICICI', 'Kotak', 'SBI', etc.
  final String accountNumber; // Masked account number
  final String accountName;
  final double currentBalance;
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
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

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
