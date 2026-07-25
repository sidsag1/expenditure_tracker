// P0-6: "Clear Data" must actually clear data — the DB file, every prefs
// key, and everything in secure storage — not just the auth prefs keys.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expenditure_tracker/database/account_dao.dart';
import 'package:expenditure_tracker/database/transaction_dao.dart';
import 'package:expenditure_tracker/services/app_reset_service.dart';
import 'package:expenditure_tracker/services/auth_service.dart';

import 'support/db_test_helper.dart';
import 'support/secure_storage_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetTestDatabase();
    SharedPreferences.setMockInitialValues({});
    setupMockSecureStorage();
  });

  tearDown(tearDownMockSecureStorage);

  tearDownAll(disposeTestDatabase);

  test('resetAll deletes the DB file, prefs, and secure storage', () async {
    // Seed some state: an account, a transaction, a non-auth pref, and a PIN.
    final accountId = await AccountDAO().insertAccount(testAccount());
    await TransactionDAO()
        .insertTransaction(testTransaction(accountId: accountId));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);

    final auth = AuthService();
    await auth.init();
    await auth.setPin('123456');
    expect(await auth.isPinSet, isTrue);

    final dbPath = await testDatabasePath();
    expect(File(dbPath).existsSync(), isTrue);

    await AppResetService.resetAll();

    expect(File(dbPath).existsSync(), isFalse);
    expect(prefs.containsKey('has_seen_onboarding'), isFalse);

    // Re-fetching SharedPreferences after prefs.clear() still reflects the
    // wipe (it's the same mocked instance).
    final freshPrefs = await SharedPreferences.getInstance();
    expect(freshPrefs.getKeys(), isEmpty);

    final freshAuth = AuthService();
    await freshAuth.init();
    expect(await freshAuth.isPinSet, isFalse);

    // Reopening the DB after a reset should recreate a fresh, empty schema
    // rather than resurrecting old rows.
    expect(await AccountDAO().getAllAccounts(), isEmpty);
    expect(await TransactionDAO().getAllTransactions(), isEmpty);
  });
}
