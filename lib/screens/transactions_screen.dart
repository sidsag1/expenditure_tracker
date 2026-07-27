import 'dart:async';
import 'package:flutter/material.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../database/transaction_dao.dart';
import '../database/category_dao.dart';
import '../models/category.dart';
import '../utils/constants.dart';
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
  
  // Pagination
  final ScrollController _scrollController = ScrollController();
  int _offset = 0;
  final int _limit = AppConstants.defaultPageSize;
  bool _hasMore = true;
  bool _isFetchingMore = false;
  
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !_isFetchingMore &&
        _hasMore) {
      _loadMoreTransactions();
    }
  }

  Future<void> _loadData() async {
    if (_isFetchingMore) return; // Sequence guard: don't reload while paginating
    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _offset = 0;
        _hasMore = true;
        _transactions = [];
      });

      // Load categories
      final categories = await _categoryDAO.getAllCategories();
      if (!mounted) return;
      _categories = categories;

      // Load initial transactions
      await _fetchTransactions();

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load transactions: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreTransactions() async {
    if (_isFetchingMore || !_hasMore) return;
    
    setState(() {
      _isFetchingMore = true;
    });
    
    try {
      _offset += _limit;
      await _fetchTransactions();
    } catch (e) {
      // Ignore load more errors
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingMore = false;
        });
      }
    }
  }

  Future<void> _fetchTransactions() async {
    final dateRange = _dateRangeBounds();
    final newTxns = await _transactionDAO.getPaginatedTransactions(
      accountId: widget.account?.id,
      category: _selectedCategory,
      startDate: dateRange?.$1,
      endDate: dateRange?.$2,
      searchQuery: _searchQuery,
      limit: _limit,
      offset: _offset,
    );

    if (!mounted) return;
    setState(() {
      _transactions.addAll(newTxns);
      if (newTxns.length < _limit) {
        _hasMore = false;
      }
    });
  }

  (DateTime, DateTime)? _dateRangeBounds() {
    final now = DateTime.now();

    switch (_selectedDateRange) {
      case 'today':
        return (
          DateTime(now.year, now.month, now.day),
          DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
        );
      case 'week':
        return (
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
          DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
        );
      case 'month':
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 1),
        );
      case 'year':
        return (
          DateTime(now.year, 1, 1),
          DateTime(now.year + 1, 1, 1),
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
                          _loadData();
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
                          _loadData();
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
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _transactions.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _transactions.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: Colors.blue),
              ),
            );
          }
          final transaction = _transactions[index];
          return _buildTransactionCard(transaction);
        },
      ),
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    // Transfer legs move the user's own money rather than earning or spending
    // it, so they're coloured apart from the rows that feed the income/expense
    // totals rather than reading as an ordinary credit. See
    // AccountDetailScreen for the same treatment.
    //
    // Whether one counts as income depends on which account is on screen: a
    // card's own summary folds incoming bill payments into its Total Income,
    // while every cross-account total leaves them out. Unfiltered, this list
    // spans both, so it only makes the promise when scoped to the card it
    // holds for.
    final isTransfer = transaction.isTransfer;
    final amountColor = isTransfer
        ? Colors.blue[300]!
        : (transaction.isExpense ? Colors.red[400]! : Colors.green[400]!);
    final transferNote = widget.account?.accountType == 'credit_card' &&
            !transaction.isExpense
        ? 'Transfer • counted as income on this card'
        : 'Transfer • not counted as income';

    return Card(
      color: const Color(0xFF1a1a2e),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () => _editTransaction(transaction),
        contentPadding: const EdgeInsets.all(16),
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
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${_formatDate(transaction.transactionDate)} • '
              '${isTransfer ? transferNote : transaction.category}',
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
                color: amountColor,
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
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _loadData();
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
      _loadData();
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
                  _loadData();
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
      _loadData();
    }
  }
}
