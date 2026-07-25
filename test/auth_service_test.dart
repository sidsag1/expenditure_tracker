// Tests for AuthService's PBKDF2 PIN storage (P1-1), persisted lockout
// backoff (P1-2), and the one-shot v2 -> v3 migration.

import 'package:encrypt/encrypt.dart' as legacy;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:expenditure_tracker/services/auth_service.dart';
import 'package:expenditure_tracker/utils/constants.dart';

import 'support/secure_storage_test_helper.dart';

// Matches AuthService's private legacy key; duplicated here deliberately so
// the migration test exercises the real on-disk key name, not a stand-in.
const _legacyPinKey = 'expenditure_tracker_pin_v2';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    setupMockSecureStorage();
  });

  tearDown(tearDownMockSecureStorage);

  Future<AuthService> freshAuthService() async {
    final service = AuthService();
    await service.init();
    return service;
  }

  group('PIN hashing', () {
    test('correct PIN verifies', () async {
      final auth = await freshAuthService();
      expect(await auth.setPin('123456'), isTrue);
      expect(await auth.verifyPin('123456'), isTrue);
    });

    test('wrong PIN fails', () async {
      final auth = await freshAuthService();
      await auth.setPin('123456');
      expect(await auth.verifyPin('654321'), isFalse);
    });

    test('stored blob contains neither the PIN nor a fixed prefix across '
        'two setups of the same PIN', () async {
      final auth = await freshAuthService();

      await auth.setPin('112233');
      final first = await _readPinRecord();

      // Re-run setup with the same PIN (as if the user reset it to the same
      // value) and compare the stored blobs.
      await auth.setPin('112233');
      final second = await _readPinRecord();

      // Random salt per setup means the stored bytes differ even though the
      // PIN is identical (this was the whole bug with the fixed-IV v2 AES
      // scheme: identical PINs produced identical ciphertext).
      expect(first.salt, isNot(equals(second.salt)));
      expect(first.hash, isNot(equals(second.hash)));

      for (final blob in [first.salt, first.hash, second.salt, second.hash]) {
        expect(blob.contains('112233'), isFalse);
      }
    });

    test('the PIN is stored as one atomic record, not several keys', () async {
      // A PIN change writes salt+hash together; three separate writes could
      // be torn by a process kill and leave a new salt with an old hash,
      // which no PIN input could ever verify again.
      final auth = await freshAuthService();
      await auth.setPin('123456');

      final pinKeys = (await _dumpSecureStorage())
          .keys
          .where((k) => k.contains('pin'))
          .toList();
      expect(pinKeys, ['expenditure_tracker_pin_v3']);
    });

    test('rejects a PIN of the wrong length', () async {
      final auth = await freshAuthService();
      expect(await auth.setPin('123'), isFalse);
      expect(await auth.setPin('1234567'), isFalse);
      expect(AuthService.validatePinStrength('1' * AppConstants.pinLength), isTrue);
    });
  });

  group('v2 -> v3 migration', () {
    // Reproduces exactly what the old AuthService.setPin wrote: AES with a
    // key baked into the binary and a fixed IV, base64, in SharedPreferences.
    Future<SharedPreferences> seedLegacyPin(String pin) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final key = legacy.Key.fromUtf8('expenditure_tracker_secure_key32');
      final iv = legacy.IV.fromUtf8('expenditure_iv16');
      final encrypter = legacy.Encrypter(legacy.AES(key));
      await prefs.setString(_legacyPinKey, encrypter.encrypt(pin, iv: iv).base64);
      return prefs;
    }

    test('a stored v2 PIN is decrypted, rehashed, and the legacy key removed',
        () async {
      final prefs = await seedLegacyPin('998877');

      final auth = AuthService();
      await auth.init();

      expect(await auth.isPinSet, isTrue);
      expect(await auth.verifyPin('998877'), isTrue);
      expect(prefs.containsKey(_legacyPinKey), isFalse);
    });

    test('a v2 PIN of the wrong length is dropped, not carried over',
        () async {
      // v2 accepted 4-8 digits. Migrating a 4-digit PIN forward would leave a
      // PIN that isPinSet reports as set but that the 6-digit keypad can
      // never submit — locking the user out of their own data with "Forgot
      // PIN?" (a full wipe) as the only escape.
      final prefs = await seedLegacyPin('1234');

      final auth = AuthService();
      await auth.init();

      expect(await auth.isPinSet, isFalse,
          reason: 'an unenterable PIN must not survive migration');
      expect(prefs.containsKey(_legacyPinKey), isFalse);

      // The user is sent to PIN setup and can set a valid one; their database
      // is untouched by any of this.
      expect(await auth.setPin('123456'), isTrue);
      expect(await auth.verifyPin('123456'), isTrue);
    });
  });

  group('lockout', () {
    test('locks out after maxAttempts consecutive failures', () async {
      final auth = await freshAuthService();
      await auth.setPin('123456');

      for (var i = 0; i < AppConstants.maxAttempts; i++) {
        await auth.verifyPin('000000');
      }

      expect(await auth.isLockedOut(), isTrue);
      // The correct PIN is refused while locked, and doesn't consume/clear
      // the lock either.
      expect(await auth.verifyPin('123456'), isFalse);
      expect(await auth.isLockedOut(), isTrue);
    });

    test('lockout state survives a service restart', () async {
      final auth = await freshAuthService();
      await auth.setPin('123456');
      for (var i = 0; i < AppConstants.maxAttempts; i++) {
        await auth.verifyPin('000000');
      }
      expect(await auth.isLockedOut(), isTrue);

      // "Restart": re-run init() against the same (mocked) secure storage
      // backing store, as a fresh process would.
      final restarted = AuthService();
      await restarted.init();

      expect(await restarted.isLockedOut(), isTrue);
      expect(await restarted.getLockRemaining(), greaterThan(Duration.zero));
    });

    test('a successful verify resets the failed-attempt counter', () async {
      final auth = await freshAuthService();
      await auth.setPin('123456');

      await auth.verifyPin('000000');
      await auth.verifyPin('000000');
      expect(await auth.getAttemptsRemaining(), AppConstants.maxAttempts - 2);

      expect(await auth.verifyPin('123456'), isTrue);
      expect(await auth.getAttemptsRemaining(), AppConstants.maxAttempts);
    });
  });
}

// Reads straight from the (mocked) secure storage channel that AuthService
// itself writes to, rather than adding a test-only accessor to AuthService.
Future<Map<String, String>> _dumpSecureStorage() {
  return AuthService.secureStorage.readAll();
}

class _PinRecord {
  const _PinRecord(this.iterations, this.salt, this.hash);

  final String iterations;
  final String salt;
  final String hash;
}

// Parses the on-disk record layout: "<iterations>:<base64 salt>:<base64 hash>".
Future<_PinRecord> _readPinRecord() async {
  final raw = (await _dumpSecureStorage())['expenditure_tracker_pin_v3'];
  expect(raw, isNotNull, reason: 'no PIN record was stored');
  final parts = raw!.split(':');
  expect(parts, hasLength(3));
  return _PinRecord(parts[0], parts[1], parts[2]);
}
