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
          balanceAfter: 297158.22,
          isTransfer: true,
          needsReview: true,
          source: 'sms',
          rawMessageHash: 'abc123',
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
      expect(restored.balanceAfter, original.balanceAfter);
      expect(restored.isTransfer, original.isTransfer);
      expect(restored.needsReview, original.needsReview);
      expect(restored.source, original.source);
      expect(restored.rawMessageHash, original.rawMessageHash);
      expect(restored.createdAt, original.createdAt);
      expect(restored.updatedAt, original.updatedAt);
    });

    test('fromMap defaults missing source to manual and balanceAfter to null',
        () {
      final map = buildTransaction().toMap()
        ..remove('source')
        ..remove('balance_after');
      final restored = Transaction.fromMap(map);
      expect(restored.source, 'manual');
      expect(restored.balanceAfter, isNull);
    });

    test('fromMap accepts an int-typed balance_after column', () {
      final map = buildTransaction().toMap();
      map['balance_after'] = 300000; // e.g. a stored 300000.0 comes back as int
      final restored = Transaction.fromMap(map);
      expect(restored.balanceAfter, 300000.0);
      expect(restored.balanceAfter, isA<double>());
    });

    test('fromMap defaults missing category to Uncategorized', () {
      final map = buildTransaction().toMap()..remove('category');
      map['category'] = null;
      expect(Transaction.fromMap(map).category, 'Uncategorized');
    });

    test('fromMap accepts an int-typed amount column (SQLite returns int for whole-number REALs)',
        () {
      final map = buildTransaction().toMap();
      map['amount'] = 50; // e.g. a stored 50.0 comes back as int, not double
      final restored = Transaction.fromMap(map);
      expect(restored.amount, 50.0);
      expect(restored.amount, isA<double>());
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

    test('equality compares every field, not just id', () {
      final a = buildTransaction();
      final identical = buildTransaction();
      final differentAmount = buildTransaction().copyWith(amount: 9999.0);

      // Two unsaved (id == null) transactions with different content must
      // not compare equal — this is what an account/category dropdown uses
      // for item identity. copyWith can't null out id (id ?? this.id), so
      // these are built directly.
      Transaction unsaved(double amount) => Transaction(
            transactionType: 'debit',
            amount: amount,
            description: 'unsaved',
            transactionDate: now,
            bankName: 'ICICI',
            accountType: 'bank_account',
            createdAt: now,
            updatedAt: now,
          );

      expect(a, equals(identical));
      expect(a, isNot(equals(differentAmount)));
      expect(unsaved(10), isNot(equals(unsaved(20))));
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

    test('fromMap accepts an int-typed current_balance column (SQLite returns int for whole-number REALs)',
        () {
      final map = buildAccount().toMap();
      map['current_balance'] = 25000; // e.g. a stored 25000.0 comes back as int
      final restored = Account.fromMap(map);
      expect(restored.currentBalance, 25000.0);
      expect(restored.currentBalance, isA<double>());
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

    test('equality compares every field, not just id', () {
      final a = buildAccount();
      final identical = buildAccount();
      final differentBalance = buildAccount().copyWith(currentBalance: 1.0);

      // Two unsaved (id == null) accounts with different content must not
      // compare equal — this is what the Add Transaction screen's account
      // dropdown uses for item identity. copyWith can't null out id
      // (id ?? this.id), so these are built directly.
      Account unsaved(String accountName) => Account(
            accountType: 'bank_account',
            bankName: 'SBI',
            accountNumber: 'XX1234',
            accountName: accountName,
            currentBalance: 0,
            createdAt: now,
            updatedAt: now,
          );

      expect(a, equals(identical));
      expect(a, isNot(equals(differentBalance)));
      expect(unsaved('A'), isNot(equals(unsaved('B'))));
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

    test('equality compares every field, not just id', () {
      // Two unsaved (id == null) custom categories with different content
      // must not compare equal.
      final a = Category(
        name: 'Aquarium Supplies',
        icon: '🐠',
        color: '#00BCD4',
        isCustom: true,
        createdAt: now,
        updatedAt: now,
      );
      final b = Category(
        name: 'Gardening',
        icon: '🌱',
        color: '#4CAF50',
        isCustom: true,
        createdAt: now,
        updatedAt: now,
      );
      final identicalToA = Category(
        name: 'Aquarium Supplies',
        icon: '🐠',
        color: '#00BCD4',
        isCustom: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(a, equals(identicalToA));
      expect(a, isNot(equals(b)));
    });
  });
}
