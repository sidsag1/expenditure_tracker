import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import '../services/auth_service.dart';
import '../services/app_reset_service.dart';
import '../services/sms_service.dart';
import '../utils/app_logger.dart';
import '../utils/constants.dart';
import 'home_shell.dart';
import 'pin_setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  bool _biometricsEnabled = false;
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = _authService.isBiometricEnabled;
    setState(() {
      _biometricsEnabled = enabled;
    });
  }

  Future<void> _toggleBiometrics(bool value) async {
    if (value) {
      final isAvailable = await _authService.isBiometricAvailable();
      if (!isAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Biometrics not available on this device')),
          );
        }
        return;
      }
      
      final authenticated = await _authService.authenticateWithBiometric();
      if (!authenticated) {
        return;
      }
    }

    try {
      await _authService.setBiometricEnabled(value);
      setState(() {
        _biometricsEnabled = value;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to toggle biometrics')),
        );
      }
    }
  }

  Future<void> _triggerFullRescan() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Starting full inbox rescan...')),
      );
    }
    
    try {
      final saved = await SMSService().syncMessages(fullSync: true);
      if (mounted) {
        final homeShellState = context.findAncestorStateOfType<HomeShellState>();
        homeShellState?.clearCache();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rescan complete. Imported $saved new transactions.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rescan failed: $e')),
        );
      }
    }
  }

  void _showDeleteAllDataDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text(
          'Delete All Data',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will permanently erase all your accounts and transactions, '
          'and reset your PIN. This action cannot be undone. Are you sure '
          'you want to proceed?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteAllData();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllData() async {
    setState(() {
      _isResetting = true;
    });

    try {
      await AppResetService.resetAll();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App data cleared. Closing app.'),
            backgroundColor: Colors.orange,
          ),
        );
        // Every in-memory cache (DB connections, AuthService/SharedPreferences
        // state, other screens' loaded data) is now stale, so force a cold
        // restart rather than trying to reset live app state in place.
        await Future.delayed(const Duration(milliseconds: 800));
        SystemNavigator.pop();
      }
    } catch (e, st) {
      AppLogger.error('App reset failed', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error clearing data. Please restart the app manually.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResetting = false;
        });
      }
    }
  }

  void _navigateToPinSetup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PinSetupScreen(
          isFirstTime: false,
          onComplete: () {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PIN successfully updated')),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Security',
            style: TextStyle(
              color: Colors.blue,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Change PIN', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Update your ${AppConstants.pinLength}-digit access code', style: TextStyle(color: Colors.grey)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: _navigateToPinSetup,
          ),
          SwitchListTile(
            title: const Text('Biometric Authentication', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Use fingerprint/face to unlock', style: TextStyle(color: Colors.grey)),
            value: _biometricsEnabled,
            onChanged: _toggleBiometrics,
            activeThumbColor: Colors.blue[400],
          ),
          const Divider(color: Colors.white24, height: 32),
          const Text(
            'Data',
            style: TextStyle(
              color: Colors.blue,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Full SMS Rescan', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Re-read all bank SMS messages', style: TextStyle(color: Colors.grey)),
            trailing: const Icon(Icons.sync, color: Colors.grey),
            onTap: _triggerFullRescan,
          ),
          ListTile(
            title: const Text('Export Data', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Export transactions to CSV', style: TextStyle(color: Colors.grey)),
            trailing: const Icon(Icons.download, color: Colors.grey),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export coming soon')),
              );
            },
          ),
          ListTile(
            title: const Text('Delete All Data', style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text('Permanently erase all accounts and transactions', style: TextStyle(color: Colors.grey)),
            trailing: _isResetting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                  )
                : const Icon(Icons.delete_forever, color: Colors.redAccent),
            onTap: _isResetting ? null : _showDeleteAllDataDialog,
          ),
        ],
      ),
    );
  }
}
