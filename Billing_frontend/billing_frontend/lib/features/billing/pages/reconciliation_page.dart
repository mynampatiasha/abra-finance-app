// ============================================================================
// RECONCILIATION PAGE - Bank/Provider Transaction Matching
// ============================================================================
// File: lib/screens/banking/reconciliation_page.dart
// Features:
// - Side-by-side comparison of Provider vs System transactions
// - Auto-matching algorithm
// - Manual matching capability
// - Variance analysis
// - Mark as reconciled functionality
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ReconciliationPage extends StatefulWidget {
  final String accountId;
  final String accountName;
  final String accountType;

  const ReconciliationPage({
    Key? key,
    required this.accountId,
    required this.accountName,
    required this.accountType,
  }) : super(key: key);

  @override
  State<ReconciliationPage> createState() => _ReconciliationPageState();
}

class _ReconciliationPageState extends State<ReconciliationPage> {
  bool _isLoading = false;
  bool _isMatching = false;

  // Balances
  double _providerBalance = 0;
  double _systemBalance = 0;

  // Transactions
  List<ProviderTransaction> _providerTransactions = [];
  List<SystemExpense> _systemExpenses = [];

  // Filters
  String _selectedFilter = 'All';
  final List<String> _filterOptions = ['All', 'Matched', 'Unmatched', 'Pending'];

  // Date range
  DateTime? _fromDate;
  DateTime? _toDate;

  // Statistics
  int _totalMatched = 0;
  int _totalUnmatched = 0;
  double _totalVariance = 0;

  // Selected items for manual matching
  String? _selectedProviderTxnId;
  String? _selectedSystemExpenseId;

  @override
  void initState() {
    super.initState();
    _loadReconciliationData();
  }

