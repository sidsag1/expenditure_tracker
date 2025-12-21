import 'package:flutter/material.dart';
import '../models/account.dart';
import '../database/account_dao.dart';

class AddAccountScreen extends StatefulWidget {
  const AddAccountScreen({super.key});

  @override
  State<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends State<AddAccountScreen> {
  final AccountDAO _accountDAO = AccountDAO();
  final _formKey = GlobalKey<FormState>();
  
  String _selectedAccountType = 'bank_account';
  String _selectedBank = '';
  final TextEditingController _accountNameController = TextEditingController();
  final TextEditingController _accountNumberController = TextEditingController();
  final TextEditingController _balanceController = TextEditingController();
  
  bool _isLoading = false;
  String _errorMessage = '';

  final List<Map<String, dynamic>> _accountTypes = [
    {'value': 'bank_account', 'label': 'Bank Account', 'icon': Icons.account_balance},
    {'value': 'debit_card', 'label': 'Debit Card', 'icon': Icons.credit_card},
    {'value': 'credit_card', 'label': 'Credit Card', 'icon': Icons.credit_card},
    {'value': 'wallet', 'label': 'Digital Wallet', 'icon': Icons.wallet},
  ];

  final List<String> _banks = [
    'ICICI',
    'HDFC',
    'SBI',
    'Axis Bank',
    'Kotak Mahindra',
    'Bank of Baroda',
    'Punjab National Bank',
    'Canara Bank',
    'IDBI Bank',
    'Yes Bank',
    'IndusInd Bank',
    'Federal Bank',
    'RBL Bank',
    'South Indian Bank',
    'Amazon Pay',
    'Google Pay',
    'PhonePe',
    'Paytm',
    'Other',
  ];

  @override
  void dispose() {
    _accountNameController.dispose();
    _accountNumberController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Add Account',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Account Type Selection
              _buildSectionTitle('Account Type'),
              const SizedBox(height: 12),
              _buildAccountTypeSelector(),
              
              const SizedBox(height: 24),
              
              // Bank Selection
              _buildSectionTitle('Bank/Wallet'),
              const SizedBox(height: 12),
              _buildBankSelector(),
              
              const SizedBox(height: 24),
              
              // Account Name
              _buildSectionTitle('Account Name'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNameController,
                style: const TextStyle(color: Colors.white),
                decoration: _buildInputDecoration(
                  'Enter a name for this account',
                  Icons.account_circle,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an account name';
                  }
                  if (value.trim().length < 2) {
                    return 'Account name must be at least 2 characters';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // Account Number
              _buildSectionTitle('Account/Card Number'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNumberController,
                style: const TextStyle(color: Colors.white),
                decoration: _buildInputDecoration(
                  'Enter masked account number (e.g., XX1234)',
                  Icons.numbers,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter account number';
                  }
                  if (value.trim().length < 4) {
                    return 'Account number must be at least 4 characters';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 24),
              
              // Current Balance
              _buildSectionTitle('Current Balance'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: _buildInputDecoration(
                  'Enter current balance',
                  Icons.currency_rupee,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter current balance';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 32),
              
              // Error Message
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
              
              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[400],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save Account',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey[300],
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[600]),
      prefixIcon: Icon(icon, color: Colors.grey[400]),
      filled: true,
      fillColor: const Color(0xFF1a1a2e),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[700]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[700]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue[400]!, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red[400]!, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red[400]!, width: 2),
      ),
    );
  }

  Widget _buildAccountTypeSelector() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _accountTypes.length,
      itemBuilder: (context, index) {
        final type = _accountTypes[index];
        final isSelected = _selectedAccountType == type['value'];
        
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedAccountType = type['value'];
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected 
                ? Colors.blue[400]!.withOpacity(0.2)
                : const Color(0xFF1a1a2e),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected 
                  ? Colors.blue[400]!
                  : Colors.grey[700]!,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type['icon'] as IconData,
                  color: isSelected ? Colors.blue[400] : Colors.grey[400],
                ),
                const SizedBox(width: 8),
                Text(
                  type['label'],
                  style: TextStyle(
                    color: isSelected ? Colors.blue[400] : Colors.grey[300],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBankSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: DropdownButtonFormField<String>(
        value: _selectedBank.isEmpty ? null : _selectedBank,
        decoration: const InputDecoration(
          hintText: 'Select bank or wallet',
          prefixIcon: Icon(Icons.account_balance, color: Colors.grey),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        hint: Text(
          'Select bank or wallet',
          style: TextStyle(color: Colors.grey[600]),
        ),
        dropdownColor: const Color(0xFF1a1a2e),
        style: const TextStyle(color: Colors.white),
        iconEnabledColor: Colors.grey[400],
        items: _banks.map((bank) {
          return DropdownMenuItem(
            value: bank,
            child: Text(bank),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedBank = value ?? '';
          });
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please select a bank or wallet';
          }
          return null;
        },
      ),
    );
  }

  Future<void> _saveAccount() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Check if account number already exists
      final accountNumberExists = await _accountDAO.accountNumberExists(
        _accountNumberController.text.trim(),
      );

      if (accountNumberExists) {
        setState(() {
          _errorMessage = 'An account with this number already exists';
          _isLoading = false;
        });
        return;
      }

      // Create new account
      final now = DateTime.now();
      final account = Account(
        accountType: _selectedAccountType,
        bankName: _selectedBank,
        accountNumber: _accountNumberController.text.trim(),
        accountName: _accountNameController.text.trim(),
        currentBalance: double.parse(_balanceController.text),
        createdAt: now,
        updatedAt: now,
      );

      // Save to database
      final accountId = await _accountDAO.insertAccount(account);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account added successfully!'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save account: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
}
