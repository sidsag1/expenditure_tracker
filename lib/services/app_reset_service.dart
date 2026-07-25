import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import 'auth_service.dart';

// Performs a real, full local data wipe: the SQLite database file, every
// SharedPreferences key (PIN setup/onboarding flags, SMS sync markers), and
// everything in secure storage (PIN hash/salt, lockout state). Anything
// short of all three leaves data behind after a "Clear Data" action.
class AppResetService {
  AppResetService._();

  static Future<void> resetAll() async {
    await DatabaseHelper.instance.deleteDatabaseFile();

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // Must be the same configured handle AuthService wrote through: on
    // Android the plugin picks its backing store per call from the supplied
    // options, so a default-constructed instance can clear a different store
    // and silently leave the PIN hash behind.
    await AuthService.secureStorage.deleteAll();
  }
}
