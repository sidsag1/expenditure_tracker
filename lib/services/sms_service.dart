import 'dart:async';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sms_parser_service.dart';

class SMSService {
  static final SMSService _instance = SMSService._internal();
  factory SMSService() => _instance;
  SMSService._internal();

  static const String _lastSyncTimeKey = 'expenditure_tracker_last_sms_sync';

  // Native channel for reading the device SMS inbox (see MainActivity.kt)
  static const MethodChannel _channel =
      MethodChannel('com.example.expenditure_tracker/sms');

  late SharedPreferences _prefs;

  // Brand substrings matched against SMS sender IDs. Senders vary by
  // telecom route and service (e.g. AD-ICICIB-S, VM-ICICIT, JD-HDFCBK-S),
  // so match on the brand fragment rather than exact sender IDs.
  static const Map<String, List<String>> _bankSenderNumbers = {
    'ICICI': ['ICICI'],
    'Kotak': ['KOTAK'],
    'SBI': ['SBI'],
    'HDFC': ['HDFC'],
    'Axis Bank': ['AXIS'],
    'Bank of Baroda': ['BOB'],
    'Punjab National Bank': ['PNB'],
    'Canara Bank': ['CNRB', 'CANBK'],
    'IDBI Bank': ['IDBI'],
    'Yes Bank': ['YESB'],
    'IndusInd Bank': ['INDB'],
    'Federal Bank': ['FEDB'],
    'RBL Bank': ['RBLB'],
    'South Indian Bank': ['SOUTHB'],
    'Amazon Pay': ['AMZPAY', 'AMAZON'],
    'Google Pay': ['GPAY', 'GOOGPAY'],
    'PhonePe': ['PHONEPE', 'PPLTFIP'],
    'Paytm': ['PYTM', 'PTYM'],
    'Blinkit': ['BLNKIT', 'BLINKIT'],
    'Zepto': ['ZEPTO'],
    'MobiKwik': ['MOBIKWIK', 'MBKWIK'],
    'Freecharge': ['FREECHARGE', 'FRECHG'],
  };

  // Initialize the service
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // Check if SMS permission is granted
  Future<bool> isPermissionGranted() async {
    final status = await Permission.sms.status;
    return status.isGranted;
  }

  // Request SMS permission
  Future<PermissionStatus> requestPermission() async {
    final status = await Permission.sms.request();
    return status;
  }

  // Check if we should show permission rationale
  Future<bool> shouldShowPermissionRationale() async {
    final status = await Permission.sms.status;
    return status.isDenied;
  }

  // Query the device SMS inbox via the native platform channel.
  // Returns every inbox message newer than [since] (epoch millis; 0 = all).
  Future<List<Map<String, dynamic>>> getInboxMessages({int since = 0}) async {
    if (!await isPermissionGranted()) {
      throw Exception('SMS permission not granted');
    }

    try {
      final raw = await _channel
          .invokeMethod<List<dynamic>>('getInboxSms', {'since': since});
      return (raw ?? const [])
          .map((m) => Map<String, dynamic>.from(m as Map))
          .toList();
    } on PlatformException catch (e) {
      throw Exception('Failed to read SMS messages: ${e.message}');
    }
  }

  // Get all SMS messages from known bank/wallet senders
  Future<List<Map<String, dynamic>>> getBankSMSMessages({int since = 0}) async {
    final allMessages = await getInboxMessages(since: since);
    return allMessages
        .where((m) =>
            getBankNameFromSender((m['sender'] as String?) ?? '') != null)
        .toList();
  }

  // Get bank SMS messages received since the last sync
  Future<List<Map<String, dynamic>>> getNewSMSMessages() async {
    final lastSyncTime = _prefs.getInt(_lastSyncTimeKey) ?? 0;
    return getBankSMSMessages(since: lastSyncTime);
  }

  // Read the inbox, parse every bank message into a transaction, and save it.
  // The whole inbox is processed on every sync so that messages for an
  // account the user registered later are still picked up; duplicates are
  // skipped via a deterministic per-message transaction ID, and only
  // messages matching a registered account are saved.
  // Returns the number of newly saved transactions.
  Future<int> syncMessages({bool fullSync = false}) async {
    if (!await isPermissionGranted()) {
      return 0;
    }

    // Older builds saved promotional messages, wrong dates, and transactions
    // that were never matched to a registered account. Cleaning those up
    // used to be a SharedPreferences-gated one-time hack that ran here on
    // every sync; it's now a one-time DELETE in the schema v5 migration
    // (DatabaseHelper._upgradeDatabase) instead, since a migration is
    // inherently one-shot per install. The full-inbox rescan below re-imports
    // anything real through the current parser regardless.
    final messages = await getBankSMSMessages();
    final parser = SMSParserService();

    int saved = 0;
    for (final message in messages) {
      final sender = (message['sender'] as String?) ?? '';
      final body = (message['body'] as String?) ?? '';
      if (body.isEmpty) continue;

      // When the body has no date (typical for wallet SMSes), the parser
      // falls back to when the SMS was received.
      final epochMillis = (message['date'] as num?)?.toInt();
      final receivedAt = epochMillis != null && epochMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(epochMillis)
          : null;

      final transaction =
          await parser.parseSMS(body, sender, receivedAt: receivedAt);
      if (transaction != null &&
          await parser.saveTransaction(transaction, sourceMessage: body)) {
        saved++;
      }
    }

    await updateLastSyncTime();
    return saved;
  }

