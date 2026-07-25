// Lifecycle tests for the DatabaseHelper singleton itself.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:expenditure_tracker/database/database_helper.dart';

import 'support/db_test_helper.dart';

void main() {
  setUp(() async {
    await resetTestDatabase();
  });

  tearDownAll(disposeTestDatabase);

  test('close() on an unopened helper does not create the database file',
      () async {
    final path = await testDatabasePath();
    expect(File(path).existsSync(), isFalse,
        reason: 'resetTestDatabase should have deleted it');

    await DatabaseHelper.instance.close();

    // close() used to route through the `database` getter, which opens (and
    // migrates, or creates from scratch) the database purely in order to close
    // it — leaving a stray fully-built file behind every time.
    expect(File(path).existsSync(), isFalse);
  });

  test('close() is idempotent and does not resurrect the file', () async {
    final path = await testDatabasePath();

    await DatabaseHelper.instance.database;
    expect(File(path).existsSync(), isTrue);

    await DatabaseHelper.instance.close();
    await File(path).delete();

    // The second close() must be a no-op rather than re-creating the file.
    await DatabaseHelper.instance.close();
    expect(File(path).existsSync(), isFalse);
  });

  test('the helper reopens after being closed', () async {
    final db = await DatabaseHelper.instance.database;
    expect(db.isOpen, isTrue);

    await DatabaseHelper.instance.close();
    expect(db.isOpen, isFalse);

    final reopened = await DatabaseHelper.instance.database;
    expect(reopened.isOpen, isTrue);
    // A fresh open runs onCreate, so the seeded categories are there.
    final categories = await reopened.query('categories');
    expect(categories, isNotEmpty);
  });
}
