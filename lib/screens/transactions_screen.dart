import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../database/transaction_dao.dart';
import '../database/category_dao.dart';
import '../models/category.dart';
import 'add_transaction_screen.dart';

class TransactionsScreen extends StatefulWidget {
  // When set, only this account's transactions are shown
  final Account? account;

  const TransactionsScreen({super.key, this.account});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final TransactionDAO _transactionDAO = TransactionDAO();
  final CategoryDAO _categoryDAO = CategoryDAO();
  
  List<Transaction> _transactions = [];
  List<Category> _categories = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _selectedCategory = 'all';
  String _selectedDateRange = 'all'; // 'all', 'today', 'week', 'month', 'year'
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      // Load categories
      _categories = await _categoryDAO.getAllCategories();
      
      // Load transactions based on filters
      await _loadTransactions();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load transactions: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTransactions() async {
    // Base list: everything, or just the selected account's transactions
    var transactions = widget.account != null
        ? await _transactionDAO.getTransactionsByAccount(widget.account!.id!)
        : await _transactionDAO.getAllTransactions();

    // Apply the remaining filters in memory so they combine correctly
    final dateRange = _dateRangeBounds();
    if (dateRange != null) {
      transactions = transactions
          .where((t) =>
              !t.transactionDate.isBefore(dateRange.$1) &&
              !t.transactionDate.isAfter(dateRange.$2))
          .toList();
    }
    if (_selectedCategory != 'all') {
      transactions =
          transactions.where((t) => t.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      transactions = transactions
          .where((t) =>
              t.description.toLowerCase().contains(query) ||
              (t.merchant ?? '').toLowerCase().contains(query) ||
              t.amount.toString().contains(query))
          .toList();
    }

    setState(() {
      _transactions = transactions;
    });
  }

  (DateTime, DateTime)? _dateRangeBounds() {
    final now = DateTime.now();

    switch (_selectedDateRange) {
      case 'today':
        return (
          DateTime(now.year, now.month, now.day),
          DateTime(now.year, now.month, now.day, 23, 59, 59),
        );
      case 'week':
        return (now.subtract(const Duration(days: 7)), now);
      case 'month':
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
      case 'year':
        return (
          DateTime(now.year, 1, 1),
          DateTime(now.year, 12, 31, 23, 59, 59),
        );
      default:
        return null;
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
          widget.account != null
              ? '${widget.account!.accountName} Transactions'
              : 'Transactions',
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          _buildFilters(),
          
          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addManualTransaction,
        backgroundColor: Colors.blue[400],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        border: Border(bottom: BorderSide(color: Colors.grey[800]!)),
      ),
      child: Column(
        children: [
          // Search bar
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search transactions...',
              hintStyle: TextStyle(color: Colors.grey[600]),
              prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
              filled: true,
              fillColor: const Color(0xFF0f0f23),
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
                borderSide: BorderSide(color: Colors.blue[400]!),
              ),
            ),
            onChanged: (value) {
              _searchQuery = value;
              _debouncedSearch();
            },
          ),
          
          const SizedBox(height: 16),
          
          // Category and Date filters
          Row(
            children: [
              // Category filter
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f0f23),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[700]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton(
                      value: _selectedCategory,
                      style: const TextStyle(color: Colors.white),
                      dropdownColor: const Color(0xFF1a1a2e),
                      icon: Icon(Icons.category, color: Colors.grey[400]),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All Categories')),
                        ..._categories.map((category) => DropdownMenuItem(
                          value: category.name,
                          child: Row(
                            children: [
                              Text(category.icon),
                              const SizedBox(width: 8),
                              Text(category.name),
                            ],
                          ),
                        )),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedCategory = value;
                          });
                          _loadTransactions();
                        }
                      },
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Date range filter
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0f0f23),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[700]!),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton(
                      value: _selectedDateRange,
                      style: const TextStyle(color: Colors.white),
                      dropdownColor: const Color(0xFF1a1a2e),
                      icon: Icon(Icons.date_range, color: Colors.grey[400]),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Time')),
                        DropdownMenuItem(value: 'today', child: Text('Today')),
                        DropdownMenuItem(value: 'week', child: Text('This Week')),
                        DropdownMenuItem(value: 'month', child: Text('This Month')),
                        DropdownMenuItem(value: 'year', child: Text('This Year')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedDateRange = value;
                          });
                          _loadTransactions();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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

    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 64,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 16),
            Text(
              'No transactions found',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your filters or add a manual transaction',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: Colors.blue[400],
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _transactions.length,
        itemBuilder: (context, index) {
          final transaction = _transactions[index];
          return _buildTransactionCard(transaction);
        },
      ),
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    return Card(
      color: const Color(0xFF1a1a2e),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () => _editTransaction(transaction),
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: transaction.isExpense 
            ? Colors.red[400]!.withValues(alpha: 0.2)
            : Colors.green[400]!.withValues(alpha: 0.2),
          child: Icon(
            transaction.isExpense ? Icons.remove : Icons.add,
            color: transaction.isExpense ? Colors.red[400] : Colors.green[400],
          ),
        ),
        title: Text(
          transaction.description,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${_formatDate(transaction.transactionDate)} • ${transaction.category}',
              style: TextStyle(color: Colors.grey[400]),
            ),
            if (transaction.merchant != null && transaction.merchant!.isNotEmpty)
              Text(
                transaction.merchant!,
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
              transaction.formattedAmount,
              style: TextStyle(
                color: transaction.isExpense ? Colors.red[400] : Colors.green[400],
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 20),
              color: Colors.transparent,
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Colors.grey[400], size: 16),
                      const SizedBox(width: 8),
                      const Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red[400], size: 16),
                      const SizedBox(width: 8),
                      const Text('Delete'),
                    ],
                  ),
                ),
              ],
              onSelected: (value) => _handleTransactionAction(transaction, value),
            ),
          ],
        ),
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
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _debouncedSearch() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _loadTransactions();
      }
    });
  }

  void _handleTransactionAction(Transaction transaction, String? action) {
    switch (action) {
      case 'edit':
        _editTransaction(transaction);
        break;
      case 'delete':
        _deleteTransaction(transaction);
        break;
    }
  }

  Future<void> _editTransaction(Transaction transaction) async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTransactionScreen(transaction: transaction),
      ),
    );
    if (updated == true) {
      _loadTransactions();
    }
  }

  void _deleteTransaction(Transaction transaction) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text(
          'Delete Transaction',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete this transaction?\n\n${transaction.description}\n${transaction.formattedAmount}',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              try {
                await _transactionDAO.deleteTransaction(transaction.id!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Transaction deleted'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadTransactions();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete transaction: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _addManualTransaction() async {
    final added = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddTransactionScreen(),
      ),
    );
    if (added == true) {
      _loadTransactions();
    }
  }
}
