import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import '../services/auth_service.dart';
import '../services/app_reset_service.dart';
import '../utils/app_logger.dart';
import '../utils/constants.dart';

class PinEntryScreen extends StatefulWidget {
  final VoidCallback? onSuccess;
  final VoidCallback? onCancel;
  final String? title;
  final String? subtitle;

  const PinEntryScreen({
    super.key,
    this.onSuccess,
    this.onCancel,
    this.title,
    this.subtitle,
  });

  @override
  State<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends State<PinEntryScreen> {
  final AuthService _authService = AuthService();

  String _enteredPin = '';
  bool _isLoading = false;
  bool _isResetting = false;
  String _errorMessage = '';
  int _attemptsRemaining = AppConstants.maxAttempts;
  Duration _lockRemaining = Duration.zero;
  Timer? _lockTimer;

  bool get _isLocked => _lockRemaining > Duration.zero;

  @override
  void initState() {
    super.initState();
    _refreshLockState();
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshLockState() async {
    final remaining = await _authService.getLockRemaining();
    final attemptsRemaining = await _authService.getAttemptsRemaining();
    if (!mounted) return;
    setState(() {
      _lockRemaining = remaining;
      _attemptsRemaining = attemptsRemaining;
    });

    _lockTimer?.cancel();
    if (remaining > Duration.zero) {
      _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickLock());
    }
  }

  Future<void> _tickLock() async {
    final remaining = await _authService.getLockRemaining();
    if (!mounted) return;

    if (remaining <= Duration.zero) {
      _lockTimer?.cancel();
      final attemptsRemaining = await _authService.getAttemptsRemaining();
      if (!mounted) return;
      setState(() {
        _lockRemaining = Duration.zero;
        _attemptsRemaining = attemptsRemaining;
        _errorMessage = '';
      });
    } else {
      setState(() {
        _lockRemaining = remaining;
      });
    }
  }

  String _formatLockRemaining(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    if (minutes > 0) {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              // Header
              Icon(
                Icons.lock,
                size: 48,
                color: _errorMessage.isNotEmpty || _isLocked
                    ? Colors.red[400]
                    : Colors.blue[400],
              ),
              const SizedBox(height: 12),
              Text(
                widget.title ?? 'Enter Security PIN',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.subtitle ?? 'Enter your PIN to access your financial data',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // PIN Display
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(AppConstants.pinLength, (index) {
                  final isFilled = index < _enteredPin.length;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                        ? (_errorMessage.isNotEmpty ? Colors.red[400] : Colors.blue[400])
                        : Colors.grey[700],
                      border: Border.all(
                        color: Colors.grey[600]!,
                        width: 1,
                      ),
                    ),
                  );
                }),
              ),

              const SizedBox(height: 12),

              // Lockout countdown
              if (_isLocked)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Locked. Try again in ${_formatLockRemaining(_lockRemaining)}',
                    style: TextStyle(
                      color: Colors.red[400],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              // Attempts left
              else if (_attemptsRemaining < AppConstants.maxAttempts)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _attemptsRemaining <= 2 ? Colors.red.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _attemptsRemaining <= 2 ? Colors.red.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$_attemptsRemaining attempts remaining',
                    style: TextStyle(
                      color: _attemptsRemaining <= 2 ? Colors.red[400] : Colors.orange[400],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              // Error message
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red[400], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage,
                          style: TextStyle(color: Colors.red[400]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Keypad: sized to the remaining space so all keys are always
              // visible without scrolling, but capped so keys stay a
              // comfortable size on tall screens.
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 300, maxHeight: 400),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const spacing = 12.0;
                        final buttonWidth =
                            (constraints.maxWidth - 2 * spacing) / 3;
                        final buttonHeight =
                            (constraints.maxHeight - 3 * spacing) / 4;
                        final aspectRatio = buttonHeight > 0
                            ? buttonWidth / buttonHeight
                            : 1.0;

                        return GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: aspectRatio,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                          ),
                          itemCount: 12,
                          itemBuilder: (context, index) {
                            if (index == 9) {
                              return _buildKeypadButton(
                                icon: Icons.backspace,
                                onTap: _onBackspace,
                              );
                            } else if (index == 10) {
                              return _buildKeypadButton(
                                text: '0',
                                onTap: () => _onNumberPress('0'),
                              );
                            } else if (index == 11) {
                              return _buildKeypadButton(
                                icon: Icons.check,
                                onTap: _onSubmit,
                              );
                            } else {
                              final number = (index + 1).toString();
                              return _buildKeypadButton(
                                text: number,
                                onTap: () => _onNumberPress(number),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Forgot PIN — always available, but resetting still requires
              // an explicit confirmation dialog; it is not a bare-tap escape
              // from a lockout.
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: TextButton(
                  onPressed: _isResetting ? null : _showResetPinDialog,
                  child: Text(
                    'Forgot PIN?',
                    style: TextStyle(color: Colors.blue[400]),
                  ),
                ),
              ),

              // Cancel button
              if (widget.onCancel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton.icon(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.cancel, color: Colors.grey),
                    label: Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadButton({
    String? text,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    final disabled = _isLoading || _isLocked || _isResetting;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: disabled ? Colors.grey[850] : Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[700]!),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: text != null
                ? Text(
                    text,
                    style: TextStyle(
                      color: disabled ? Colors.grey[600] : Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Icon(
                    icon,
                    color: disabled ? Colors.grey[600] : Colors.blue[400],
                    size: 28,
                  ),
          ),
        ),
      ),
    );
  }

  void _onNumberPress(String number) {
    if (_isLoading || _isLocked || _enteredPin.length >= AppConstants.pinLength) return;

    setState(() {
      _errorMessage = '';
    });

    setState(() {
      _enteredPin += number;
    });

    // Auto-verify when PIN is complete
    if (_enteredPin.length == AppConstants.pinLength) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _onSubmit();
      });
    }
  }

  void _onBackspace() {
    if (_isLoading || _isLocked || _enteredPin.isEmpty) return;

    setState(() {
      _errorMessage = '';
    });

    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  Future<void> _onSubmit() async {
    if (_isLoading || _isLocked || _enteredPin.length < AppConstants.pinLength) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final isValid = await _authService.verifyPin(_enteredPin);

      if (isValid) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Access granted!'),
              backgroundColor: Colors.green,
            ),
          );

          widget.onSuccess?.call();
        }
      } else {
        final locked = await _authService.isLockedOut();
        final attemptsRemaining = await _authService.getAttemptsRemaining();

        if (!mounted) return;
        setState(() {
          _enteredPin = '';
          _attemptsRemaining = attemptsRemaining;
          _errorMessage = locked
              ? 'Too many attempts. Try again later.'
              : 'Invalid PIN. Please try again.';
        });

        if (locked) {
          await _refreshLockState();
        }
      }
    } catch (e, st) {
      // verifyPin now runs PBKDF2 (~100k iterations off-isolate), so the
      // window in which this screen can be disposed mid-verify is real.
      AppLogger.error('PIN entry failed', e, st);
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Authentication error. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showResetPinDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text(
          'Reset PIN',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will clear all your data including accounts and transactions. '
          'Are you sure you want to proceed?',
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
              _clearAllData();
            },
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllData() async {
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
}