  // Update last sync time
  Future<void> updateLastSyncTime() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setInt(_lastSyncTimeKey, now);
  }

  // Get sender bank name
  String? getBankNameFromSender(String sender) {
    final upperSender = sender.toUpperCase().trim();
    
    for (final entry in _bankSenderNumbers.entries) {
      for (final number in entry.value) {
        if (upperSender.contains(number.toUpperCase())) {
          return entry.key;
        }
      }
    }
    
    return null;
  }

  // Stream for real-time SMS messages (stub implementation)
  Stream<Map<String, dynamic>>? get smsStream {
    // Mock implementation - in real app would provide actual SMS stream
    return null;
  }

  // Set up SMS listener (stub implementation)
  void listenToNewSMS(Function(Map<String, dynamic>) onNewMessage) {
    // Mock implementation - in real app would set up SMS listener
  }

  // Stop listening to SMS
  void stopListening() {
    // Mock implementation - in real app would stop SMS listener
  }

  // Get permission status
  Future<PermissionStatus> getPermissionStatus() async {
    return await Permission.sms.status;
  }

  // Open app settings
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  // Get supported banks
  List<String> getSupportedBanks() {
    return _bankSenderNumbers.keys.toList();
  }

  // Check if a specific bank is supported
  bool isBankSupported(String bankName) {
    return _bankSenderNumbers.containsKey(bankName);
  }

  // Get sender numbers for a specific bank
  List<String> getSenderNumbersForBank(String bankName) {
    return _bankSenderNumbers[bankName] ?? [];
  }

  // Test method to simulate SMS parsing (for development)
  List<String> getTestSMSMessages() {
    return [
      'ICICI Bank Account XX340 credited:Rs. 2,45,687.00 on 30-Sep-25. Info NEFT-HSBCN52025093079143616-. Available Balance is Rs. 2,97,158.22.',
      'ICICI Bank Acct XX340 debited for Rs 50.00 on 11-Oct-25; VENDIMAN credited. UPI:528407948322. Call 18002662 for dispute. SMS BLOCK 340 to 9215676766.',
      'INR 630.00 spent using ICICI Bank Card XX4016 on 19-Oct-25 on INDIGO AIRLINE. Avl Limit: INR 1,45,739.72. If not you, call 1800 2662/SMS BLOCK 4016 to 9215676766.',
      'Payment of Rs 70,000.00 has been received on your ICICI Bank Credit Card XX4016 through Bharat Bill Payment System on 09-DEC-25.',
      'Rs.2000.00 spent via Kotak Debit Card XX7297 at PYU*SAFRESH TECHNOLOGY PR on 10/12/2025. Avl bal Rs.247.77 Not you?Tap https://kotak.com/KBANKT/Fraud',
      'Sent Rs.100.00 from Kotak Bank AC X2285 to q999676030@ybl on 18-12-25.UPI Ref 535215638117. Not you, https://kotak.com/KBANKT/Fraud',
      'Received Rs. 10000.00 on 01-12-25 in your Kotak Bank A/C x2285 by an A/C linked to mobile x522. IMPS Ref no 533523524027.',
      'IMPS from Ac X5706 for Rs.10,000.00 with Ref 533523524027 dt 01.12.25 to Siddha Ac X2285 with KKBK0008336 sent from YONO. If not done by you fwd this SMS to 7400165218 or call 1800111109 - SBI.',
      'Dear UPI user A/C X5706 debited by 1748.0 on date 09Dec25 trf to CRED Club Refno 534352440391 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear Customer, Your a/c no. XXXXXXXX5706 is credited by Rs.100000.00 on 09-12-25 by a/c linked to mobile 8XXXXXX522-SIDDHARTH SAGAR BAR (IMPS Ref no 534320026033).If not done by you, call 1800111109. -SBI',
    ];
  }

  // Clear all sync data (for testing)
  Future<void> clearSyncData() async {
    await _prefs.remove(_lastSyncTimeKey);
  }
}
