// Unit tests for the data models: Transaction, Account, and Category.

import 'package:flutter_test/flutter_test.dart';

import 'package:expenditure_tracker/models/account.dart';
import 'package:expenditure_tracker/models/category.dart';
import 'package:expenditure_tracker/models/transaction.dart';

void main() {
  final now = DateTime(2026, 7, 19, 10, 30);

  group('Transaction model', () {
    Transaction buildTransaction() => Transaction(
          id: 1,
          accountId: 2,
          transactionType: 'debit',
          amount: 1499.50,
          description: 'Debit card transaction',
          merchant: 'Amazon',
          transactionDate: DateTime(2026, 7, 15),
          referenceNumber: '123456',
          transactionId: 'txn-abc',
          category: 'shopping',
          bankName: 'ICICI',
          accountType: 'debit_card',
          isManual: false,
          isPending: false,
          createdAt: now,
          updatedAt: now,
        );

    test('toMap/fromMap round-trip preserves all fields', () {
      final original = buildTransaction();
      final restored = Transaction.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.accountId, original.accountId);
      expect(restored.transactionType, original.transactionType);
      expect(restored.amount, original.amount);
      expect(restored.description, original.description);
      expect(restored.merchant, original.merchant);
      expect(restored.transactionDate, original.transactionDate);
      expect(restored.referenceNumber, original.referenceNumber);
      expect(restored.transactionId, original.transactionId);
      expect(restored.category, original.category);
      expect(restored.bankName, original.bankName);
      expect(restored.accountType, original.accountType);
      expect(restored.isManual, original.isManual);
      expect(restored.isPending, original.isPending);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('fromMap defaults missing category to uncategorized', () {
      final map = buildTransaction().toMap()..remove('category');
      map['category'] = null;
      expect(Transaction.fromMap(map).category, 'uncategorized');
    });

    test('copyWith overrides only the given fields', () {
      final updated = buildTransaction().copyWith(
        amount: 200.0,
        transactionType: 'credit',
      );
      expect(updated.amount, 200.0);
      expect(updated.transactionType, 'credit');
      expect(updated.merchant, 'Amazon');
      expect(updated.bankName, 'ICICI');
    });

    test('isExpense/isIncome reflect transaction type', () {
      final debit = buildTransaction();
      final credit = debit.copyWith(transactionType: 'credit');
      expect(debit.isExpense, isTrue);
      expect(debit.isIncome, isFalse);
      expect(credit.isIncome, isTrue);
      expect(credit.isExpense, isFalse);
    });

    test('formattedAmount uses sign, rupee symbol and Indian grouping', () {
      final debit = buildTransaction();
      expect(debit.formattedAmount, '-₹1,499.50');
      expect(debit.copyWith(transactionType: 'credit').formattedAmount,
          '+₹1,499.50');
      // Lakh grouping: 2,89,502.00 not 289,502.00
      expect(debit.copyWith(amount: 289502.00).formattedAmount,
          '-₹2,89,502.00');
    });

    test('categoryIcon maps known categories and falls back', () {
      final txn = buildTransaction();
      expect(txn.copyWith(category: 'food').categoryIcon, '🍽️');
      expect(txn.copyWith(category: 'Food & Dining').categoryIcon, '🍽️');
      expect(txn.copyWith(category: 'Groceries').categoryIcon, '🛒');
      expect(txn.copyWith(category: 'travel').categoryIcon, '✈️');
      expect(txn.copyWith(category: 'somethingelse').categoryIcon, '💰');
    });

    test('equality is based on id', () {
      final a = buildTransaction();
      final b = buildTransaction().copyWith(amount: 9999.0);
      expect(a, equals(b));
    });
  });

  group('Account model', () {
    Account buildAccount() => Account(
          id: 5,
          accountType: 'bank_account',
          bankName: 'SBI',
          accountNumber: 'XX1234',
          accountName: 'Salary Account',
          currentBalance: 25000.75,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        );

    test('toMap/fromMap round-trip preserves all fields', () {
      final original = buildAccount();
      final restored = Account.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.accountType, original.accountType);
      expect(restored.bankName, original.bankName);
      expect(restored.accountNumber, original.accountNumber);
      expect(restored.accountName, original.accountName);
      expect(restored.currentBalance, original.currentBalance);
      expect(restored.isActive, original.isActive);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('toMap stores isActive as integer flag', () {
      expect(buildAccount().toMap()['is_active'], 1);
      expect(buildAccount().copyWith(isActive: false).toMap()['is_active'], 0);
    });

    test('copyWith overrides only the given fields', () {
      final updated = buildAccount().copyWith(currentBalance: 100.0);
      expect(updated.currentBalance, 100.0);
      expect(updated.bankName, 'SBI');
      expect(updated.accountNumber, 'XX1234');
    });

    test('debit card numbers survive a toMap/fromMap round-trip', () {
      final acc = buildAccount().copyWith(
        debitCard1: 'XX7297',
        debitCard2: 'XX4016',
      );
      final restored = Account.fromMap(acc.toMap());
      expect(restored.debitCard1, 'XX7297');
      expect(restored.debitCard2, 'XX4016');
      expect(restored.debitCards, ['XX7297', 'XX4016']);
    });

    test('debitCards omits empty slots', () {
      expect(buildAccount().debitCards, isEmpty);
      expect(buildAccount().copyWith(debitCard1: 'XX7297').debitCards,
          ['XX7297']);
    });

    test('balanceLabel depends on account type', () {
      expect(buildAccount().balanceLabel, 'Current Balance');
      expect(
        buildAccount().copyWith(accountType: 'credit_card').balanceLabel,
        'Available Credit Limit',
      );
    });
  });

  group('Category model', () {
    test('toMap/fromMap round-trip preserves all fields', () {
      final original = Category(
        id: 3,
        name: 'Groceries',
        icon: '🛒',
        color: '#00CEC9',
        isCustom: true,
        createdAt: now,
        updatedAt: now,
      );
      final restored = Category.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.icon, original.icon);
      expect(restored.color, original.color);
      expect(restored.isCustom, original.isCustom);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('predefined categories are complete and marked non-custom', () {
      final categories = Category.predefinedCategories;
      expect(categories, hasLength(12));
      expect(categories.every((c) => !c.isCustom), isTrue);
      expect(categories.map((c) => c.name), contains('Uncategorized'));
      expect(
        categories.map((c) => c.name).toSet().length,
        categories.length,
        reason: 'category names should be unique',
      );
    });
  });
}
