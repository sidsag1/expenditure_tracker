import 'dart:async';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms/sms.dart';

class SMSService {
  static final SMSService _instance = SMSService._internal();
  factory SMSService() => _instance;
  SMSService._internal();

  static const String _lastSyncTimeKey = 'expenditure_tracker_last_sms_sync';
  
  late SharedPreferences _prefs;
  late SmsReceiver _smsReceiver;
  late SmsSender _smsSender;

  // Bank SMS sender numbers
  static const Map<String, List<String>> _bankSenderNumbers = {
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

  // Initialize the service
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _smsReceiver = SmsReceiver();
    _smsSender = SmsSender();
  }

  // Check if SMS permission is granted
  Future<bool> isPermissionGranted() async {
    final status = await Permission.sms.status;
    return status == PermissionStatus.granted;
  }

  // Request SMS permission
  Future<PermissionStatus> requestPermission() async {
    final status = await Permission.sms.request();
    return status;
  }

  // Check if we should show permission rationale
  bool shouldShowPermissionRationale() {
    return Permission.sms.status == PermissionStatus.denied;
  }

  // Get all SMS messages from bank numbers
  Future<List<SmsMessage>> getBankSMSMessages() async {
    if (!await isPermissionGranted()) {
      throw Exception('SMS permission not granted');
    }

    try {
      final senderNumbers = _getAllBankSenderNumbers();
      final messages = await _smsReceiver.querySms(
        kind: SmsQueryKind.Inbox,
        address: senderNumbers,
      );

      return messages.where((message) => _isBankMessage(message)).toList();
    } catch (e) {
      throw Exception('Failed to read SMS messages: $e');
    }
  }

  // Get SMS messages since last sync
  Future<List<SmsMessage>> getNewSMSMessages() async {
    final lastSyncTime = _prefs.getInt(_lastSyncTimeKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    if (!await isPermissionGranted()) {
      throw Exception('SMS permission not granted');
    }

    try {
      final senderNumbers = _getAllBankSenderNumbers();
      final messages = await _smsReceiver.querySms(
        kind: SmsQueryKind.Inbox,
        address: senderNumbers,
        startDate: DateTime.fromMillisecondsSinceEpoch(lastSyncTime),
      );

      return messages.where((message) => 
        message.date!.millisecondsSinceEpoch > lastSyncTime && 
        _isBankMessage(message)
      ).toList();
    } catch (e) {
      throw Exception('Failed to read new SMS messages: $e');
    }
  }

  // Update last sync time
  Future<void> updateLastSyncTime() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setInt(_lastSyncTimeKey, now);
  }

  // Check if message is from a bank
  bool _isBankMessage(SmsMessage message) {
    if (message.sender == null) return false;
    
    final sender = message.sender!.toUpperCase().trim();
    
    for (final bankNumbers in _bankSenderNumbers.values) {
      for (final number in bankNumbers) {
        if (sender.contains(number.toUpperCase())) {
          return true;
        }
      }
    }
    
    return false;
  }

  // Get all bank sender numbers
  List<String> _getAllBankSenderNumbers() {
    final List<String> allNumbers = [];
    for (final numbers in _bankSenderNumbers.values) {
      allNumbers.addAll(numbers);
    }
    return allNumbers;
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

  // Stream for real-time SMS messages
  Stream<SmsMessage>? get smsStream {
    if (!Platform.isAndroid) return null;
    
    try {
      return _smsReceiver.onSmsReceived;
    } catch (e) {
      return null;
    }
  }

  // Set up SMS listener
  void listenToNewSMS(Function(SmsMessage) onNewMessage) {
    if (!Platform.isAndroid) return;
    
    _smsReceiver.onSmsReceived.listen((SmsMessage message) {
      if (_isBankMessage(message)) {
        onNewMessage(message);
      }
    });
  }

  // Stop listening to SMS
  void stopListening() {
    // SMS receiver doesn't have explicit stop method, but we can dispose
    // In a real implementation, you might want to store the stream subscription
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
