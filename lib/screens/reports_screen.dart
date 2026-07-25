import 'package:flutter/material.dart';
import '../database/transaction_dao.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final TransactionDAO _transactionDAO = TransactionDAO();
  
  List<Transaction> _transactions = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _selectedPeriod = '30 days'; // Default to 30 days

  final List<String> _periodOptions = [
    '7 days',
    '30 days',
    '90 days',
    '1 year',
  ];

  @override
  void initState() {
    super.initState();
    _loadReportsData();
  }

  Future<void> _loadReportsData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final now = DateTime.now();
      DateTime startDate;

      switch (_selectedPeriod) {
        case '7 days':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case '30 days':
          startDate = now.subtract(const Duration(days: 30));
          break;
        case '90 days':
          startDate = now.subtract(const Duration(days: 90));
          break;
        case '1 year':
          startDate = now.subtract(const Duration(days: 365));
          break;
        default:
          startDate = now.subtract(const Duration(days: 30));
      }

      final allTransactions = await _transactionDAO.getAllTransactions();
      
      setState(() {
        _transactions = allTransactions
            .where((t) => t.transactionDate.isAfter(startDate))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load reports data: ${e.toString()}';
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
          'Reports',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadReportsData,
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : _errorMessage.isNotEmpty
              ? _buildErrorWidget()
              : _buildReportsContent(),
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
            onPressed: _loadReportsData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsContent() {
    // Transfers (e.g. a credit-card bill payment) move money between the
    // user's own accounts rather than earning or spending it, so they're
    // excluded from both totals — while still appearing in the transaction
    // lists below, same as the DAO aggregates used elsewhere.
    final totalIncome = _transactions
        .where((t) => !t.isExpense && !t.isTransfer)
        .fold(0.0, (sum, t) => sum + t.amount);

    final totalExpenses = _transactions
        .where((t) => t.isExpense && !t.isTransfer)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final categoryTotals = _getCategoryTotals();

    return RefreshIndicator(
      onRefresh: _loadReportsData,
      color: Colors.blue[400],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Period selector
            _buildPeriodSelector(),
            
            const SizedBox(height: 24),
            
            // Summary cards
            _buildSummaryCards(totalIncome, totalExpenses),
            
            const SizedBox(height: 24),
            
            // Category breakdown
            _buildCategoryBreakdown(categoryTotals),
            
            const SizedBox(height: 24),
            
            // Transaction trends
            _buildTrendsList(),
            
            const SizedBox(height: 24),
            
            // Recent transactions summary
            _buildRecentTransactionsSummary(),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Time Period',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _periodOptions.map((period) {
                final isSelected = _selectedPeriod == period;
                return FilterChip(
                  label: Text(
                    period,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[400],
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedPeriod = period;
                      });
                      _loadReportsData();
                    }
                  },
                  backgroundColor: Colors.grey[800],
                  selectedColor: Colors.blue[400],
                  checkmarkColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(double totalIncome, double totalExpenses) {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Total Income',
            totalIncome,
            Colors.green[400]!,
            Icons.trending_up,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            'Total Expenses',
            totalExpenses,
            Colors.red[400]!,
            Icons.trending_down,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color, IconData icon) {
    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              formatINR(amount),
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown(Map<String, double> categoryTotals) {
    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Category Breakdown',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            if (categoryTotals.isEmpty)
              _buildEmptyState('No transactions found for the selected period')
            else
              ...categoryTotals.entries.map((entry) => _buildCategoryItem(entry.key, entry.value)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryItem(String category, double amount) {
    final totalExpenses = _transactions
        .where((t) => t.isExpense && !t.isTransfer)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final percentage = totalExpenses > 0 ? (amount / totalExpenses) * 100 : 0.0;

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatINR(amount),
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: Colors.blue[400],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 60,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: percentage / 100,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[400]!),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrendsList() {
    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Transactions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: _transactions.isEmpty
                  ? _buildEmptyState('No transactions for trends')
                  : ListView.builder(
                      itemCount: _transactions.length,
                      itemBuilder: (context, index) {
                        final transaction = _transactions[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0f0f23),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: transaction.isExpense 
                                    ? Colors.red[400]!.withValues(alpha: 0.2)
                                    : Colors.green[400]!.withValues(alpha: 0.2),
                                child: Icon(
                                  transaction.isExpense ? Icons.remove : Icons.add,
                                  color: transaction.isExpense ? Colors.red[400] : Colors.green[400],
                                  size: 12,
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
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${transaction.category} • ${_formatDate(transaction.transactionDate)}',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                transaction.formattedAmount,
                                style: TextStyle(
                                  color: transaction.isExpense ? Colors.red[400] : Colors.green[400],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTransactionsSummary() {
    final recentTransactions = _transactions.take(5).toList();

    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top Transactions',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            if (recentTransactions.isEmpty)
              _buildEmptyState('No recent transactions')
            else
              ...recentTransactions.map((transaction) => _buildTransactionSummaryItem(transaction)),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionSummaryItem(Transaction transaction) {
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
                Text(
                  '${transaction.category} • ${_formatDate(transaction.transactionDate)}',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            transaction.formattedAmount,
            style: TextStyle(
              color: transaction.isExpense ? Colors.red[400] : Colors.green[400],
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Map<String, double> _getCategoryTotals() {
    final Map<String, double> categoryTotals = {};
    
    for (final transaction in _transactions) {
      if (transaction.isExpense && !transaction.isTransfer) {
        categoryTotals[transaction.category] =
            (categoryTotals[transaction.category] ?? 0) + transaction.amount;
      }
    }
    
    // Sort by amount descending
    final sortedEntries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return Map.fromEntries(sortedEntries);
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
}