  Future<void> _loadReconciliationData() async {
    setState(() => _isLoading = true);

    try {
      // TODO: Replace with actual API calls
      await Future.delayed(const Duration(seconds: 1));

      setState(() {
        // Mock data - Provider Transactions
        _providerTransactions = [
          ProviderTransaction(
            id: 'p1',
            date: DateTime(2026, 1, 22),
            amount: 800.00,
            location: 'Shell Marathahalli',
            description: 'Fuel Purchase',
            cardNumber: 'xxxx-5678',
            vehicleNumber: null,
            status: 'UNMATCHED',
            matchedExpenseId: null,
            confidence: null,
          ),
          ProviderTransaction(
            id: 'p2',
            date: DateTime(2026, 1, 23),
            amount: 1200.00,
            location: 'HP Whitefield',
            description: 'Fuel Purchase',
            cardNumber: 'xxxx-5678',
            vehicleNumber: null,
            status: 'MATCHED',
            matchedExpenseId: 's2',
            confidence: 100,
          ),
          ProviderTransaction(
            id: 'p3',
            date: DateTime(2026, 1, 24),
            amount: 950.00,
            location: 'Shell Koramangala',
            description: 'Fuel Purchase',
            cardNumber: 'xxxx-5678',
            vehicleNumber: null,
            status: 'UNMATCHED',
            matchedExpenseId: null,
            confidence: null,
          ),
          ProviderTransaction(
            id: 'p4',
            date: DateTime(2026, 1, 25),
            amount: 1100.00,
            location: 'HP Electronic City',
            description: 'Fuel Purchase',
            cardNumber: 'xxxx-5678',
            vehicleNumber: null,
            status: 'UNMATCHED',
            matchedExpenseId: null,
            confidence: null,
          ),
          ProviderTransaction(
            id: 'p5',
            date: DateTime(2026, 1, 26),
            amount: 600.00,
            location: 'Reliance HSR Layout',
            description: 'Fuel Purchase',
            cardNumber: 'xxxx-5678',
            vehicleNumber: null,
            status: 'PENDING',
            matchedExpenseId: 's4',
            confidence: 75,
          ),
        ];

        // Mock data - System Expenses
        _systemExpenses = [
          SystemExpense(
            id: 's1',
            date: DateTime(2026, 1, 22),
            amount: 800.00,
            vehicleNumber: 'KA-01-AB-1234',
            description: 'Fuel expense',
            expenseAccount: 'Fuel Expenses',
            isMatched: false,
            matchedProviderTxnId: null,
          ),
          SystemExpense(
            id: 's2',
            date: DateTime(2026, 1, 23),
            amount: 1200.00,
            vehicleNumber: 'KA-05-CD-5678',
            description: 'Fuel expense',
            expenseAccount: 'Fuel Expenses',
            isMatched: true,
            matchedProviderTxnId: 'p2',
          ),
          SystemExpense(
            id: 's3',
            date: DateTime(2026, 1, 24),
            amount: 650.00,
            vehicleNumber: 'KA-01-AB-1234',
            description: 'Fuel expense',
            expenseAccount: 'Fuel Expenses',
            isMatched: false,
            matchedProviderTxnId: null,
          ),
          SystemExpense(
            id: 's4',
            date: DateTime(2026, 1, 26),
            amount: 600.00,
            vehicleNumber: 'KA-05-CD-5678',
            description: 'Fuel expense',
            expenseAccount: 'Fuel Expenses',
            isMatched: false,
            matchedProviderTxnId: null,
          ),
        ];

        // Calculate balances
        _providerBalance = _providerTransactions.fold(
            0, (sum, txn) => sum + txn.amount);
        _systemBalance = _systemExpenses.fold(0, (sum, exp) => sum + exp.amount);

        // Calculate statistics
        _calculateStatistics();

        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to load reconciliation data: $e');
    }
  }

  void _calculateStatistics() {
    _totalMatched =
        _providerTransactions.where((t) => t.status == 'MATCHED').length;
    _totalUnmatched =
        _providerTransactions.where((t) => t.status == 'UNMATCHED').length;
    _totalVariance = (_providerBalance - _systemBalance).abs();
  }

  List<ProviderTransaction> get _filteredProviderTransactions {
    if (_selectedFilter == 'All') return _providerTransactions;
    if (_selectedFilter == 'Matched') {
      return _providerTransactions.where((t) => t.status == 'MATCHED').toList();
    }
    if (_selectedFilter == 'Unmatched') {
      return _providerTransactions
          .where((t) => t.status == 'UNMATCHED')
          .toList();
    }
    if (_selectedFilter == 'Pending') {
      return _providerTransactions.where((t) => t.status == 'PENDING').toList();
    }
    return _providerTransactions;
  }

  List<SystemExpense> get _filteredSystemExpenses {
    if (_selectedFilter == 'All') return _systemExpenses;
    if (_selectedFilter == 'Matched') {
      return _systemExpenses.where((e) => e.isMatched).toList();
    }
    if (_selectedFilter == 'Unmatched') {
      return _systemExpenses.where((e) => !e.isMatched).toList();
    }
    return _systemExpenses;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildBalanceSummary(),
                _buildFiltersBar(),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildProviderTransactionsList()),
                      Container(
                        width: 60,
                        color: Colors.grey[100],
                        child: _buildMatchingArrows(),
                      ),
                      Expanded(child: _buildSystemExpensesList()),
                    ],
                  ),
                ),
                _buildActionBar(),
              ],
            ),
    );
  }

  // ============================================================================
  // APP BAR
  // ============================================================================

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF2C3E50),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reconciliation',
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
          Text(
            widget.accountName,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: _loadReconciliationData,
          tooltip: 'Refresh',
        ),
        IconButton(
          icon: const Icon(Icons.date_range, color: Colors.white),
          onPressed: _showDateRangePicker,
          tooltip: 'Select Date Range',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  // ============================================================================
  // BALANCE SUMMARY
  // ============================================================================

  Widget _buildBalanceSummary() {
    final difference = _providerBalance - _systemBalance;
    final isBalanced = difference.abs() < 0.01; // Within 1 paisa tolerance

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildBalanceCard(
                  'Provider Balance',
                  _providerBalance,
                  Icons.account_balance,
                  Colors.blue,
                  '${_providerTransactions.length} transactions',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildBalanceCard(
                  'System Balance',
                  _systemBalance,
                  Icons.receipt_long,
                  Colors.green,
                  '${_systemExpenses.length} expenses',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildBalanceCard(
                  'Difference',
                  difference.abs(),
                  isBalanced ? Icons.check_circle : Icons.warning,
                  isBalanced ? Colors.green : Colors.red,
                  isBalanced ? 'Balanced ✓' : 'Needs attention',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Statistics Row
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Matched', _totalMatched, Colors.green),
                _buildStatDivider(),
                _buildStatItem('Unmatched', _totalUnmatched, Colors.orange),
                _buildStatDivider(),
                _buildStatItem(
                  'Pending',
                  _providerTransactions
                      .where((t) => t.status == 'PENDING')
                      .length,
                  Colors.blue,
                ),
                _buildStatDivider(),
                _buildStatItem('Variance', _totalVariance, Colors.red,
                    isAmount: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(
    String label,
    double amount,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const Spacer(),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, dynamic value, Color color,
      {bool isAmount = false}) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isAmount
              ? '₹${(value as double).toStringAsFixed(2)}'
              : value.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    return Container(
      height: 40,
      width: 1,
      color: Colors.grey[300],
    );
  }

  // ============================================================================
  // FILTERS BAR
  // ============================================================================

  Widget _buildFiltersBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          const Text(
            'Filter:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C3E50),
            ),
          ),
          const SizedBox(width: 12),
          ..._filterOptions.map((filter) {
            final isSelected = _selectedFilter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
                backgroundColor: Colors.grey[100],
                selectedColor: const Color(0xFF3498DB).withOpacity(0.2),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? const Color(0xFF3498DB)
                      : Colors.grey[700],
                ),
              ),
            );
          }).toList(),
          const Spacer(),
          if (_fromDate != null && _toDate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.date_range, size: 16, color: Colors.blue[700]),
                  const SizedBox(width: 6),
                  Text(
                    '${DateFormat('dd/MM').format(_fromDate!)} - ${DateFormat('dd/MM').format(_toDate!)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[900],
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                      });
                    },
                    child: Icon(Icons.close, size: 16, color: Colors.blue[700]),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================================
  // PROVIDER TRANSACTIONS LIST (LEFT SIDE)
  // ============================================================================

  Widget _buildProviderTransactionsList() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[700],
              border: Border(
                bottom: BorderSide(color: Colors.blue[800]!),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Provider Transactions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_filteredProviderTransactions.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: _filteredProviderTransactions.isEmpty
                ? _buildEmptyState('No provider transactions')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredProviderTransactions.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final transaction = _filteredProviderTransactions[index];
                      return _buildProviderTransactionCard(transaction);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderTransactionCard(ProviderTransaction transaction) {
    final isSelected = _selectedProviderTxnId == transaction.id;
    final isMatched = transaction.status == 'MATCHED';
    final isPending = transaction.status == 'PENDING';

    Color statusColor;
    if (isMatched) {
      statusColor = Colors.green;
    } else if (isPending) {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.grey;
    }

    return InkWell(
      onTap: () {
        if (!isMatched) {
          setState(() {
            _selectedProviderTxnId =
                isSelected ? null : transaction.id;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue[50]
              : (isMatched ? Colors.green[50] : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3498DB)
                : (isMatched ? Colors.green[200]! : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd MMM yyyy').format(transaction.date),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isMatched
                                      ? Icons.check_circle
                                      : (isPending
                                          ? Icons.pending
                                          : Icons.circle_outlined),
                                  size: 12,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  transaction.status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₹${transaction.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        transaction.location ?? 'No location',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (transaction.cardNumber != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Card: ${transaction.cardNumber}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (isPending && transaction.confidence != null) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.psychology, size: 14, color: Colors.orange[700]),
                  const SizedBox(width: 6),
                  Text(
                    'Auto-match confidence: ${transaction.confidence}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[700],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _acceptMatch(transaction),
                    child: const Text('Accept', style: TextStyle(fontSize: 11)),
                  ),
                  TextButton(
                    onPressed: () => _rejectMatch(transaction),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Reject', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
            if (isMatched) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link, size: 14, color: Colors.green[700]),
                  const SizedBox(width: 6),
                  Text(
                    'Matched with system expense',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _unmatchTransaction(transaction),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Unmatch', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // SYSTEM EXPENSES LIST (RIGHT SIDE)
  // ============================================================================

  Widget _buildSystemExpensesList() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[700],
              border: Border(
                bottom: BorderSide(color: Colors.green[800]!),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'System Expenses',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_filteredSystemExpenses.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: _filteredSystemExpenses.isEmpty
                ? _buildEmptyState('No system expenses')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredSystemExpenses.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final expense = _filteredSystemExpenses[index];
                      return _buildSystemExpenseCard(expense);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemExpenseCard(SystemExpense expense) {
    final isSelected = _selectedSystemExpenseId == expense.id;
    final isMatched = expense.isMatched;

    return InkWell(
      onTap: () {
        if (!isMatched) {
          setState(() {
            _selectedSystemExpenseId =
                isSelected ? null : expense.id;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.green[50]
              : (isMatched ? Colors.green[50] : Colors.white),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF27AE60)
                : (isMatched ? Colors.green[200]! : Colors.grey[300]!),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd MMM yyyy').format(expense.date),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          const Spacer(),
                          if (isMatched)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle,
                                      size: 12, color: Colors.green[700]),
                                  const SizedBox(width: 4),
                                  Text(
                                    'MATCHED',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₹${expense.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (expense.vehicleNumber != null)
                        Row(
                          children: [
                            Icon(Icons.directions_car,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 6),
                            Text(
                              expense.vehicleNumber!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      if (expense.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          expense.description!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (isMatched) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.link, size: 14, color: Colors.green[700]),
                  const SizedBox(width: 6),
                  Text(
                    'Matched with provider transaction',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
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

  // ============================================================================
  // MATCHING ARROWS (CENTER)
  // ============================================================================

  Widget _buildMatchingArrows() {
    final canMatch = _selectedProviderTxnId != null &&
        _selectedSystemExpenseId != null;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (canMatch)
            ElevatedButton(
              onPressed: _performManualMatch,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3498DB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
                shape: const CircleBorder(),
              ),
              child: const Icon(Icons.compare_arrows, size: 28),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.compare_arrows,
                  size: 28, color: Colors.grey[500]),
            ),
          const SizedBox(height: 12),
          Text(
            canMatch ? 'Match' : 'Select\nboth',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: canMatch ? const Color(0xFF3498DB) : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // ACTION BAR
  // ============================================================================

  Widget _buildActionBar() {
    final isFullyReconciled = _totalUnmatched == 0 &&
        _providerTransactions
                .where((t) => t.status == 'PENDING')
                .isEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Info text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isFullyReconciled
                      ? '✓ All transactions reconciled'
                      : 'Reconciliation in progress',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isFullyReconciled
                        ? Colors.green[700]
                        : Colors.orange[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isFullyReconciled
                      ? 'Ready to finalize reconciliation'
                      : '$_totalUnmatched unmatched transactions remaining',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),

          // Actions
          ElevatedButton.icon(
            onPressed: _isMatching ? null : _performAutoMatch,
            icon: _isMatching
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.auto_fix_high),
            label: Text(_isMatching ? 'Matching...' : 'Auto-Match All'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: isFullyReconciled ? _markAsReconciled : null,
            icon: const Icon(Icons.check_circle),
            label: const Text('Mark as Reconciled'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // HELPER WIDGETS
  // ============================================================================

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // ACTIONS
  // ============================================================================

  void _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _loadReconciliationData(); // Reload with date filter
    }
  }

  Future<void> _performAutoMatch() async {
    setState(() => _isMatching = true);

    try {
      // TODO: Call backend auto-match API
      await Future.delayed(const Duration(seconds: 2));

      // Mock: Auto-match some transactions
      setState(() {
        // Example: Mark first unmatched as pending with 80% confidence
        final unmatchedProvider = _providerTransactions
            .firstWhere((t) => t.status == 'UNMATCHED', orElse: () => _providerTransactions.first);
        unmatchedProvider.status = 'PENDING';
        unmatchedProvider.confidence = 80;

        _calculateStatistics();
        _isMatching = false;
      });

      _showSuccessSnackbar('Auto-match completed. Review pending matches.');
    } catch (e) {
      setState(() => _isMatching = false);
      _showErrorSnackbar('Auto-match failed: $e');
    }
  }

  void _performManualMatch() {
    if (_selectedProviderTxnId == null || _selectedSystemExpenseId == null) {
      return;
    }

    // TODO: Call backend manual match API
    setState(() {
      final providerTxn = _providerTransactions
          .firstWhere((t) => t.id == _selectedProviderTxnId);
      final systemExp = _systemExpenses
          .firstWhere((e) => e.id == _selectedSystemExpenseId);

      providerTxn.status = 'MATCHED';
      providerTxn.matchedExpenseId = systemExp.id;
      systemExp.isMatched = true;
      systemExp.matchedProviderTxnId = providerTxn.id;

      _selectedProviderTxnId = null;
      _selectedSystemExpenseId = null;

      _calculateStatistics();
    });

    _showSuccessSnackbar('Transactions matched successfully');
  }

  void _acceptMatch(ProviderTransaction transaction) {
    // TODO: Call backend accept match API
    setState(() {
      transaction.status = 'MATCHED';
      final matchedExpense = _systemExpenses
          .firstWhere((e) => e.id == transaction.matchedExpenseId);
      matchedExpense.isMatched = true;

      _calculateStatistics();
    });

    _showSuccessSnackbar('Match accepted');
  }

  void _rejectMatch(ProviderTransaction transaction) {
    // TODO: Call backend reject match API
    setState(() {
      transaction.status = 'UNMATCHED';
      transaction.matchedExpenseId = null;
      transaction.confidence = null;

      _calculateStatistics();
    });

    _showSuccessSnackbar('Match rejected');
  }

  void _unmatchTransaction(ProviderTransaction transaction) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unmatch Transaction'),
        content: const Text(
            'Are you sure you want to unmatch this transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: Call backend unmatch API
              setState(() {
                final matchedExpense = _systemExpenses.firstWhere(
                    (e) => e.id == transaction.matchedExpenseId);
                matchedExpense.isMatched = false;
                matchedExpense.matchedProviderTxnId = null;

                transaction.status = 'UNMATCHED';
                transaction.matchedExpenseId = null;

                _calculateStatistics();
              });

              Navigator.pop(context);
              _showSuccessSnackbar('Transaction unmatched');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Unmatch'),
          ),
        ],
      ),
    );
  }

  Future<void> _markAsReconciled() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Reconciled'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will finalize the reconciliation for this period.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber,
                          color: Colors.orange[700], size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Warning',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• This period will be locked\n'
                    '• No further edits allowed\n'
                    '• Reconciliation report will be generated',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // TODO: Call backend mark as reconciled API
              await Future.delayed(const Duration(seconds: 1));
              Navigator.pop(context, true);
              _showSuccessSnackbar('Reconciliation completed successfully!');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ============================================================================
// MODELS
// ============================================================================

class ProviderTransaction {
  final String id;
  final DateTime date;
  final double amount;
  final String? location;
  final String? description;
  final String? cardNumber;
  final String? vehicleNumber;
  String status; // MATCHED, UNMATCHED, PENDING
  String? matchedExpenseId;
  int? confidence; // 0-100

  ProviderTransaction({
    required this.id,
    required this.date,
    required this.amount,
    this.location,
    this.description,
    this.cardNumber,
    this.vehicleNumber,
    required this.status,
    this.matchedExpenseId,
    this.confidence,
  });
}

class SystemExpense {
  final String id;
  final DateTime date;
  final double amount;
  final String? vehicleNumber;
  final String? description;
  final String expenseAccount;
  bool isMatched;
  String? matchedProviderTxnId;

  SystemExpense({
    required this.id,
    required this.date,
    required this.amount,
    this.vehicleNumber,
    this.description,
    required this.expenseAccount,
    required this.isMatched,
    this.matchedProviderTxnId,
  });
}