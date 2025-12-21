import 'dart:math';
import 'package:encrypt/encrypt.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _pinKey = 'expenditure_tracker_pin';
  static const String _biometricKey = 'expenditure_tracker_biometric';
  static const String _isFirstLaunchKey = 'expenditure_tracker_first_launch';

  late SharedPreferences _prefs;
  late Encrypter _encrypter;
  late IV _iv;

  // Initialize the service
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Initialize encryption
    const keyString = 'expenditure_tracker_secure_key_32_chars!';
    final key = Key.fromSecureRandom(32);
    _encrypter = Encrypter(AES(key));
    _iv = IV.fromSecureRandom(16);
  }

  // Check if it's the first launch
  bool get isFirstLaunch => _prefs.getBool(_isFirstLaunchKey) ?? true;

  // Set first launch flag
  Future<void> setFirstLaunchCompleted() async {
    await _prefs.setBool(_isFirstLaunchKey, false);
  }

  // Check if PIN is set
  bool get isPinSet => _prefs.containsKey(_pinKey);

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
    if (pin.length < 4 || pin.length > 8) {
      return false;
    }

    try {
      // Generate a hash of the PIN for security
      final encrypted = _encrypter.encrypt(pin, iv: _iv);
      await _prefs.setString(_pinKey, encrypted.base64);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Verify PIN
  Future<bool> verifyPin(String pin) async {
    if (!isPinSet || pin.isEmpty) {
      return false;
    }

    try {
      final String? encryptedPin = _prefs.getString(_pinKey);
      if (encryptedPin == null) {
        return false;
      }

      final decrypted = _encrypter.decrypt64(encryptedPin, iv: _iv);
      return pin == decrypted;
    } catch (e) {
      return false;
    }
  }

  // Change PIN
  Future<bool> changePin(String currentPin, String newPin) async {
    if (!await verifyPin(currentPin)) {
      return false;
    }

    if (newPin.length < 4 || newPin.length > 8) {
      return false;
    }

    return await setPin(newPin);
  }

  // Clear PIN
  Future<void> clearPin() async {
    await _prefs.remove(_pinKey);
  }

  // Clear all authentication data
  Future<void> clearAllAuthData() async {
    await _prefs.remove(_pinKey);
    await _prefs.remove(_biometricKey);
    await _prefs.remove(_isFirstLaunchKey);
  }

  // Generate secure PIN suggestion
  static String generateSecurePin() {
    final random = Random();
    String pin = '';
    for (int i = 0; i < 6; i++) {
      pin += random.nextInt(10).toString();
    }
    return pin;
  }

  // Validate PIN strength
  static bool validatePinStrength(String pin) {
    if (pin.length < 4 || pin.length > 8) {
      return false;
    }

    // Check if PIN contains only digits
    if (!RegExp(r'^[0-9]+$').hasMatch(pin)) {
      return false;
    }

    // Check for simple patterns (optional)
    // Avoid simple patterns like 1234, 0000, 1111, etc.
    if (pin == '1234' || pin == '0000' || pin == '1111' || 
        pin == '123456' || pin == '000000' || pin == '111111') {
      return false;
    }

    return true;
  }

  // Get authentication methods
  Future<Map<String, bool>> getAuthenticationMethods() async {
    return {
      'pin': isPinSet,
      'biometric': await isBiometricAvailable() && isBiometricEnabled,
    };
  }

  // Auto-login (attempt biometric first, then PIN)
  Future<bool> autoLogin() async {
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
    if (requirePin && isPinSet) {
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
    if (isPinSet) {
      return true;
    }

    return false;
  }
}
