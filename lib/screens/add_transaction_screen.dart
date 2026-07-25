import 'package:flutter/material.dart';
import '../models/transaction.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../database/transaction_dao.dart';
import '../database/account_dao.dart';
import '../database/category_dao.dart';
import '../utils/app_logger.dart';

class AddTransactionScreen extends StatefulWidget {
  final Transaction? transaction; // For editing existing transaction

  const AddTransactionScreen({
    super.key,
    this.transaction,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  static const Color _grey600 = Color(0xFF9E9E9E);
  
  final TransactionDAO _transactionDAO = TransactionDAO();
  final AccountDAO _accountDAO = AccountDAO();
  final CategoryDAO _categoryDAO = CategoryDAO();
  
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _merchantController = TextEditingController();
  final _referenceController = TextEditingController();
  
  String _selectedTransactionType = 'debit';
  String _selectedCategory = 'Uncategorized';
  Account? _selectedAccount;
  DateTime _selectedDate = DateTime.now();
  bool _adjustBalance = false;
  
  List<Account> _accounts = [];
  List<Category> _categories = [];
  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.transaction != null;
    _loadData();
    
    if (_isEditing) {
      _populateFields();
    }
  }

  Future<void> _loadData() async {
    try {
      _accounts = await _accountDAO.getActiveAccounts();
      _categories = await _categoryDAO.getAllCategories();

      if (_isEditing && widget.transaction!.accountId != null) {
        // Look up by id directly rather than scanning the active-only list —
        // an account deactivated after this transaction was created must
        // still be editable/re-saveable, not silently dropped to null.
        final existingAccount =
            await _accountDAO.getAccountById(widget.transaction!.accountId!);
        if (existingAccount != null) {
          _selectedAccount = existingAccount;
          if (!_accounts.any((a) => a.id == existingAccount.id)) {
            _accounts = [..._accounts, existingAccount];
          }
        }
      }

      // Guard against a category that no longer exists (stale data, a
      // deleted custom category) — DropdownButtonFormField throws if its
      // value doesn't match any item once the list is non-empty.
      if (_categories.isNotEmpty &&
          !_categories.any((c) => c.name == _selectedCategory)) {
        _selectedCategory = _categories
            .firstWhere(
              (c) => c.name == 'Uncategorized',
              orElse: () => _categories.first,
            )
            .name;
      }

      setState(() {});
    } catch (e, stackTrace) {
      AppLogger.error('Error loading data', e, stackTrace);
    }
  }

  void _populateFields() {
    if (widget.transaction != null) {
      final transaction = widget.transaction!;
      _amountController.text = transaction.amount.toString();
      _descriptionController.text = transaction.description;
      _merchantController.text = transaction.merchant ?? '';
      _referenceController.text = transaction.referenceNumber ?? '';
      _selectedTransactionType = transaction.transactionType;
      _selectedCategory = transaction.category;
      _selectedDate = transaction.transactionDate;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _merchantController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f0f23),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _isEditing ? 'Edit Transaction' : 'Add Transaction',
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Transaction Type
              _buildSectionTitle('Transaction Type'),
              const SizedBox(height: 8),
              _buildTransactionTypeSelector(),
              
              const SizedBox(height: 24),
              
              // Account Selection
              _buildSectionTitle('Account'),
              const SizedBox(height: 8),
              _buildAccountSelector(),

              if (!_isEditing && _selectedAccount != null) ...[
                const SizedBox(height: 12),
                _buildAdjustBalanceToggle(),
              ],

              const SizedBox(height: 24),
              
              // Amount and Date
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('Amount *'),
                        const SizedBox(height: 8),
                        _buildAmountField(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle('Date'),
                        const SizedBox(height: 8),
                        _buildDateField(),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Description
              _buildSectionTitle('Description'),
              const SizedBox(height: 8),
              _buildDescriptionField(),
              
              const SizedBox(height: 24),
              
              // Merchant (for expenses)
              if (_selectedTransactionType == 'debit') ...[
                _buildSectionTitle('Merchant'),
                const SizedBox(height: 8),
                _buildMerchantField(),
                const SizedBox(height: 24),
              ],
              
              // Category
              _buildSectionTitle('Category'),
              const SizedBox(height: 8),
              _buildCategorySelector(),
              
              const SizedBox(height: 24),
              
              // Reference Number
              _buildSectionTitle('Reference Number (Optional)'),
              const SizedBox(height: 8),
              _buildReferenceField(),
              
              const SizedBox(height: 32),
              
              // Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _isLoading || _accounts.isEmpty ? null : _saveTransaction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedTransactionType == 'credit' 
                        ? Colors.green[400] 
                        : Colors.red[400],
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
                      : Text(
                          _isEditing ? 'Update Transaction' : 'Save Transaction',
                          style: const TextStyle(
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

  // ListTile and RadioListTile paint their ink on the nearest Material
  // ancestor. Inside a bare Container they assert on every build
  // ("ListTile background color or ink splashes may be invisible"), taps show
  // no ripple, and any widget test of this screen fails outright because the
  // framework reports those asserts as unexpected exceptions. A Material with
  // a shape renders identically to the old BoxDecoration and gives the tiles
  // a real ink surface.
  Widget _buildSurface({required Widget child, EdgeInsetsGeometry? padding}) {
    return Material(
      color: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[700]!),
      ),
      clipBehavior: Clip.antiAlias,
      child: padding == null ? child : Padding(padding: padding, child: child),
    );
  }

  Widget _buildTransactionTypeSelector() {
    return _buildSurface(
      child: RadioGroup<String>(
        groupValue: _selectedTransactionType,
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _selectedTransactionType = value;
            });
          }
        },
        child: Row(
          children: [
            Expanded(
              child: RadioListTile<String>(
                title: const Text(
                  'Expense',
                  style: TextStyle(color: Colors.white),
                ),
                value: 'debit',
                activeColor: Colors.red[400],
              ),
            ),
            Expanded(
              child: RadioListTile<String>(
                title: const Text(
                  'Income',
                  style: TextStyle(color: Colors.white),
                ),
                value: 'credit',
                activeColor: Colors.green[400],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSelector() {
    if (_accounts.isEmpty) {
      return _buildSurface(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No accounts found. Please add an account first.',
          style: TextStyle(color: Colors.grey[400]),
          textAlign: TextAlign.center,
        ),
      );
    }

    return _buildSurface(
      child: DropdownButtonFormField<Account>(
        initialValue: _selectedAccount,
        // Without this the button lays its selected item out in a
        // shrink-wrapping Row, i.e. with unbounded width, and the Expanded in
        // the item below throws "RenderFlex children have non-zero flex but
        // incoming width constraints are unbounded" during layout.
        isExpanded: true,
        validator: (value) =>
            value == null ? 'Please select an account' : null,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        hint: const Text(
          'Select account',
          style: TextStyle(color: _grey600),
        ),
        dropdownColor: const Color(0xFF1a1a2e),
        style: const TextStyle(color: Colors.white),
        icon: Icon(Icons.account_balance_wallet, color: Colors.grey[400]),
        items: _accounts.map((account) {
          return DropdownMenuItem(
            value: account,
            child: Row(
              children: [
                Text(_getAccountIcon(account.accountType)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.accountName,
                        style: const TextStyle(color: Colors.white),
                      ),
                      Text(
                        '${account.bankName} • ${_formatAccountType(account.accountType)}',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedAccount = value;
          });
        },
      ),
    );
  }

  // Lets a manual entry move the account's stored balance by the transaction
  // amount (debit subtracts, credit adds) instead of leaving it untouched.
  // Only offered when adding (not editing) a transaction: applying it again
  // on an edit would double-count without knowing whether the original entry
  // already adjusted the balance.
  Widget _buildAdjustBalanceToggle() {
    return _buildSurface(
      child: CheckboxListTile(
        value: _adjustBalance,
        onChanged: (value) =>
            setState(() => _adjustBalance = value ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: Colors.blue[400],
        title: const Text(
          'Adjust account balance',
          style: TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          _selectedTransactionType == 'debit'
              ? 'Subtract this amount from the account balance'
              : 'Add this amount to the account balance',
          style: TextStyle(color: Colors.grey[400], fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return TextFormField(
      controller: _amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Enter amount',
        hintStyle: const TextStyle(color: _grey600),
        prefixIcon: Icon(Icons.currency_rupee, color: Colors.grey[400]),
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
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter an amount';
        }
        if (double.tryParse(value) == null || double.tryParse(value)! <= 0) {
          return 'Please enter a valid amount';
        }
        return null;
      },
    );
  }

  Widget _buildDateField() {
    return _buildSurface(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(
          'Selected Date',
          style: TextStyle(color: Colors.grey[400]),
        ),
        subtitle: Text(
          '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
          style: const TextStyle(color: Colors.white),
        ),
        trailing: Icon(Icons.calendar_today, color: Colors.grey[400]),
        onTap: _selectDate,
      ),
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Enter description',
        hintStyle: const TextStyle(color: _grey600),
        prefixIcon: Icon(Icons.description, color: Colors.grey[400]),
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
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter a description';
        }
        return null;
      },
    );
  }

  Widget _buildMerchantField() {
    return TextFormField(
      controller: _merchantController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Enter merchant name',
        hintStyle: const TextStyle(color: _grey600),
        prefixIcon: Icon(Icons.store, color: Colors.grey[400]),
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
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter merchant name';
        }
        return null;
      },
    );
  }

  Widget _buildCategorySelector() {
    return _buildSurface(
      child: DropdownButtonFormField<String>(
        initialValue: _selectedCategory,
        isExpanded: true,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        hint: const Text(
          'Select category',
          style: TextStyle(color: _grey600),
        ),
        dropdownColor: const Color(0xFF1a1a2e),
        style: const TextStyle(color: Colors.white),
        icon: Icon(Icons.category, color: Colors.grey[400]),
        items: _categories.map((category) {
          return DropdownMenuItem(
            value: category.name,
            child: Row(
              children: [
                Text(category.icon),
                const SizedBox(width: 8),
                Text(category.name),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _selectedCategory = value;
            });
          }
        },
      ),
    );
  }

  Widget _buildReferenceField() {
    return TextFormField(
      controller: _referenceController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Enter reference number (optional)',
        hintStyle: const TextStyle(color: _grey600),
        prefixIcon: Icon(Icons.tag, color: Colors.grey[400]),
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
      ),
    );
  }

  String _getAccountIcon(String accountType) {
    switch (accountType) {
      case 'bank_account':
        return '🏦';
      case 'debit_card':
        return '💳️';
      case 'credit_card':
        return '💳️';
      case 'wallet':
        return '👛';
      default:
        return '🏦';
    }
  }

  String _formatAccountType(String accountType) {
    switch (accountType) {
      case 'bank_account':
        return 'Bank Account';
      case 'debit_card':
        return 'Debit Card';
      case 'credit_card':
        return 'Credit Card';
      case 'wallet':
        return 'Wallet';
      default:
        return accountType;
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();
      final transaction = Transaction(
        id: _isEditing ? widget.transaction!.id : null,
        accountId: _selectedAccount?.id,
        transactionType: _selectedTransactionType,
        amount: double.parse(_amountController.text),
        description: _descriptionController.text.trim(),
        merchant: _selectedTransactionType == 'debit' ? _merchantController.text.trim() : null,
        transactionDate: _selectedDate,
        referenceNumber: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
        transactionId: _isEditing ? widget.transaction!.transactionId : null,
        category: _selectedCategory,
        bankName: _selectedAccount?.bankName ?? '',
        accountType: _selectedAccount?.accountType ?? '',
        isManual: _isEditing ? widget.transaction!.isManual : true,
        isPending: _isEditing ? widget.transaction!.isPending : false,
        // SMS-derived provenance must survive an edit rather than silently
        // reset to the manual-entry defaults (Transaction()'s defaults are
        // source: 'manual', isTransfer/needsReview: false).
        balanceAfter: _isEditing ? widget.transaction!.balanceAfter : null,
        isTransfer: _isEditing ? widget.transaction!.isTransfer : false,
        needsReview: _isEditing ? widget.transaction!.needsReview : false,
        source: _isEditing ? widget.transaction!.source : 'manual',
        rawMessageHash: _isEditing ? widget.transaction!.rawMessageHash : null,
        createdAt: _isEditing ? widget.transaction!.createdAt : now,
        updatedAt: now,
      );

      if (_isEditing) {
        await _transactionDAO.updateTransaction(transaction);
      } else {
        await _transactionDAO.insertTransaction(transaction);
        if (_adjustBalance && _selectedAccount != null) {
          final delta = _selectedTransactionType == 'debit'
              ? -transaction.amount
              : transaction.amount;
          await _accountDAO.updateAccountBalance(
            _selectedAccount!.id!,
            _selectedAccount!.currentBalance + delta,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Transaction updated successfully!' : 'Transaction added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
