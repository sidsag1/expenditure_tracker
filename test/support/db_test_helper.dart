// Shared setup for DAO/migration tests backed by a real (ffi) SQLite
// database rather than mocks, so the SQL itself is exercised.
//
// Requires the Windows Flutter-SDK-path workaround if the SDK lives under a
// path with a space in it — see scripts/setup-windows-flutter-sdk.ps1.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:expenditure_tracker/database/database_helper.dart';
import 'package:expenditure_tracker/models/account.dart';
import 'package:expenditure_tracker/models/category.dart';
import 'package:expenditure_tracker/models/transaction.dart' as models;

bool _ffiInitialized = false;
Directory? _databasesDir;

// DatabaseHelper always opens the same fixed filename
// ('expenditure_tracker.db') under getDatabasesPath(). `flutter test` runs
// each test file in its own isolate, but isolates in the same process share
// a filesystem, so without this every DB-backed test file would fight over
// one physical file when run concurrently ("database is locked", duplicate
// ALTER COLUMN). Pointing each isolate at its own temp directory keeps them
// isolated from each other while every test within a file still shares one
// file, reset between tests by resetTestDatabase().
Future<void> _ensureIsolatedDatabasesPath() async {
  if (_ffiInitialized) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final dir = await Directory.systemTemp.createTemp('expenditure_tracker_test_');
  await databaseFactory.setDatabasesPath(dir.path);
  _databasesDir = dir;
  _ffiInitialized = true;
}

// Closes the shared DatabaseHelper connection and removes this isolate's temp
// directory. Call from tearDownAll() in every DB-backed test file — otherwise
// each file leaves behind one `expenditure_tracker_test_*` directory in the
// system temp dir on every run, forever.
Future<void> disposeTestDatabase() async {
  await DatabaseHelper.instance.close();
  final dir = _databasesDir;
  _databasesDir = null;
  _ffiInitialized = false;
  if (dir != null && dir.existsSync()) {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      // Windows can still hold the sqlite file briefly after close(); a leaked
      // temp dir must never fail an otherwise-green test run.
    }
  }
}

// Closes any open DatabaseHelper connection, deletes the on-disk file and
// re-initializes sqflite_common_ffi. Call from setUp() so every test starts
// from a clean, freshly migrated (onCreate) database.
Future<void> resetTestDatabase() async {
  await _ensureIsolatedDatabasesPath();
  await DatabaseHelper.instance.close();
  final dbPath = await testDatabasePath();
  await databaseFactory.deleteDatabase(dbPath);
}

Future<String> testDatabasePath() async {
  return p.join(await getDatabasesPath(), 'expenditure_tracker.db');
}

Account testAccount({
  int? id,
  String accountType = 'bank_account',
  String bankName = 'ICICI',
  String accountNumber = 'XX1234',
  String accountName = 'Primary',
  double currentBalance = 10000,
  String? debitCard1,
  String? debitCard2,
  bool isActive = true,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final now = DateTime.now();
  return Account(
    id: id,
    accountType: accountType,
    bankName: bankName,
    accountNumber: accountNumber,
    accountName: accountName,
    currentBalance: currentBalance,
    debitCard1: debitCard1,
    debitCard2: debitCard2,
    isActive: isActive,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

models.Transaction testTransaction({
  int? accountId,
  String type = 'debit',
  double amount = 100,
  DateTime? date,
  String category = 'Uncategorized',
  String bankName = 'ICICI',
  String accountType = 'bank_account',
  String description = 'test',
  String? merchant,
  String? referenceNumber,
  String? transactionId,
  bool isManual = false,
  bool isPending = false,
  double? balanceAfter,
  bool isTransfer = false,
  bool needsReview = false,
  String? source,
  String? rawMessageHash,
}) {
  final now = DateTime.now();
  return models.Transaction(
    accountId: accountId,
    transactionType: type,
    amount: amount,
    description: description,
    merchant: merchant,
    transactionDate: date ?? now,
    referenceNumber: referenceNumber,
    transactionId: transactionId,
    category: category,
    bankName: bankName,
    accountType: accountType,
    isManual: isManual,
    isPending: isPending,
    balanceAfter: balanceAfter,
    isTransfer: isTransfer,
    needsReview: needsReview,
    source: source ?? (isManual ? 'manual' : 'sms'),
    rawMessageHash: rawMessageHash,
    createdAt: now,
    updatedAt: now,
  );
}

Category testCategory({
  String name = 'Custom Category',
  String icon = '⭐',
  String color = '#123456',
  bool isCustom = true,
}) {
  final now = DateTime.now();
  return Category(
    name: name,
    icon: icon,
    color: color,
    isCustom: isCustom,
    createdAt: now,
    updatedAt: now,
  );
}
