// Widget tests for the Add Transaction screen.
//
// These exist as much to pin the fix as to test the screen: the ListTile and
// RadioListTile instances used to sit inside bare Containers, so every build
// threw "ListTile background color or ink splashes may be invisible". The
// framework reports those asserts as unexpected exceptions, which made *any*
// widget test of this screen fail before it could assert anything.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expenditure_tracker/database/account_dao.dart';
import 'package:expenditure_tracker/screens/add_transaction_screen.dart';

import 'support/db_test_helper.dart';

void main() {
  setUp(() async {
    await resetTestDatabase();
  });

  tearDownAll(disposeTestDatabase);

  // initState kicks off _loadData(), which does real disk I/O through
  // sqflite_common_ffi. testWidgets runs the body under a fake clock where
  // real async work never completes, so both the seeding and the first frames
  // have to happen inside runAsync(); only then can we pump normally.
  Future<void> pumpScreen(WidgetTester tester, {bool withAccount = true}) async {
    await tester.runAsync(() async {
      if (withAccount) {
        await AccountDAO().insertAccount(testAccount());
      }
      await tester.pumpWidget(
        const MaterialApp(home: AddTransactionScreen()),
      );
      // Give _loadData() a real moment to finish and call setState().
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  testWidgets('builds without Material/ink assertions', (tester) async {
    await pumpScreen(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(ListTile), findsWidgets);
    expect(find.text('Add Transaction'), findsOneWidget);
  });

  testWidgets('every ListTile has a Material ancestor to paint ink on',
      (tester) async {
    await pumpScreen(tester);

    final tiles = find.byType(ListTile);
    expect(tiles, findsWidgets);
    for (var i = 0; i < tester.widgetList(tiles).length; i++) {
      expect(
        find.ancestor(of: tiles.at(i), matching: find.byType(Material)),
        findsWidgets,
        reason: 'ListTile #$i has no Material ancestor',
      );
    }
  });

  testWidgets('the RadioGroup toggles the transaction type in both directions',
      (tester) async {
    await pumpScreen(tester);

    RadioListTile<String> tileFor(String label) => tester.widget<RadioListTile<String>>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(RadioListTile<String>),
          ),
        );

    String? selected() => tester
        .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
        .groupValue;

    // Default is Expense; the tiles carry no per-tile onChanged any more, so
    // selection has to flow through the RadioGroup.
    expect(selected(), 'debit');
    expect(tileFor('Expense').value, 'debit');
    expect(tileFor('Income').value, 'credit');

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    expect(selected(), 'credit');

    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    expect(selected(), 'debit');
  });

  testWidgets('switching to Income hides the merchant field', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Merchant'), findsOneWidget);

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();

    expect(find.text('Merchant'), findsNothing);
  });

  testWidgets('with no accounts the save button is disabled and says so',
      (tester) async {
    await pumpScreen(tester, withAccount: false);

    expect(find.text('No accounts found. Please add an account first.'),
        findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('with an account present the save button is enabled',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('No accounts found. Please add an account first.'),
        findsNothing);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });
}
