import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class PinSetupScreen extends StatefulWidget {
  final bool isFirstTime;
  final VoidCallback? onComplete;

  const PinSetupScreen({
    super.key,
    this.isFirstTime = true,
    this.onComplete,
  });

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final AuthService _authService = AuthService();
  
  String _currentPin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.isFirstTime ? 'Set Security PIN' : 'Change PIN',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Column(
            children: [
              // Title and description
              Icon(
                Icons.security,
                size: 48,
                color: Colors.blue[400],
              ),
              const SizedBox(height: 12),
              Text(
                _isConfirming ? 'Confirm Your PIN' : 'Create Security PIN',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isConfirming
                    ? 'Enter the same PIN again to confirm'
                    : 'Choose a 4-6 digit PIN to secure your financial data',
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
                children: List.generate(6, (index) {
                  final indexToShow = _isConfirming ? _confirmPin.length : _currentPin.length;
                  final isFilled = index < indexToShow;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled ? Colors.blue[400] : Colors.grey[700],
                      border: Border.all(
                        color: Colors.grey[600]!,
                        width: 1,
                      ),
                    ),
                  );
                }),
              ),

              // Error message
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
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

              // Help text
              if (_isConfirming)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isConfirming = false;
                      _currentPin = '';
                      _confirmPin = '';
                      _errorMessage = '';
                    });
                  },
                  child: Text(
                    'Start Over',
                    style: TextStyle(color: Colors.blue[400]),
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
          child: FittedBox(
            fit: BoxFit.scaleDown,
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
      ),
    );
  }

  void _onNumberPress(String number) {
    if (_isLoading) return;
    
    setState(() {
      _errorMessage = '';
    });
    
    if (!_isConfirming) {
      if (_currentPin.length < 6) {
        setState(() {
          _currentPin += number;
        });
      }
    } else {
      if (_confirmPin.length < 6) {
        setState(() {
          _confirmPin += number;
        });
      }
    }
    
    // Auto-advance when PIN is complete
    if ((!_isConfirming && _currentPin.length == 6) ||
        (_isConfirming && _confirmPin.length == 6)) {
      Future.delayed(const Duration(milliseconds: 300), () {
        _onSubmit();
      });
    }
  }

  void _onBackspace() {
    if (_isLoading) return;
    
    setState(() {
      _errorMessage = '';
    });
    
    if (!_isConfirming) {
      if (_currentPin.isNotEmpty) {
        setState(() {
          _currentPin = _currentPin.substring(0, _currentPin.length - 1);
        });
      }
    } else {
      if (_confirmPin.isNotEmpty) {
        setState(() {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        });
      }
    }
  }

  Future<void> _onSubmit() async {
    if (_isLoading) return;
    
    final currentPin = _isConfirming ? _confirmPin : _currentPin;
    
    if (currentPin.length < 4) {
      setState(() {
        _errorMessage = 'PIN must be at least 4 digits';
      });
      return;
    }

    if (!_isConfirming) {
      // Move to confirmation phase
      setState(() {
        _isConfirming = true;
        _errorMessage = '';
      });
    } else {
      // Confirm PINs match
      if (_currentPin != _confirmPin) {
        setState(() {
          _errorMessage = 'PINs do not match. Please try again.';
          _isConfirming = false;
          _currentPin = '';
          _confirmPin = '';
        });
        return;
      }
      
      // Save PIN
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
      
      try {
        final success = await _authService.setPin(currentPin);
        
        if (success) {
          // Set first launch completed if applicable
          if (widget.isFirstTime) {
            await _authService.setFirstLaunchCompleted();
          }
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('PIN setup successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            
            widget.onComplete?.call();
          }
        } else {
          setState(() {
            _errorMessage = 'Failed to save PIN. Please try again.';
          });
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'An error occurred. Please try again.';
        });
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
