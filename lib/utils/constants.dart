class AppConstants {
  // Database: DatabaseHelper owns the filename and schema version. They were
  // duplicated here and had drifted (this file still claimed version 1 while
  // the schema is at 4), so the copies are gone rather than re-synced.

  // Auth: AuthService owns its own storage keys — the PIN now lives in secure
  // storage, not SharedPreferences, so the old prefs key names here were both
  // unused and actively misleading about where the PIN is kept.
  static const String hasSeenOnboardingKey = 'has_seen_onboarding';
  static const String lastSyncTimeKey = 'expenditure_tracker_last_sms_sync';
  
  // Bank SMS sender numbers
  static const Map<String, List<String>> bankSenderNumbers = {
    'ICICI': ['ICICIB', 'ICICIBK', 'ICICIL'],
    'Kotak': ['KOTAKB', 'KOTAKL', 'KOTAKM'],
    'SBI': ['SBIPSG', 'SBIPSGB', 'SBI', 'SBIN'],
    'HDFC': ['HDFCB', 'HDFCL', 'HDFCBK'],
    'Axis Bank': ['AXISB', 'AXISL', 'AXISBK'],
    'Bank of Baroda': ['BOB', 'BOBPSG', 'BOBPSGB'],
    'Punjab National Bank': ['PNB', 'PNBPSG', 'PNBPSGB'],
    'Canara Bank': ['CNRB', 'CANBK'],
    'IDBI Bank': ['IDBIB', 'IDBIBK'],
    'Yes Bank': ['YESB', 'YESL'],
    'IndusInd Bank': ['INDB', 'INDBL'],
    'Federal Bank': ['FEDBNK', 'FEDB'],
    'RBL Bank': ['RBLB', 'RBLL'],
    'South Indian Bank': ['SOUTHB', 'SOUTHL'],
    'Amazon Pay': ['AMZPAY', 'AMAZON'],
    'Google Pay': ['GPAY', 'GOOGPAY'],
    'PhonePe': ['PHONEPE', 'PPLTFIP'],
    'Paytm': ['PYTM', 'PTYM'],
  };
  
  // Categories: see Category.predefinedCategories (models/category.dart) for
  // the single canonical list — it's what seeds the database.

  // UI
  static const double borderRadius = 12.0;
  static const double cardElevation = 4.0;
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  
  // Animation
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration splashDuration = Duration(seconds: 3);
  
  // Pagination
  static const int defaultPageSize = 20;
  static const int dashboardRefreshInterval = 30000; // 30 seconds
  
  // Limits
  static const int maxAttempts = 5;
  // PIN length: fixed at 6 digits. A keypad UI with a variable-length PIN
  // needs a "done" affordance that this app's grid keypad doesn't have, so
  // every screen and AuthService validation shares this single constant.
  static const int pinLength = 6;
  static const int maxTransactionAmount = 10000000; // 1 crore

  // Lockout backoff after maxAttempts consecutive failures: 30s, 1m, 5m,
  // 15m, then holds at 15m. Index = number of lockouts triggered so far - 1.
  static const List<Duration> lockoutBackoff = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];
}
