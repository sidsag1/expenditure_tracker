import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../database/account_dao.dart';
import '../database/transaction_dao.dart';
import '../services/sms_service.dart';
import '../screens/account_management_screen.dart';
import '../screens/transactions_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AccountDAO _accountDAO = AccountDAO();
  final TransactionDAO _transactionDAO = TransactionDAO();
  
  List<Account> _accounts = [];
  List<Transaction> _recentTransactions = [];
  double _totalBalance = 0.0;
  double _totalAvailableCredit = 0.0;
  double _totalIncome = 0.0;
  double _totalExpenses = 0.0;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      // Pull and parse bank SMS messages before loading dashboard data.
      // First run processes the entire inbox; later runs only new messages.
      // Failures here (e.g. permission revoked) shouldn't block the dashboard.
      try {
        await SMSService().syncMessages();
      } catch (_) {
        // Ignore sync errors; dashboard still shows existing data.
      }

      // Load data in parallel
      final results = await Future.wait([
        _accountDAO.getActiveAccounts(),
        _accountDAO.getTotalBalance(),
        _accountDAO.getTotalAvailableCredit(),
        _transactionDAO.getRecentTransactions(limit: 5),
        _transactionDAO.getTotalIncome(startDate: DateTime.now().subtract(const Duration(days: 30))),
        _transactionDAO.getTotalExpenses(startDate: DateTime.now().subtract(const Duration(days: 30))),
      ]);

      setState(() {
        _accounts = results[0] as List<Account>;
        _totalBalance = results[1] as double;
        _totalAvailableCredit = results[2] as double;
        _recentTransactions = results[3] as List<Transaction>;
        _totalIncome = results[4] as double;
        _totalExpenses = results[5] as double;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load dashboard data: ${e.toString()}';
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
          'Dashboard',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadDashboardData,
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : _errorMessage.isNotEmpty
              ? _buildErrorWidget()
              : _buildDashboardContent(),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToTransactions,
        backgroundColor: Colors.blue[400],
        tooltip: 'Add Transaction',
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            style: TextStyle(color: Colors.red[400]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadDashboardData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      color: Colors.blue[400],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary cards stacked full-width so large amounts stay readable
            _buildBalanceCard(),
            const SizedBox(height: 12),
            _buildIncomeExpenseCard(),

            const SizedBox(height: 24),
            
            // Accounts Overview
            _buildAccountsOverview(),
            
            const SizedBox(height: 24),
            
            // Recent Transactions
            _buildRecentTransactions(),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: Colors.blue[400],
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Total Balance',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _formatCurrency(_totalBalance),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Across bank accounts & wallets',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
            ),
            if (_totalAvailableCredit > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.credit_card, color: Colors.orange[400], size: 16),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Available Credit: ${_formatCurrency(_totalAvailableCredit)}',
                        style: TextStyle(
                          color: Colors.orange[400],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeExpenseCard() {
    final net = _totalIncome - _totalExpenses;

    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last 30 Days',
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _buildIncomeExpenseItem(
                      'Income',
                      _totalIncome,
                      Colors.green[400]!,
                      Icons.arrow_downward,
                    ),
                  ),
                  VerticalDivider(color: Colors.grey[700], width: 32),
                  Expanded(
                    child: _buildIncomeExpenseItem(
                      'Expenses',
                      _totalExpenses,
                      Colors.red[400]!,
                      Icons.arrow_upward,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    net >= 0 ? 'Net Savings' : 'Net Spend',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 13,
                    ),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _formatCurrency(net.abs()),
                        style: TextStyle(
                          color: net >= 0 ? Colors.green[400] : Colors.red[400],
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeExpenseItem(String title, double amount, Color color, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _formatCurrency(amount),
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // Indian-style grouping, no paise for large amounts: ₹10,92,132
  String _formatCurrency(double amount) {
    final format = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: amount.abs() >= 1000 ? 0 : 2,
    );
    return format.format(amount);
  }

  Widget _buildAccountsOverview() {
    if (_accounts.isEmpty) {
      return Card(
        color: const Color(0xFF1a1a2e),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 48,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 16),
              Text(
                'No Accounts Added',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add your first bank account to start tracking expenses',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _navigateToAccounts,
                icon: const Icon(Icons.add),
                label: const Text('Add Account'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[400],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your Accounts',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: _navigateToAccounts,
                  child: Text(
                    'View All',
                    style: TextStyle(color: Colors.blue[400]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._accounts.take(3).map((account) => _buildAccountItem(account)),
            if (_accounts.length > 3)
              TextButton(
                onPressed: _navigateToAccounts,
                child: Text(
                  'View ${_accounts.length - 3} More Accounts',
                  style: TextStyle(color: Colors.blue[400]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountItem(Account account) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0f0f23),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Row(
        children: [
          _buildAccountIcon(account.accountType),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.accountName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${account.bankName} • ${_formatAccountType(account.accountType)}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${account.accountType == 'credit_card' ? 'Available Limit' : 'Balance'}: ${_formatCurrency(account.currentBalance)}',
                  style: TextStyle(
                    color: account.currentBalance >= 0
                        ? Colors.green[400]
                        : Colors.red[400],
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'as of ${_formatDate(account.updatedAt)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.arrow_forward_ios,
            color: Colors.grey[600],
            size: 16,
          ),
        ],
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
      backgroundColor: color.withValues(alpha: 0.2),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildRecentTransactions() {
    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Transactions',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextButton(
                  onPressed: _navigateToTransactions,
                  child: Text(
                    'View All',
                    style: TextStyle(color: Colors.blue[400]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_recentTransactions.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 48,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No transactions yet',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your recent transactions will appear here once you start adding them',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ..._recentTransactions.map((transaction) => _buildTransactionItem(transaction)),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Transaction transaction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: transaction.isExpense 
                ? Colors.red[400]!.withValues(alpha: 0.2)
                : Colors.green[400]!.withValues(alpha: 0.2),
            child: Icon(
              transaction.isExpense ? Icons.remove : Icons.add,
              color: transaction.isExpense ? Colors.red[400] : Colors.green[400],
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _formatDate(transaction.transactionDate),
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    if (transaction.merchant != null && transaction.merchant!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '• ${transaction.merchant}',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                transaction.formattedAmount,
                style: TextStyle(
                  color: transaction.isExpense ? Colors.red[400] : Colors.green[400],
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                transaction.category,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()} weeks ago';
    } else {
      return '${date.day}/${date.month}';
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

  void _navigateToAccounts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AccountManagementScreen(),
      ),
    );
  }

  void _navigateToTransactions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TransactionsScreen(),
      ),
    );
  }
}
