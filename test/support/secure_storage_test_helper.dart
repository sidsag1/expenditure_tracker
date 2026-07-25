// In-memory fake for the flutter_secure_storage platform channel.
//
// flutter_secure_storage has no on-device implementation available under
// `flutter test` (no Keystore/Keychain), so AuthService would hang/throw
// on every read/write without a channel handler. This mocks the same
// MethodChannel the plugin's MethodChannelFlutterSecureStorage talks to
// (see flutter_secure_storage_platform_interface's
// method_channel_flutter_secure_storage.dart) with a plain in-memory map,
// mirroring how SharedPreferences.setMockInitialValues works for prefs.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Map<String, String> _store = {};

void setupMockSecureStorage() {
  _store = {};
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    switch (call.method) {
      case 'containsKey':
        return _store.containsKey(call.arguments['key'] as String);
      case 'read':
        return _store[call.arguments['key'] as String];
      case 'write':
        _store[call.arguments['key'] as String] =
            call.arguments['value'] as String;
        return null;
      case 'delete':
        _store.remove(call.arguments['key'] as String);
        return null;
      case 'deleteAll':
        _store.clear();
        return null;
      case 'readAll':
        return Map<String, String>.from(_store);
      default:
        return null;
    }
  });
}

void tearDownMockSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
  _store = {};
}
