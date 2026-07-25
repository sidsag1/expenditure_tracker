import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/sms_service.dart';

class SMSPermissionScreen extends StatefulWidget {
  final VoidCallback? onPermissionGranted;
  final VoidCallback? onPermissionDenied;

  const SMSPermissionScreen({
    super.key,
    this.onPermissionGranted,
    this.onPermissionDenied,
  });

  @override
  State<SMSPermissionScreen> createState() => _SMSPermissionScreenState();
}

class _SMSPermissionScreenState extends State<SMSPermissionScreen> {
  final SMSService _smsService = SMSService();
  
  PermissionStatus _permissionStatus = PermissionStatus.denied;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _checkPermissionStatus();
  }

  Future<void> _checkPermissionStatus() async {
    final status = await _smsService.getPermissionStatus();
    setState(() {
      _permissionStatus = status;
    });

    if (status == PermissionStatus.granted) {
      widget.onPermissionGranted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'SMS Permission Required',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            
            // Icon and illustration
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue[400]!.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.message,
                size: 80,
                color: Colors.blue[400],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Title
            const Text(
              'Enable SMS Access',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 16),
            
            // Description
            Text(
              'To automatically track your expenses from bank messages, we need permission to read your SMS messages.',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 32),
            
            // Features list
            _buildFeatureList(),
            
            const SizedBox(height: 32),
            
            // Error message
            if (_errorMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
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
            
            const Spacer(),
            
            // Action buttons
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureList() {
    return Column(
      children: [
        _buildFeatureItem(
          Icons.shield,
          'Secure & Private',
          'Your SMS data stays on your device',
        ),
        const SizedBox(height: 16),
        _buildFeatureItem(
          Icons.analytics,
          'Smart Analysis',
          'Automatically categorizes your expenses',
        ),
        const SizedBox(height: 16),
        _buildFeatureItem(
          Icons.account_balance,
          'Multiple Banks',
          'Supports ICICI, Kotak, SBI, and more',
        ),
      ],
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green[400]!.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.green[400], size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    if (_permissionStatus == PermissionStatus.granted) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[400]!.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green[400]!.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[400], size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'SMS permission granted!',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: widget.onPermissionGranted,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[400],
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (_permissionStatus == PermissionStatus.denied)
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _requestPermission,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[400],
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.message, color: Colors.white),
            label: Text(
              _isLoading ? 'Requesting Permission...' : 'Grant SMS Permission',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        
        if (_permissionStatus == PermissionStatus.permanentlyDenied)
          Column(
            children: [
              Text(
                'Permission was permanently denied.',
                style: TextStyle(
                  color: Colors.orange[400],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _openSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[400],
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        
        const SizedBox(height: 16),
        
        TextButton(
          onPressed: widget.onPermissionDenied,
          child: Text(
            'Skip for now',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        TextButton(
          onPressed: _showPrivacyInfo,
          child: Text(
            'How we protect your privacy',
            style: TextStyle(
              color: Colors.blue[400],
              fontSize: 14,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _requestPermission() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final status = await _smsService.requestPermission();
      
      setState(() {
        _permissionStatus = status;
        _isLoading = false;
      });

      if (status == PermissionStatus.granted) {
        await _smsService.init();
        widget.onPermissionGranted?.call();
      } else {
        setState(() {
          _errorMessage = 'SMS permission is required to track expenses automatically.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to request permission: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _openSettings() async {
    final opened = await _smsService.openSettings();
    if (!opened) {
      setState(() {
        _errorMessage = 'Could not open app settings. Please enable SMS permission manually.';
      });
    }
  }

  void _showPrivacyInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text(
          'Privacy & Security',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Your privacy is our priority. Here\'s how we protect your data:\n\n'
          '• SMS messages are read only from your device\n'
          '• No data is sent to external servers\n'
          '• All financial information stays stored locally on your device, '
          'protected by your device lock and app PIN\n'
          '• You can revoke SMS permission anytime\n'
          '• We only read messages from supported banks\n'
          '• Transaction data is processed locally for categorization',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Got it',
              style: TextStyle(color: Colors.blue[400]),
            ),
          ),
        ],
      ),
    );
  }
}
