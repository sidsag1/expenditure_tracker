import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

// Debug-only logging via dart:developer (visible in DevTools/IDE consoles)
// instead of `print`, which ships to stdout in release builds too.
class AppLogger {
  AppLogger._();

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      developer.log(
        message,
        name: 'expenditure_tracker',
        error: error,
        stackTrace: stackTrace,
        level: 1000,
      );
    }
  }
}
