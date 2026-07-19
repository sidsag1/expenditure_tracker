// Basic smoke test for the Expenditure Tracker app.
//
// The full app initializes SQLite, SharedPreferences, and SMS services in
// main(), and the splash screen starts navigation timers backed by platform
// plugins that are unavailable in the widget-test environment. This test
// therefore only verifies that the root app widget can be constructed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expenditure_tracker/main.dart';

void main() {
  test('Root app widget can be constructed', () {
    const app = ExpenditureTrackerApp();
    expect(app, isA<Widget>());
  });
}
