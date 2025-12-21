class AppConstants {
  // Database
  static const String databaseName = 'expenditure_tracker.db';
  static const int databaseVersion = 1;
  
  // Auth
  static const String pinKey = 'expenditure_tracker_pin';
  static const String biometricKey = 'expenditure_tracker_biometric';
  static const String isFirstLaunchKey = 'expenditure_tracker_first_launch';
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
  
  // Categories
  static const List<Map<String, dynamic>> predefinedCategories = [
    {'name': 'Food & Dining', 'icon': '🍽️', 'color': '#FF6B6B'},
    {'name': 'Transportation', 'icon': '🚗', 'color': '#4ECDC4'},
    {'name': 'Shopping', 'icon': '🛍️', 'color': '#45B7D1'},
    {'name': 'Entertainment', 'icon': '🎬', 'color': '#96CEB4'},
    {'name': 'Bills & Utilities', 'icon': '💡', 'color': '#FFEAA7'},
    {'name': 'Health & Medical', 'icon': '🏥', 'color': '#DDA0DD'},
    {'name': 'Education', 'icon': '📚', 'color': '#74B9FF'},
    {'name': 'Travel', 'icon': '✈️', 'color': '#00B894'},
    {'name': 'Groceries', 'icon': '🛒', 'color': '#00CEC9'},
    {'name': 'Business', 'icon': '💼', 'color': '#636E72'},
    {'name': 'Investment', 'icon': '📈', 'color': '#FDCB6E'},
    {'name': 'Uncategorized', 'icon': '💰', 'color': '#B2BEC3'},
  ];
  
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
  static const int minPinLength = 4;
  static const int maxPinLength = 8;
  static const int maxTransactionAmount = 10000000; // 1 crore
}
