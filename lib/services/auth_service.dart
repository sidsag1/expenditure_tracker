import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as legacy;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import '../utils/constants.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // The one shared handle for this app's secure storage. The Android plugin
  // resolves its backing store from the options of each individual call
  // (FlutterSecureStorage.ensureInitialized), and mixed option sets across
  // call sites are explicitly unsupported there — so every caller, including
  // AppResetService's deleteAll(), must go through this instance or risk
  // reading/clearing a different store than the one that was written.
  static const FlutterSecureStorage secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // v3: PBKDF2-HMAC-SHA256(pin, random salt) in Keystore-backed secure
  // storage, replacing the v2 scheme below (reversible AES with a key baked
  // into the app binary — recoverable from the APK plus a prefs dump).
  //
  // Iterations, salt and hash share ONE record so that setting or changing a
  // PIN is a single write. Split across three keys, a process kill between
  // them would leave a fresh salt paired with the previous hash — a PIN that
  // is "set" but that no input can ever verify, with a full data wipe as the
  // only way out.
  static const String _pinRecordKey = 'expenditure_tracker_pin_v3';

  static const String _failedAttemptsKey = 'expenditure_tracker_failed_attempts';
  static const String _lockedUntilKey = 'expenditure_tracker_locked_until';
  static const String _lockoutStageKey = 'expenditure_tracker_lockout_stage';

  static const int _pbkdf2Iterations = 100000;
  static const int _saltLengthBytes = 16;
  static const int _derivedKeyLengthBytes = 32;

  // v2 key, kept only so a still-installed v2 build can be migrated once.
  static const String _legacyPinKey = 'expenditure_tracker_pin_v2';

  static const String _biometricKey = 'expenditure_tracker_biometric';
  static const String _isFirstLaunchKey = 'expenditure_tracker_first_launch';

  late SharedPreferences _prefs;

  // Initialize the service
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _migrateLegacyPinIfNeeded();
  }

  // One-shot migration: decrypt a v2 (reversibly-encrypted) PIN and store it
  // under the v3 PBKDF2 scheme instead. Runs at most once per install; the
  // legacy key is removed whether migration succeeds or not so it is never
  // retried against a corrupt value.
  Future<void> _migrateLegacyPinIfNeeded() async {
    final legacyValue = _prefs.getString(_legacyPinKey);
    if (legacyValue == null) return;

    try {
      if (!await secureStorage.containsKey(key: _pinRecordKey)) {
        final key = legacy.Key.fromUtf8('expenditure_tracker_secure_key32');
        final iv = legacy.IV.fromUtf8('expenditure_iv16');
        final encrypter = legacy.Encrypter(legacy.AES(key));
        final decryptedPin = encrypter.decrypt64(legacyValue, iv: iv);

        // v2 accepted 4-8 digits; the v3 keypad can only ever submit exactly
        // AppConstants.pinLength (P1-7). Carrying a shorter or longer PIN
        // across would leave a PIN that is set but impossible to type, whose
        // only escape is "Forgot PIN?" — which wipes the user's accounts and
        // transactions. Drop it instead: isPinSet then reports false, the
        // splash routes to PIN setup, and the database is left untouched.
        if (validatePinStrength(decryptedPin)) {
          await _storePin(decryptedPin);
        } else {
          AppLogger.error(
            'Legacy PIN is not ${AppConstants.pinLength} digits; '
            'dropping it and requiring a new one at next launch.',
          );
        }
      }
    } catch (e, st) {
      AppLogger.error('Failed to migrate legacy PIN', e, st);
    } finally {
      await _prefs.remove(_legacyPinKey);
    }
  }

  // Check if it's the first launch
  bool get isFirstLaunch => _prefs.getBool(_isFirstLaunchKey) ?? true;

  // Set first launch flag
  Future<void> setFirstLaunchCompleted() async {
    await _prefs.setBool(_isFirstLaunchKey, false);
  }

  // Check if PIN is set
  Future<bool> get isPinSet async =>
      await secureStorage.containsKey(key: _pinRecordKey);

  // Check if biometric is enabled
  bool get isBiometricEnabled => _prefs.getBool(_biometricKey) ?? false;

  // Set biometric enabled status
  Future<void> setBiometricEnabled(bool enabled) async {
    await _prefs.setBool(_biometricKey, enabled);
  }

  // Check if biometric is available
  Future<bool> isBiometricAvailable() async {
    try {
      final LocalAuthentication auth = LocalAuthentication();
      return await auth.canCheckBiometrics || await auth.isDeviceSupported();
    } catch (e) {
      return false;
    }
  }

  // Check which biometrics are available
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      final LocalAuthentication auth = LocalAuthentication();
      return await auth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  // Authenticate with biometric
  Future<bool> authenticateWithBiometric() async {
    try {
      final LocalAuthentication auth = LocalAuthentication();
      final bool isAvailable = await auth.canCheckBiometrics || await auth.isDeviceSupported();

      if (!isAvailable) {
        return false;
      }

      return await auth.authenticate(
        localizedReason: 'Authenticate to access your expenditure tracker',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  // Set PIN
  Future<bool> setPin(String pin) async {
    if (!validatePinStrength(pin)) {
      return false;
    }

    try {
      await _storePin(pin);
      await _resetLockoutState();
      return true;
    } catch (e, st) {
      // A secure-storage failure here is invisible to the user otherwise:
      // PIN setup just reports "Failed to save PIN" forever.
      AppLogger.error('Failed to store PIN', e, st);
      return false;
    }
  }

  // Record layout: "<iterations>:<base64 salt>:<base64 hash>". Base64 never
  // contains ':', so a plain split is unambiguous.
  Future<void> _storePin(String pin) async {
    final salt = _generateSalt();
    final hash = await _deriveKey(pin, salt, _pbkdf2Iterations);
    await secureStorage.write(
      key: _pinRecordKey,
      value: '$_pbkdf2Iterations:${base64Encode(salt)}:${base64Encode(hash)}',
    );
  }

  Uint8List _generateSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(_saltLengthBytes, (_) => random.nextInt(256)),
    );
  }

  Future<Uint8List> _deriveKey(String pin, Uint8List salt, int iterations) {
    return compute(
      _pbkdf2Compute,
      _Pbkdf2Params(pin, salt, iterations, _derivedKeyLengthBytes),
    );
  }

  // Verify PIN. Refuses while locked out without consuming another attempt;
  // otherwise records success (clearing lockout state) or failure (which may
  // trigger a new lockout) before returning.
  Future<bool> verifyPin(String pin) async {
    if (!await isPinSet || pin.isEmpty) {
      return false;
    }

    if (await isLockedOut()) {
      return false;
    }
    await _clearExpiredLock();

    try {
      final record = await secureStorage.read(key: _pinRecordKey);
      if (record == null) {
        return false;
      }

      final parts = record.split(':');
      if (parts.length != 3) {
        AppLogger.error('Stored PIN record is malformed');
        return false;
      }
      final iterations = int.tryParse(parts[0]);
      if (iterations == null || iterations <= 0) {
        AppLogger.error('Stored PIN record has an invalid iteration count');
        return false;
      }
      final salt = base64Decode(parts[1]);
      final storedHash = base64Decode(parts[2]);

      final candidateHash = await _deriveKey(pin, salt, iterations);
      final isValid = _constantTimeEquals(candidateHash, storedHash);

      if (isValid) {
        await _resetLockoutState();
      } else {
        await _registerFailedAttempt();
      }
      return isValid;
    } catch (e, st) {
      // Fail closed, but don't let a storage fault masquerade as a wrong PIN
      // with no trace of why the user can't get in.
      AppLogger.error('PIN verification failed', e, st);
      return false;
    }
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  // --- Lockout state (persisted so it survives app/process restarts) ---

  // Attempts used in the current window, before a lockout is triggered.
  Future<int> getFailedAttempts() async {
    final raw = await secureStorage.read(key: _failedAttemptsKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  Future<int> getAttemptsRemaining() async {
    final used = await getFailedAttempts();
    return (AppConstants.maxAttempts - used).clamp(0, AppConstants.maxAttempts);
  }

  Future<DateTime?> getLockedUntil() async {
    final raw = await secureStorage.read(key: _lockedUntilKey);
    if (raw == null) return null;
    final millis = int.tryParse(raw);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<bool> isLockedOut() async {
    final lockedUntil = await getLockedUntil();
    if (lockedUntil == null) return false;
    return DateTime.now().isBefore(lockedUntil);
  }

  Future<Duration> getLockRemaining() async {
    final lockedUntil = await getLockedUntil();
    if (lockedUntil == null) return Duration.zero;
    final remaining = lockedUntil.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // Clears an expired lock (and resets the attempt counter for a fresh
  // window) without affecting an active one.
  Future<void> _clearExpiredLock() async {
    final lockedUntil = await getLockedUntil();
    if (lockedUntil == null) return;
    if (!DateTime.now().isBefore(lockedUntil)) {
      await secureStorage.delete(key: _lockedUntilKey);
      await secureStorage.write(key: _failedAttemptsKey, value: '0');
    }
  }

  Future<void> _registerFailedAttempt() async {
    final attempts = (await getFailedAttempts()) + 1;
    await secureStorage.write(
      key: _failedAttemptsKey,
      value: attempts.toString(),
    );

    if (attempts >= AppConstants.maxAttempts) {
      final stageRaw = await secureStorage.read(key: _lockoutStageKey);
      final stage = int.tryParse(stageRaw ?? '') ?? 0;
      final clampedStage =
          stage.clamp(0, AppConstants.lockoutBackoff.length - 1);
      final duration = AppConstants.lockoutBackoff[clampedStage];

      final lockedUntil = DateTime.now().add(duration);
      await secureStorage.write(
        key: _lockedUntilKey,
        value: lockedUntil.millisecondsSinceEpoch.toString(),
      );
      await secureStorage.write(
        key: _lockoutStageKey,
        value: (clampedStage + 1).clamp(0, AppConstants.lockoutBackoff.length - 1).toString(),
      );
      await secureStorage.write(key: _failedAttemptsKey, value: '0');
    }
  }

  Future<void> _resetLockoutState() async {
    await secureStorage.delete(key: _failedAttemptsKey);
    await secureStorage.delete(key: _lockedUntilKey);
    await secureStorage.delete(key: _lockoutStageKey);
  }

  // Change PIN
  Future<bool> changePin(String currentPin, String newPin) async {
    if (!await verifyPin(currentPin)) {
      return false;
    }

    if (!validatePinStrength(newPin)) {
      return false;
    }

    return await setPin(newPin);
  }

  // Clear PIN
  Future<void> clearPin() async {
    await secureStorage.delete(key: _pinRecordKey);
  }

  // Clear authentication state only: PIN, lockout counters, and the
  // biometric/first-launch flags. This is NOT the app-reset path — a full
  // wipe goes through AppResetService, which drops the database and clears
  // prefs and secure storage wholesale. Kept for a future change-auth /
  // sign-out flow in Settings (P5-3).
  Future<void> clearAllAuthData() async {
    await clearPin();
    await _resetLockoutState();
    await _prefs.remove(_biometricKey);
    await _prefs.remove(_isFirstLaunchKey);
  }

  // Generate secure PIN suggestion
  static String generateSecurePin() {
    final random = Random.secure();
    String pin = '';
    for (int i = 0; i < AppConstants.pinLength; i++) {
      pin += random.nextInt(10).toString();
    }
    return pin;
  }

  // Validate PIN: exactly AppConstants.pinLength digits.
  static bool validatePinStrength(String pin) {
    if (pin.length != AppConstants.pinLength) {
      return false;
    }

    return RegExp(r'^[0-9]+$').hasMatch(pin);
  }

  // Get authentication methods
  Future<Map<String, bool>> getAuthenticationMethods() async {
    return {
      'pin': await isPinSet,
      'biometric': await isBiometricAvailable() && isBiometricEnabled,
    };
  }

  // Auto-login (attempt biometric first, then PIN)
  Future<bool> autoLogin() async {
    // A PIN lockout has to gate every unlock path, not just verifyPin —
    // otherwise wiring up the biometric toggle (P5-3) would silently hand
    // back an escape hatch from the backoff.
    if (await isLockedOut()) {
      return false;
    }

    // Try biometric first if enabled and available
    if (isBiometricEnabled && await isBiometricAvailable()) {
      final biometricResult = await authenticateWithBiometric();
      if (biometricResult) {
        return true;
      }
    }

    // If biometric fails or not available, prompt for PIN
    return false;
  }

  // Force authentication (with UI prompts)
  Future<bool> authenticateUser({
    bool requirePin = true,
    bool requireBiometric = false,
  }) async {
    // If biometric is required and available
    if (requireBiometric && await isBiometricAvailable()) {
      final biometricResult = await authenticateWithBiometric();
      if (biometricResult) {
        return true;
      }
    }

    // If PIN is required and set
    if (requirePin && await isPinSet) {
      // Return true to indicate PIN entry should be prompted
      return true;
    }

    return false;
  }

  // Check if user should be authenticated
  Future<bool> shouldAuthenticate() async {
    // If it's first launch, no authentication required
    if (isFirstLaunch) {
      return false;
    }

    // If PIN is set, authentication is required
    if (await isPinSet) {
      return true;
    }

    return false;
  }
}

@immutable
class _Pbkdf2Params {
  final String pin;
  final Uint8List salt;
  final int iterations;
  final int keyLength;

  const _Pbkdf2Params(this.pin, this.salt, this.iterations, this.keyLength);
}

Uint8List _pbkdf2Compute(_Pbkdf2Params params) {
  return _pbkdf2(params.pin, params.salt, params.iterations, params.keyLength);
}

// PBKDF2-HMAC-SHA256, implemented directly against package:crypto since it
// has no built-in PBKDF2 helper.
Uint8List _pbkdf2(
  String password,
  List<int> salt,
  int iterations,
  int keyLengthBytes,
) {
  const hashLengthBytes = 32; // SHA-256 digest size
  final hmac = Hmac(sha256, utf8.encode(password));
  final blockCount = (keyLengthBytes / hashLengthBytes).ceil();
  final output = BytesBuilder();

  for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
    final blockSeed = Uint8List.fromList([
      ...salt,
      (blockIndex >> 24) & 0xff,
      (blockIndex >> 16) & 0xff,
      (blockIndex >> 8) & 0xff,
      blockIndex & 0xff,
    ]);

    var u = Uint8List.fromList(hmac.convert(blockSeed).bytes);
    final t = Uint8List.fromList(u);

    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var k = 0; k < t.length; k++) {
        t[k] ^= u[k];
      }
    }

    output.add(t);
  }

  return output.toBytes().sublist(0, keyLengthBytes);
}
