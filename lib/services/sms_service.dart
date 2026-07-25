import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction.dart';
import '../database/database_helper.dart';
import '../utils/constants.dart';
import 'sms_parser_service.dart';

// Top-level function to run in a background isolate
Future<List<Map<String, dynamic>?>> _parseSmsBatch(List<Map<String, dynamic>> messages) async {
  final parser = SMSParserService();
  final List<Map<String, dynamic>?> results = [];
  
  for (final message in messages) {
    final sender = (message['sender'] as String?) ?? '';
    final body = (message['body'] as String?) ?? '';
    if (body.isEmpty) continue;

    final epochMillis = (message['date'] as num?)?.toInt();
    final receivedAt = epochMillis != null && epochMillis > 0
        ? DateTime.fromMillisecondsSinceEpoch(epochMillis)
        : null;

    final transaction = await parser.parseSMS(body, sender, receivedAt: receivedAt);
    if (transaction != null) {
      final txnMap = transaction.toMap();
      txnMap['_sourceMessage'] = body; // Pass the source message back for DB link
      results.add(txnMap);
    }
  }
  return results;
}

class SMSService {
  static final SMSService _instance = SMSService._internal();
  factory SMSService() => _instance;
  SMSService._internal();

  static const String _lastSyncTimeKey = 'expenditure_tracker_last_sms_sync';

  // Native channels for reading the device SMS inbox (see MainActivity.kt)

  static const EventChannel _eventChannel =
      EventChannel('com.sbarpanda.expendituretracker/sms_stream');

  late SharedPreferences _prefs;
  bool _isSyncing = false;

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

  // Stream SMS messages from the device inbox using an EventChannel.
  Stream<List<Map<String, dynamic>>> getInboxMessageStream({int since = 0, List<String>? filterSenders}) {
    return _eventChannel.receiveBroadcastStream({
      'since': since,
      'filterSenders': filterSenders,
    }).map((dynamic event) {
      final list = event as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    });
  }

  // Stream bank SMS messages
  Stream<List<Map<String, dynamic>>> getBankSMSMessageStream({int since = 0}) {
    final allSenders = AppConstants.bankSenderNumbers.values.expand((l) => l).toList();
    return getInboxMessageStream(since: since, filterSenders: allSenders);
  }

  // Read the inbox, parse every bank message into a transaction, and save it.
  //
  // Concurrency: a second call while one is already running would race the
  // same SQLite rows (duplicate detection, balance updates) and double-count
  // `saved`, so a call that arrives while `_isSyncing` is true is a no-op.
  Future<int> syncMessages({bool fullSync = false}) async {
    if (_isSyncing) return 0;
    _isSyncing = true;
    try {
      if (!await isPermissionGranted()) {
        return 0;
      }

      final since = fullSync ? 0 : (_prefs.getInt(_lastSyncTimeKey) ?? 0);
      final parser = SMSParserService();

      int saved = 0;
      // The high-water mark actually persisted is the latest message epoch
      // seen this run, not "now" -- the native query above already started
      // (and can take many seconds to stream back and parse), so any SMS
      // that lands after it started but before this line would run has a
      // timestamp older than DateTime.now() and would be silently skipped by
      // every future sync if we recorded wall-clock time here instead.
      int maxMessageTime = since;

      await for (final batch in getBankSMSMessageStream(since: since)) {
        if (batch.isEmpty) continue;

        for (final message in batch) {
          final epochMillis = (message['date'] as num?)?.toInt();
          if (epochMillis != null && epochMillis > maxMessageTime) {
            maxMessageTime = epochMillis;
          }
        }

        // Parse the batch of SMS messages in a background isolate
        // We pass the raw maps and get back parsed Transaction objects (as maps to ensure serialization).
        final parsedTxnMaps = await compute(_parseSmsBatch, batch);

        // We must insert them into the database on the main isolate.
        // We wrap the loop in a single SQLite transaction for batch performance.
        final db = await DatabaseHelper().database;
        await db.transaction((txn) async {
          // Fetched once per batch rather than once per message -- a batch
          // of hundreds of SMSes would otherwise hit SQLite for the active
          // accounts list on every single saveTransaction call.
          final activeAccounts = await parser.loadActiveAccounts(txn: txn);

          for (final txnMap in parsedTxnMaps) {
            if (txnMap == null) continue;

            final transaction = Transaction.fromMap(txnMap);
            final sourceMessage = txnMap['_sourceMessage'] as String?; // passed along from isolate

            if (await parser.saveTransaction(transaction,
                sourceMessage: sourceMessage,
                txn: txn,
                activeAccounts: activeAccounts)) {
              saved++;
            }
          }
        });
      }

      if (maxMessageTime > 0) {
        await _prefs.setInt(_lastSyncTimeKey, maxMessageTime);
      }
      return saved;
    } finally {
      _isSyncing = false;
    }
  }

  // Get last sync time
  DateTime? getLastSyncTime() {
    final timestamp = _prefs.getInt(_lastSyncTimeKey);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }



  String? getBankNameFromSender(String sender) {
    final upperSender = sender.toUpperCase().trim();
    
    for (final entry in AppConstants.bankSenderNumbers.entries) {
      for (final number in entry.value) {
        if (upperSender.contains(number.toUpperCase())) {
          return entry.key;
        }
      }
    }
    
    return null;
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
    return AppConstants.bankSenderNumbers.keys.toList();
  }

  // Check if a specific bank is supported
  bool isBankSupported(String bankName) {
    return AppConstants.bankSenderNumbers.containsKey(bankName);
  }

  // Get sender numbers for a specific bank
  List<String> getSenderNumbersForBank(String bankName) {
    return AppConstants.bankSenderNumbers[bankName] ?? [];
  }

  // Clear all sync data (for testing)
  Future<void> clearSyncData() async {
    await _prefs.remove(_lastSyncTimeKey);
  }
}
