import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../database/account_dao.dart';
import '../database/transaction_dao.dart';
import 'add_account_screen.dart';
import 'add_transaction_screen.dart';
import 'transactions_screen.dart';
import '../utils/formatters.dart';

class AccountDetailScreen extends StatefulWidget {
  final Account account;

  const AccountDetailScreen({
    super.key,
    required this.account,
  });

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  final AccountDAO _accountDAO = AccountDAO();
  final TransactionDAO _transactionDAO = TransactionDAO();
  
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  String _errorMessage = '';
  double _totalExpenses = 0.0;
  double _totalIncome = 0.0;
  double _totalTransfers = 0.0;

  // On a credit card, the payments that clear the bill are the account's
  // biggest credits; a "Total Income" for the card that omits them describes
  // almost nothing that happened on it. Elsewhere they stay excluded — see
  // TransactionDAO.getTotalIncome for why they must not reach a cross-account
  // total.
  bool get _countsTransfersAsIncome =>
      widget.account.accountType == 'credit_card';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      // Load transactions for this account (limit to 10 for display)
      final transactions = await _transactionDAO.getTransactionsByAccount(widget.account.id!, limit: 10);

      // Calculate totals
      final expenses = await _transactionDAO.getTotalExpenses(accountId: widget.account.id);
      final income = await _transactionDAO.getTotalIncome(
        accountId: widget.account.id,
        includeTransfers: _countsTransfersAsIncome,
      );
      // Only the leg that matches what the note below says: the credits
      // folded *into* income on a card, or every transfer left out of both
      // totals everywhere else.
      final transfers = await _transactionDAO.getTotalTransfers(
        accountId: widget.account.id,
        transactionType: _countsTransfersAsIncome ? 'credit' : null,
      );

      if (!mounted) return;
      setState(() {
        _transactions = transactions;
        _totalExpenses = expenses;
        _totalIncome = income;
        _totalTransfers = transfers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load account details: ${e.toString()}';
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
        title: Text(
          widget.account.accountName,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: _navigateToEditAccount,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _showDeleteDialog,
          ),
        ],
      ),
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blue),
      );
    }

    if (_errorMessage.isNotEmpty) {
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
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account Overview Card
          _buildAccountOverviewCard(),
          
          const SizedBox(height: 24),
          
          // Statistics
          _buildStatisticsCards(),
          
          const SizedBox(height: 24),
          
          // Recent Transactions
          _buildTransactionsSection(),
        ],
      ),
    );
  }

  Widget _buildAccountOverviewCard() {
    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildAccountIcon(widget.account.accountType),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.account.accountName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.account.bankName} • ${_formatAccountType(widget.account.accountType)}',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.grey),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account Number',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.account.accountNumber.isEmpty
                          ? '—'
                          : '****${widget.account.accountNumber}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.account.debitCards.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Debit Cards',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.account.debitCards.join(', '),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.account.balanceLabel,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatINR(widget.account.currentBalance),
                      style: TextStyle(
                        color: widget.account.currentBalance >= 0
                          ? Colors.green[400]
                          : Colors.red[400],
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'as of ${_formatDate(widget.account.updatedAt)}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Income',
                _totalIncome,
                Colors.green[400]!,
                Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Total Expenses',
                _totalExpenses,
                Colors.red[400]!,
                Icons.trending_down,
              ),
            ),
          ],
        ),
        // Transfers move the user's own money between their own accounts, so
        // what the two totals above did with them is never self-evident from
        // the list below — the same ₹50,000 credit is either counted or not
        // depending on which account you are looking at. Say which, rather
        // than leaving a visible row that doesn't reconcile with the figure
        // over it.
        if (_totalTransfers > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.swap_horiz, size: 14, color: Colors.blue[300]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _countsTransfersAsIncome
                      ? 'Includes ${formatINR(_totalTransfers)} of payments made '
                          'to this card from your own accounts. These are not '
                          'counted as income anywhere else.'
                      : 'Excludes ${formatINR(_totalTransfers)} of transfers between '
                          'your own accounts (e.g. card bill payments).',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStatCard(String title, double amount, Color color, IconData icon) {
    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              formatINR(amount),
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsSection() {
    return Column(
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
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        TransactionsScreen(account: widget.account),
                  ),
                );
                _loadData();
              },
              child: Text(
                'View All',
                style: TextStyle(color: Colors.blue[400]),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_transactions.isEmpty)
          Card(
            color: const Color(0xFF1a1a2e),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long,
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
                    'Transactions will appear here once SMS parsing is enabled',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _transactions.length,
            itemBuilder: (context, index) {
              final transaction = _transactions[index];
              return _buildTransactionTile(transaction);
            },
          ),
      ],
    );
  }

  Widget _buildTransactionTile(Transaction transaction) {
    // A transfer leg moves the user's own money, so it stays visually apart
    // from the rows that are plain income or spending. It keeps that colour on
    // a credit card even though Total Income now counts it: what makes it a
    // transfer is where the money came from, not whether this particular
    // screen happens to total it.
    final isTransfer = transaction.isTransfer;
    final amountColor = isTransfer
        ? Colors.blue[300]!
        : (transaction.isExpense ? Colors.red[400]! : Colors.green[400]!);
    final transferNote = _countsTransfersAsIncome && !transaction.isExpense
        ? 'Transfer • counted as income on this card'
        : 'Transfer • not counted as income';

    return Card(
      color: const Color(0xFF1a1a2e),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _navigateToTransactionDetail(transaction),
        leading: CircleAvatar(
          backgroundColor: amountColor.withValues(alpha: 0.2),
          child: Icon(
            isTransfer
                ? Icons.swap_horiz
                : (transaction.isExpense ? Icons.remove : Icons.add),
            color: amountColor,
          ),
        ),
        title: Text(
          transaction.description,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          '${_formatDate(transaction.transactionDate)} • '
          '${isTransfer ? transferNote : transaction.category}',
          style: TextStyle(color: Colors.grey[400]),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              transaction.formattedAmount,
              style: TextStyle(
                color: amountColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (transaction.merchant != null)
              Text(
                transaction.merchant!,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 10,
                ),
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
      backgroundColor: color.withValues(alpha: 0.2),
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Future<void> _navigateToTransactionDetail(Transaction transaction) async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTransactionScreen(transaction: transaction),
      ),
    );
    if (updated == true) {
      _loadData();
    }
  }

  Future<void> _navigateToEditAccount() async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddAccountScreen(existingAccount: widget.account),
      ),
    );
    // AddAccountScreen edits `widget.account`'s underlying row but this
    // screen's fields all read from the widget's own (now-stale) copy, so
    // rather than partially refreshing in place, pop back to the account
    // list -- which already reloads on `true`, same as the delete flow.
    if (updated == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this account? This action cannot be undone.',
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
              _deleteAccount();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    try {
      await _accountDAO.deleteAccount(widget.account.id!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
