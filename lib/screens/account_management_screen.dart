import 'package:flutter/material.dart';
import '../models/account.dart';
import '../database/account_dao.dart';
import '../utils/formatters.dart';
import 'add_account_screen.dart';
import 'account_detail_screen.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() => _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final AccountDAO _accountDAO = AccountDAO();
  List<Account> _accounts = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _selectedFilter = 'all'; // 'all', 'bank_account', 'credit_card', 'wallet'

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      List<Account> accounts;
      switch (_selectedFilter) {
        case 'all':
          accounts = await _accountDAO.getActiveAccounts();
          break;
        default:
          accounts = await _accountDAO.getAccountsByType(_selectedFilter);
          break;
      }

      setState(() {
        _accounts = accounts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load accounts: ${e.toString()}';
        _isLoading = false;
      });
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
          'Account Management',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadAccounts,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'all'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Bank Accounts', 'bank_account'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Credit Cards', 'credit_card'),
                  const SizedBox(width: 8),
                  _buildFilterChip('Wallets', 'wallet'),
                ],
              ),
            ),
          ),

          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToAddAccount(),
        backgroundColor: Colors.blue[400],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedFilter = value;
          });
          _loadAccounts();
        }
      },
      selectedColor: Colors.blue[400]!.withOpacity(0.3),
      checkmarkColor: Colors.blue[400],
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue[400] : Colors.grey[400],
      ),
      backgroundColor: Colors.grey[800],
      side: BorderSide(color: Colors.grey[700]!),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.blue,
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(color: Colors.red[400]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadAccounts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_accounts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_wallet,
              size: 64,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'No accounts found',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedFilter == 'all'
                  ? 'Add your first account to get started'
                  : 'No accounts of this type found',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _navigateToAddAccount,
              icon: const Icon(Icons.add),
              label: const Text('Add Account'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAccounts,
      color: Colors.blue[400],
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _accounts.length,
        itemBuilder: (context, index) {
          final account = _accounts[index];
          return _buildAccountCard(account);
        },
      ),
    );
  }

  Widget _buildAccountCard(Account account) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1a1a2e),
      child: ListTile(
        onTap: () => _navigateToAccountDetail(account),
        leading: _buildAccountIcon(account.accountType),
        title: Text(
          account.accountName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${account.bankName} • ${_formatAccountType(account.accountType)}',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 4),
            Text(
              account.accountNumber.isEmpty
                  ? 'No number'
                  : '****${account.accountNumber}',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
            if (account.debitCards.isNotEmpty)
              Text(
                'Debit cards: ${account.debitCards.join(', ')}',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatINR(account.currentBalance),
              style: TextStyle(
                color: account.currentBalance >= 0 ? Colors.green[400] : Colors.red[400],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountIcon(String accountType) {
    IconData icon;
    Color color;

    switch (accountType) {
      case 'bank_account':
        icon = Icons.account_balance;
        color = Colors.blue[400]!;
        break;
      case 'debit_card':
        icon = Icons.credit_card;
        color = Colors.green[400]!;
        break;
      case 'credit_card':
        icon = Icons.credit_card;
        color = Colors.orange[400]!;
        break;
      case 'wallet':
        icon = Icons.wallet;
        color = Colors.purple[400]!;
        break;
      default:
        icon = Icons.account_balance_wallet;
        color = Colors.grey[400]!;
    }

    return CircleAvatar(
      backgroundColor: color.withOpacity(0.2),
      child: Icon(icon, color: color),
    );
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
        return 'Digital Wallet';
      default:
        return accountType;
    }
  }

  Future<void> _navigateToAddAccount() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddAccountScreen(),
      ),
    );

    if (result == true) {
      _loadAccounts();
    }
  }

  Future<void> _navigateToAccountDetail(Account account) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AccountDetailScreen(account: account),
      ),
    );

    if (result == true) {
      _loadAccounts();
    }
  }
}
