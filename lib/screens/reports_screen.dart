import 'package:flutter/material.dart';
import '../database/transaction_dao.dart';
import '../models/transaction.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/formatters.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final TransactionDAO _transactionDAO = TransactionDAO();
  
  List<Transaction> _transactions = [];
  double _totalIncome = 0.0;
  double _totalExpenses = 0.0;
  Map<String, double> _categoryTotals = {};
  // Sorted descending by amount once per data load, not on every build() --
  // _buildPieChart used to re-sort categoryTotals.entries.toList() itself on
  // every rebuild.
  List<MapEntry<String, double>> _sortedCategoryEntries = [];
  Map<String, double> _monthlyTotals = {};
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
      if (!mounted) return;
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

      final results = await Future.wait([
        _transactionDAO.getTotalIncome(startDate: startDate),
        _transactionDAO.getTotalExpenses(startDate: startDate),
        _transactionDAO.getSpendingByCategory(startDate: startDate),
        // Only the 5 most recent are ever shown (_buildTrendsList /
        // _buildRecentTransactionsSummary both slice to 5) -- fetching every
        // transaction in the period just to throw away all but 5 pulls the
        // whole period into memory and onto the main thread for nothing.
        _transactionDAO.getTransactionsByDateRange(startDate, now, limit: 5),
        _transactionDAO.getMonthlySpending(months: 6),
      ]);

      if (!mounted) return;
      final categoryTotals = results[2] as Map<String, double>;
      setState(() {
        _totalIncome = results[0] as double;
        _totalExpenses = results[1] as double;
        _categoryTotals = categoryTotals;
        _sortedCategoryEntries = categoryTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        _transactions = results[3] as List<Transaction>;
        _monthlyTotals = results[4] as Map<String, double>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
            _buildSummaryCards(_totalIncome, _totalExpenses),
            
            const SizedBox(height: 24),
            
            // Category breakdown
            _buildCategoryBreakdown(_categoryTotals),
            
            const SizedBox(height: 24),
            
            // Monthly Trends Chart
            _buildMonthlyTrends(),
            
            const SizedBox(height: 24),
            
            // Transaction trends list
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
            else ...[
              _buildPieChart(categoryTotals),
              const SizedBox(height: 24),
              ...categoryTotals.entries.map((entry) => _buildCategoryItem(entry.key, entry.value)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(Map<String, double> categoryTotals) {
    if (_totalExpenses <= 0) return const SizedBox();

    // Sorted once in _loadReportsData; take top 5 here, group rest into 'Other'.
    final sortedEntries = _sortedCategoryEntries;

    final List<PieChartSectionData> sections = [];
    final colors = [
      Colors.blue[400]!,
      Colors.red[400]!,
      Colors.green[400]!,
      Colors.orange[400]!,
      Colors.purple[400]!,
      Colors.teal[400]!,
    ];
    
    double otherAmount = 0;
    for (int i = 0; i < sortedEntries.length; i++) {
      if (i < 5) {
        final percentage = (sortedEntries[i].value / _totalExpenses) * 100;
        sections.add(PieChartSectionData(
          color: colors[i % colors.length],
          value: sortedEntries[i].value,
          title: '${percentage.toStringAsFixed(0)}%',
          radius: 50,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ));
      } else {
        otherAmount += sortedEntries[i].value;
      }
    }
    
    if (otherAmount > 0) {
      final percentage = (otherAmount / _totalExpenses) * 100;
      sections.add(PieChartSectionData(
        color: colors[5],
        value: otherAmount,
        title: '${percentage.toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ));
    }

    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 40,
          sections: sections,
        ),
      ),
    );
  }

  Widget _buildMonthlyTrends() {
    return Card(
      color: const Color(0xFF1a1a2e),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monthly Trends (Last 6 Months)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            if (_monthlyTotals.isEmpty)
              _buildEmptyState('No data for monthly trends')
            else ...[
              Builder(
                builder: (context) {
                  final maxValue = _monthlyTotals.values.isEmpty 
                      ? 0.0 
                      : _monthlyTotals.values.reduce((a, b) => a > b ? a : b);
                  final maxY = maxValue > 0 ? maxValue * 1.2 : 100.0;
                  final horizontalInterval = maxValue > 0 ? (maxValue / 4).ceilToDouble() : 25.0;
                  
                  return SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxY,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(
                            formatINR(rod.toY),
                            const TextStyle(color: Colors.white),
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index >= 0 && index < _monthlyTotals.keys.length) {
                              final key = _monthlyTotals.keys.elementAt(index);
                              // Format YYYY-MM to short month (e.g. Jan)
                              final parts = key.split('-');
                              if (parts.length == 2) {
                                final month = int.tryParse(parts[1]) ?? 1;
                                const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    monthNames[month - 1],
                                    style: TextStyle(color: Colors.grey[400], fontSize: 10),
                                  ),
                                );
                              }
                            }
                            return const SizedBox();
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (value, meta) {
                            if (value == 0) return const SizedBox();
                            return Text(
                              '${(value / 1000).toStringAsFixed(0)}k',
                              style: TextStyle(color: Colors.grey[400], fontSize: 10),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: horizontalInterval == 0 ? 1 : horizontalInterval,
                      getDrawingHorizontalLine: (value) {
                        return const FlLine(
                          color: Colors.white10,
                          strokeWidth: 1,
                        );
                      },
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: _monthlyTotals.entries.toList().asMap().entries.map((entry) {
                      return BarChartGroupData(
                        x: entry.key,
                        barRods: [
                          BarChartRodData(
                            toY: entry.value.value,
                            color: Colors.blue[400],
                            width: 16,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryItem(String category, double amount) {
    final percentage = _totalExpenses > 0 ? (amount / _totalExpenses) * 100 : 0.0;

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
            if (_transactions.isEmpty)
              _buildEmptyState('No transactions for trends')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _transactions.length > 5 ? 5 : _transactions.length,
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
