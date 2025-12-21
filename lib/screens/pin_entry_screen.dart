import 'package:flutter/material.dart';
import '../services/auth_service.dart';

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
  String _errorMessage = '';
  int _attemptsLeft = 5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              
              // Header
              Column(
                children: [
                  Icon(
                    Icons.lock,
                    size: 80,
                    color: _errorMessage.isNotEmpty ? Colors.red[400] : Colors.blue[400],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.title ?? 'Enter Security PIN',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.subtitle ?? 'Enter your PIN to access your financial data',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              
              const SizedBox(height: 48),
              
              // PIN Display
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (index) {
                  final isFilled = index < _enteredPin.length;
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 20,
                    height: 20,
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
              
              const SizedBox(height: 16),
              
              // Attempts left
              if (_attemptsLeft < 5)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _attemptsLeft <= 2 ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _attemptsLeft <= 2 ? Colors.red.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    '$_attemptsLeft attempts remaining',
                    style: TextStyle(
                      color: _attemptsLeft <= 2 ? Colors.red[400] : Colors.orange[400],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              
              const SizedBox(height: 24),
              
              // Error message
              if (_errorMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
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
              
              const SizedBox(height: 24),
              
              // Keypad
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
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
                ),
              ),
              
              // Cancel button
              if (widget.onCancel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[700]!),
        ),
        child: Center(
          child: text != null
              ? Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Icon(
                  icon,
                  color: Colors.blue[400],
                  size: 28,
                ),
        ),
      ),
    );
  }

  void _onNumberPress(String number) {
    if (_isLoading || _enteredPin.length >= 6) return;
    
    setState(() {
      _errorMessage = '';
    });
    
    setState(() {
      _enteredPin += number;
    });
    
    // Auto-verify when PIN is complete
    if (_enteredPin.length == 6) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _onSubmit();
      });
    }
  }

  void _onBackspace() {
    if (_isLoading || _enteredPin.isEmpty) return;
    
    setState(() {
      _errorMessage = '';
    });
    
    setState(() {
      _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
    });
  }

  Future<void> _onSubmit() async {
    if (_isLoading || _enteredPin.length < 4) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    
    try {
      final isValid = await _authService.verifyPin(_enteredPin);
      
      if (isValid) {
        // Reset attempts on successful login
        _attemptsLeft = 5;
        
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
        // Increment failed attempts
        setState(() {
          _attemptsLeft--;
          _errorMessage = 'Invalid PIN. Please try again.';
          _enteredPin = '';
        });
        
        if (_attemptsLeft <= 0) {
          // Too many failed attempts - lock the app
          _handleTooManyAttempts();
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Authentication error. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handleTooManyAttempts() {
    // Show lockout dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text(
          'Too Many Attempts',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'You have exceeded the maximum number of PIN attempts. '
          'For security reasons, you need to reset your PIN.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _showResetPinDialog();
            },
            child: Text(
              'Reset PIN',
              style: TextStyle(color: Colors.red[400]),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Clear all data and restart
              _clearAllData();
            },
            child: const Text(
              'Clear Data',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
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
    try {
      await _authService.clearAllAuthData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('App data cleared. Please restart the app.'),
            backgroundColor: Colors.orange,
          ),
        );
        
        // Force app restart (in a real app, you might want to navigate to initial setup)
        SystemNavigator.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error clearing data. Please restart the app manually.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
