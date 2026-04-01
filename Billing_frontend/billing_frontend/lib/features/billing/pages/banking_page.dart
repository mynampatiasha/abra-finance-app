// ============================================================================
// FLEET BANKING DASHBOARD — CLEAN VERSION
// ============================================================================
// File: lib/screens/banking/banking_dashboard.dart
// Changes vs previous version:
//   ✅ Expense Trends section completely removed
//   ✅ Back arrow removed from top bar
//   ✅ backgroundColor = Colors.white (no grey/dim/pinkish overlay)
//   ✅ All dialog backgrounds explicitly set to Colors.white
//   ✅ fl_chart import removed (no longer needed)
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../app_top_bar.dart';
import 'add_account_dialog.dart';
import 'import_transactions_dialog.dart';
import 'reconciliation_billing.dart';
import '../../../core/services/add_account_service.dart';

// ─── colour palette ───────────────────────────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF16A085);
const Color _indigo = Color(0xFF3F51B5);

// ============================================================================
// MODELS
// ============================================================================

class AccountTypeSummary {
  final String accountType;
  final String displayName;
  final IconData icon;
  final Color color;
  final double totalBalance;
  final int accountCount;
  final List<String> accountIds;

  AccountTypeSummary({
    required this.accountType,
    required this.displayName,
    required this.icon,
    required this.color,
    required this.totalBalance,
    required this.accountCount,
    required this.accountIds,
  });
}

class FleetAccount {
  final String id;
  final String accountType;
  final String accountName;
  final String? accountDetails;
  final String? holderName;
  final double currentBalance;
  final double openingBalance;
  final bool isActive;
  final DateTime? createdAt;
  final Map<String, dynamic>? typeSpecificFields;
  final Map<String, dynamic>? linkedBankDetails;
  final Map<String, dynamic>? customFields;

  FleetAccount({
    required this.id,
    required this.accountType,
    required this.accountName,
    this.accountDetails,
    this.holderName,
    required this.currentBalance,
    required this.openingBalance,
    required this.isActive,
    this.createdAt,
    this.typeSpecificFields,
    this.linkedBankDetails,
    this.customFields,
  });

  factory FleetAccount.fromJson(Map<String, dynamic> json) {
    String? accountDetails;
    switch (json['accountType']) {
      case 'FUEL_CARD':
        accountDetails = json['typeSpecificFields']?['cardNumber'];
        break;
      case 'BANK':
        accountDetails = json['typeSpecificFields']?['accountNumber'];
        break;
      case 'FASTAG':
        accountDetails = json['typeSpecificFields']?['fastagNumber'];
        break;
    }
    return FleetAccount(
      id: json['_id'] ?? json['id'] ?? '',
      accountType: json['accountType'] ?? '',
      accountName: json['accountName'] ?? '',
      accountDetails: accountDetails,
      holderName: json['holderName'],
      currentBalance: (json['currentBalance'] ?? 0).toDouble(),
      openingBalance: (json['openingBalance'] ?? 0).toDouble(),
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      typeSpecificFields: json['typeSpecificFields'],
      linkedBankDetails: json['linkedBankDetails'],
      customFields: json['customFields'],
    );
  }
}

// ─── stat card helper ─────────────────────────────────────────────────────────
class _StatCardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({
    required this.label, required this.value,
    required this.icon,  required this.color,
    required this.gradientColors,
  });
}

// ============================================================================
// BANKING DASHBOARD PAGE
// ============================================================================

class BankingDashboardPage extends StatefulWidget {
  const BankingDashboardPage({Key? key}) : super(key: key);

  @override
  State<BankingDashboardPage> createState() => _BankingDashboardPageState();
}

class _BankingDashboardPageState extends State<BankingDashboardPage> {
  final AddAccountService _accountService = AddAccountService();

  bool _isLoading = false;
  String? _errorMessage;

  List<FleetAccount> _accounts = [];
  List<AccountTypeSummary> _accountTypeSummaries = [];

  double _totalBalance   = 0;
  int    _activeAccounts = 0;
  int    _totalAccounts  = 0;

  String _selectedPeriod = 'Last 7 Days';
  final List<String> _periodOptions = [
    'Today', 'Last 7 Days', 'Last 30 Days',
    'This Month', 'Last Month', 'Custom Range',
  ];

  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  final Map<String, Map<String, dynamic>> _accountTypeConfig = {
    'FUEL_CARD':      {'displayName': 'Fuel Card',      'icon': Icons.local_gas_station,      'color': _blue},
    'BANK':           {'displayName': 'Bank Account',   'icon': Icons.account_balance,        'color': _green},
    'FASTAG':         {'displayName': 'FASTag',         'icon': Icons.toll,                   'color': _orange},
    'PETTY_CASH':     {'displayName': 'Petty Cash',     'icon': Icons.payments,               'color': _purple},
    'DRIVER_ADVANCE': {'displayName': 'Driver Advance', 'icon': Icons.person,                 'color': _indigo},
    'OTHER':          {'displayName': 'Other',          'icon': Icons.account_balance_wallet, 'color': Colors.grey},
  };

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final data = await _accountService.getAllAccounts();
      setState(() {
        _accounts = data.map((j) => FleetAccount.fromJson(j)).toList();
        _calculateSummaries();
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
      _showError('Failed to load accounts: $e');
    }
  }

  void _calculateSummaries() {
    final grouped = <String, List<FleetAccount>>{};
    _totalBalance = 0; _activeAccounts = 0; _totalAccounts = _accounts.length;
    for (final a in _accounts) {
      grouped.putIfAbsent(a.accountType, () => []).add(a);
      if (a.isActive) { _activeAccounts++; _totalBalance += a.currentBalance; }
    }
    _accountTypeSummaries = [];
    grouped.forEach((type, list) {
      double total = 0;
      final ids = <String>[];
      for (final a in list) { if (a.isActive) total += a.currentBalance; ids.add(a.id); }
      final cfg = _accountTypeConfig[type] ?? _accountTypeConfig['OTHER']!;
      _accountTypeSummaries.add(AccountTypeSummary(
        accountType: type, displayName: cfg['displayName'] ?? type,
        icon: cfg['icon'] ?? Icons.account_balance_wallet,
        color: cfg['color'] ?? Colors.grey,
        totalBalance: total, accountCount: list.length, accountIds: ids,
      ));
    });
    _accountTypeSummaries.sort((a, b) => b.totalBalance.compareTo(a.totalBalance));
  }

  Future<void> _refresh() async { await _loadDashboardData(); _showSuccess('Data refreshed'); }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Banking'),
      backgroundColor: Colors.white,   // ← pure white, no dim
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : _errorMessage != null
              ? _buildErrorState()
              : SingleChildScrollView(
                  child: Column(children: [
                    _buildTopBar(),
                    _buildStatsCards(),
                    _buildAccountsTable(),
                    const SizedBox(height: 32),
                  ]),
                ),
    );
  }

  // ── top bar — NO back arrow ───────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 1100) return _topBarDesktop();
        if (c.maxWidth >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    const Text('Fleet Banking Overview',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
    const SizedBox(width: 16),
    _periodDropdown(),
    const SizedBox(width: 8),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const Spacer(),
    _actionBtn('Add Account',         Icons.add_rounded,  _navy,  _showAddAccountDialog),
    const SizedBox(width: 8),
    _actionBtn('Import Transactions', Icons.upload_file,  _green, _showImportTransactionsDialog),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      const Expanded(child: Text('Fleet Banking Overview',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)))),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _periodDropdown(), const Spacer(),
      _actionBtn('Add Account',         Icons.add_rounded,  _navy,  _showAddAccountDialog),
      const SizedBox(width: 8),
      _actionBtn('Import Transactions', Icons.upload_file,  _green, _showImportTransactionsDialog),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      const Expanded(child: Text('Fleet Banking Overview',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)))),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    ]),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _periodDropdown(), const SizedBox(width: 8),
      _compactBtn('Add Account', _navy,  _showAddAccountDialog), const SizedBox(width: 8),
      _compactBtn('Import',      _green, _showImportTransactionsDialog),
    ])),
  ]);

  Widget _periodDropdown() => Container(
    height: 42, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FC),
      border: Border.all(color: const Color(0xFFDDE3EE)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedPeriod,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
        items: _periodOptions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() => _selectedPeriod = v);
          if (v != 'Custom Range') _loadDashboardData();
          else _showError('Custom date range — coming soon!');
        },
      ),
    ),
  );

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback? onTap) =>
      ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg, foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withOpacity(0.5),
          elevation: 0, minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  Widget _compactBtn(String label, Color bg, VoidCallback? onTap) =>
      ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg, foregroundColor: Colors.white,
          elevation: 0, minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _iconBtn(IconData icon, VoidCallback? onTap,
      {String tooltip = '', Color color = const Color(0xFF7F8C8D), Color bg = const Color(0xFFF1F1F1)}) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.25))),
            child: Icon(icon, size: 20, color: onTap == null ? Colors.grey[300] : color),
          ),
        ),
      );

  // ── stats cards ───────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    final overall = [
      _StatCardData(label: 'Total Balance',    value: '₹${_fmtAmt(_totalBalance)}',    icon: Icons.account_balance_wallet, color: _indigo, gradientColors: const [Color(0xFF5C6BC0), Color(0xFF3F51B5)]),
      _StatCardData(label: 'Active Accounts',  value: '$_activeAccounts of $_totalAccounts', icon: Icons.verified,           color: _teal,   gradientColors: const [Color(0xFF1ABC9C), Color(0xFF16A085)]),
      _StatCardData(label: 'Total Accounts',   value: '$_totalAccounts accounts',       icon: Icons.list_alt,               color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
    ];

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (_, c) {
          if (c.maxWidth < 700) {
            return SingleChildScrollView(
              controller: _statsHScrollCtrl, scrollDirection: Axis.horizontal,
              child: Row(children: overall.asMap().entries.map((e) => Container(
                width: 200, margin: EdgeInsets.only(right: e.key < overall.length - 1 ? 10 : 0),
                child: _buildStatCard(e.value, compact: true),
              )).toList()),
            );
          }
          return Row(children: overall.asMap().entries.map((e) => Expanded(
            child: Padding(padding: EdgeInsets.only(right: e.key < overall.length - 1 ? 10 : 0),
                child: _buildStatCard(e.value, compact: false)),
          )).toList());
        }),

        if (_accountTypeSummaries.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(children: [
            const Text('Balance by Account Type',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
            const SizedBox(width: 8),
            Tooltip(message: 'Tap any card to view and edit accounts of that type',
                child: Icon(Icons.info_outline, size: 16, color: Colors.grey[400])),
          ]),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: _accountTypeSummaries.asMap().entries.map((e) => Padding(
              padding: EdgeInsets.only(right: e.key < _accountTypeSummaries.length - 1 ? 12 : 0),
              child: _buildTypeCard(e.value),
            )).toList()),
          ),
        ],
        const SizedBox(height: 20),
        const Divider(height: 1, color: Color(0xFFEEF2F7)),
      ]),
    );
  }

  Widget _buildStatCard(_StatCardData d, {required bool compact}) {
    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [d.gradientColors[0].withOpacity(0.15), d.gradientColors[1].withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)),
                  child: Icon(d.icon, color: Colors.white, size: 20)),
              const SizedBox(height: 10),
              Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: d.color)),
            ])
          : Row(children: [
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))]),
                  child: Icon(d.icon, color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(d.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: d.color)),
              ])),
            ]),
    );
  }

  Widget _buildTypeCard(AccountTypeSummary s) {
    return InkWell(
      onTap: () => _showAccountTypeDetails(s),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 240, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [s.color.withOpacity(0.12), s.color.withOpacity(0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: s.color.withOpacity(0.25)),
          boxShadow: [BoxShadow(color: s.color.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(gradient: LinearGradient(colors: [s.color.withOpacity(0.85), s.color], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: s.color.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2))]),
                child: Icon(s.icon, size: 20, color: Colors.white)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: s.color.withOpacity(0.3))),
                child: Text('${s.accountCount} ${s.accountCount == 1 ? 'acct' : 'accts'}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: s.color))),
          ]),
          const SizedBox(height: 12),
          Text(s.displayName, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text('₹${_fmtAmt(s.totalBalance)}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: s.color))),
            Icon(Icons.edit, size: 14, color: s.color.withOpacity(0.45)),
          ]),
        ]),
      ),
    );
  }

  String _fmtAmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  // ── account type details dialog ───────────────────────────────────────────

  void _showAccountTypeDetails(AccountTypeSummary summary) {
    final list = _accounts.where((a) => summary.accountIds.contains(a.id)).toList();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 700,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [summary.color.withOpacity(0.85), summary.color]), borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: summary.color.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 3))]),
                  child: Icon(summary.icon, color: Colors.white, size: 22)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(summary.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
                Text('Total: ₹${summary.totalBalance.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, color: summary.color, fontWeight: FontWeight.w600)),
              ])),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Flexible(child: ListView.separated(
              shrinkWrap: true, itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _buildAccountDetailRow(list[i], summary.color, ctx),
            )),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); _showAddAccountDialog(); },
              icon: const Icon(Icons.add),
              label: Text('Add New ${summary.displayName}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: summary.color, foregroundColor: Colors.white, elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _buildAccountDetailRow(FleetAccount account, Color themeColor, BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: themeColor.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(account.accountName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
            if (account.accountDetails != null)
              Text(account.accountDetails!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ])),
          _buildStatusBadge(account.isActive),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _buildBalanceField('Current Balance', account.currentBalance, themeColor,        () => _quickEditBalance(account, 'current', ctx))),
          const SizedBox(width: 12),
          Expanded(child: _buildBalanceField('Opening Balance', account.openingBalance, Colors.grey[600]!, () => _quickEditBalance(account, 'opening', ctx))),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(onPressed: () { Navigator.pop(ctx); _showEditAccountDialog(account); },
              icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Edit'),
              style: TextButton.styleFrom(foregroundColor: _blue)),
          const SizedBox(width: 8),
          TextButton.icon(onPressed: () { Navigator.pop(ctx); _confirmDeleteAccount(account); },
              icon: const Icon(Icons.delete_outline, size: 16), label: const Text('Delete'),
              style: TextButton.styleFrom(foregroundColor: _red)),
        ]),
      ]),
    );
  }

  Widget _buildBalanceField(String label, double amount, Color color, VoidCallback onEdit) {
    return InkWell(
      onTap: onEdit, borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            const Spacer(),
            Icon(Icons.edit, size: 12, color: Colors.grey[400]),
          ]),
          const SizedBox(height: 4),
          Text('₹${amount.toStringAsFixed(2)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }

  void _quickEditBalance(FleetAccount account, String balanceType, [BuildContext? parentCtx]) {
    final ctrl = TextEditingController(
      text: (balanceType == 'current' ? account.currentBalance : account.openingBalance).toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit ${balanceType == 'current' ? 'Current' : 'Opening'} Balance',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(account.accountName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF2C3E50))),
          const SizedBox(height: 16),
          TextFormField(
            controller: ctrl, autofocus: true,
            decoration: InputDecoration(
              labelText: '${balanceType == 'current' ? 'Current' : 'Opening'} Balance',
              prefixIcon: const Icon(Icons.currency_rupee),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text);
              if (val == null) return;
              try {
                await _accountService.updateAccount(account.id, {
                  'accountName': account.accountName, 'holderName': account.holderName,
                  if (balanceType == 'current') 'currentBalance': val else 'openingBalance': val,
                  if (balanceType == 'current') 'openingBalance': account.openingBalance else 'currentBalance': account.currentBalance,
                });
                Navigator.pop(ctx);
                if (parentCtx != null && parentCtx.mounted) Navigator.pop(parentCtx);
                _showSuccess('Balance updated');
                _refresh();
              } catch (e) { _showError('Failed to update: $e'); }
            },
            style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Update', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── accounts table ────────────────────────────────────────────────────────

  Widget _buildAccountsTable() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEF2F7)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7))),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(children: [
              const Text('All Accounts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
              const Spacer(),
              Text('${_accounts.length} total', style: TextStyle(fontSize: 13, color: Colors.grey[500], fontWeight: FontWeight.w500)),
            ]),
          ),
          if (_accounts.isEmpty)
            _buildEmptyState()
          else
            Scrollbar(
              controller: _tableHScrollCtrl, thumbVisibility: true, trackVisibility: true, thickness: 8, radius: const Radius.circular(4),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
                child: SingleChildScrollView(
                  controller: _tableHScrollCtrl, scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                      headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
                      headingRowHeight: 52, dataRowMinHeight: 60, dataRowMaxHeight: 72,
                      dataTextStyle: const TextStyle(fontSize: 13),
                      dataRowColor: WidgetStateProperty.resolveWith((s) {
                        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                        return null;
                      }),
                      dividerThickness: 1, columnSpacing: 16, horizontalMargin: 16,
                      columns: const [
                        DataColumn(label: SizedBox(width: 140, child: Text('ACCOUNT TYPE'))),
                        DataColumn(label: SizedBox(width: 160, child: Text('ACCOUNT NAME'))),
                        DataColumn(label: SizedBox(width: 140, child: Text('HOLDER NAME'))),
                        DataColumn(label: SizedBox(width: 130, child: Text('CURRENT BAL'))),
                        DataColumn(label: SizedBox(width: 130, child: Text('OPENING BAL'))),
                        DataColumn(label: SizedBox(width: 90,  child: Text('STATUS'))),
                        DataColumn(label: SizedBox(width: 180, child: Text('ACTIONS'))),
                      ],
                      rows: _accounts.asMap().entries.map((e) => _buildTableRow(e.key, e.value)).toList(),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      }),
    );
  }

  DataRow _buildTableRow(int idx, FleetAccount account) {
    final cfg   = _accountTypeConfig[account.accountType] ?? _accountTypeConfig['OTHER']!;
    final color = cfg['color'] as Color;
    final icon  = cfg['icon']  as IconData;
    return DataRow(
      color: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return idx % 2 == 0 ? Colors.white : const Color(0xFFFAFAFC);
      }),
      cells: [
        DataCell(SizedBox(width: 140, child: Row(children: [
          Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: Icon(icon, size: 16, color: color)),
          const SizedBox(width: 8),
          Expanded(child: Text(cfg['displayName'] ?? account.accountType, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        ]))),
        DataCell(SizedBox(width: 160, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(account.accountName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50)), overflow: TextOverflow.ellipsis),
          if (account.accountDetails != null) Text(account.accountDetails!, style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
        ]))),
        DataCell(SizedBox(width: 140, child: Text(account.holderName ?? '—', style: TextStyle(fontSize: 13, color: Colors.grey[700]), overflow: TextOverflow.ellipsis))),
        DataCell(SizedBox(width: 130, child: Text('₹${account.currentBalance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF27AE60))))),
        DataCell(SizedBox(width: 130, child: Text('₹${account.openingBalance.toStringAsFixed(2)}', style: TextStyle(fontSize: 13, color: Colors.grey[700])))),
        DataCell(SizedBox(width: 90,  child: _buildStatusBadge(account.isActive))),
        DataCell(SizedBox(width: 180, child: Row(children: [
          Tooltip(message: 'Edit', child: InkWell(onTap: () => _showEditAccountDialog(account), borderRadius: BorderRadius.circular(8),
              child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.edit_outlined, size: 15, color: _blue)))),
          const SizedBox(width: 6),
          Tooltip(message: 'Delete', child: InkWell(onTap: () => _confirmDeleteAccount(account), borderRadius: BorderRadius.circular(8),
              child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _red.withOpacity(0.10), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.delete_outline, size: 15, color: _red)))),
          const SizedBox(width: 6),
          Tooltip(message: account.isActive ? 'Deactivate' : 'Activate', child: InkWell(onTap: () => _toggleAccountStatus(account), borderRadius: BorderRadius.circular(8),
              child: Container(width: 32, height: 32, decoration: BoxDecoration(color: (account.isActive ? _orange : _green).withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                  child: Icon(account.isActive ? Icons.block : Icons.check_circle_outline, size: 15, color: account.isActive ? _orange : _green)))),
          const SizedBox(width: 6),
          Tooltip(message: 'Reconcile', child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReconciliationBillingPage(accountId: account.id, accountName: account.accountName, accountType: account.accountType)))
                .then((res) { if (res == true) _refresh(); }),
            borderRadius: BorderRadius.circular(8),
            child: Container(width: 32, height: 32, decoration: BoxDecoration(color: _purple.withOpacity(0.10), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.compare_arrows, size: 15, color: _purple)))),
        ]))),
      ],
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    final bg = isActive ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9);
    final fg = isActive ? const Color(0xFF15803D) : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20), border: Border.all(color: fg.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(isActive ? 'Active' : 'Inactive', style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }

  void _showAddAccountDialog() async {
    final result = await showDialog(context: context, barrierDismissible: false, builder: (_) => const AddAccountDialog());
    if (result != null) _refresh();
  }

  void _showEditAccountDialog(FleetAccount account) async {
    final result = await showDialog(context: context, barrierDismissible: false, builder: (_) => EditAccountDialog(account: account));
    if (result != null) _refresh();
  }

  void _confirmDeleteAccount(FleetAccount account) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Delete "${account.accountName}"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async { Navigator.pop(context); await _deleteAccount(account); },
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(FleetAccount account) async {
    try {
      setState(() => _isLoading = true);
      final ok = await _accountService.deleteAccount(account.id);
      if (ok) { _showSuccess('Account deleted'); _refresh(); }
    } catch (e) { _showError('Failed to delete: $e'); }
    finally { setState(() => _isLoading = false); }
  }

  Future<void> _toggleAccountStatus(FleetAccount account) async {
    try {
      setState(() => _isLoading = true);
      await _accountService.updateAccountStatus(account.id, !account.isActive);
      _showSuccess(account.isActive ? 'Account deactivated' : 'Account activated');
      _refresh();
    } catch (e) { _showError('Failed to update status: $e'); }
    finally { setState(() => _isLoading = false); }
  }

  void _showImportTransactionsDialog() {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const ImportTransactionsDialog());
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
      child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: _navy.withOpacity(0.06), shape: BoxShape.circle),
            child: Icon(Icons.account_balance_outlined, size: 52, color: _navy.withOpacity(0.35))),
        const SizedBox(height: 20),
        const Text('No Accounts Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
        const SizedBox(height: 8),
        Text('Click "Add Account" to create your first account', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        const SizedBox(height: 24),
        ElevatedButton.icon(onPressed: _showAddAccountDialog, icon: const Icon(Icons.add),
            label: const Text('Add Account', style: TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
      ])),
    );
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle), child: Icon(Icons.error_outline, size: 52, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Banking Data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 40), child: Text(_errorMessage ?? 'Unknown error', style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center)),
      const SizedBox(height: 28),
      ElevatedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh),
          label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ])));
  }
}

// ============================================================================
// EDIT ACCOUNT DIALOG
// ============================================================================

class EditAccountDialog extends StatefulWidget {
  final FleetAccount account;
  const EditAccountDialog({Key? key, required this.account}) : super(key: key);

  @override
  State<EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<EditAccountDialog> {
  final _formKey     = GlobalKey<FormState>();
  final _svc         = AddAccountService();
  late final _nameCtrl   = TextEditingController(text: widget.account.accountName);
  late final _holderCtrl = TextEditingController(text: widget.account.holderName ?? '');
  late final _openCtrl   = TextEditingController(text: widget.account.openingBalance.toStringAsFixed(2));
  late final _currCtrl   = TextEditingController(text: widget.account.currentBalance.toStringAsFixed(2));
  bool _loading = false;

  static const _typeLabels = {
    'FUEL_CARD': 'Fuel Card', 'BANK': 'Bank Account', 'FASTAG': 'FASTag',
    'PETTY_CASH': 'Petty Cash', 'DRIVER_ADVANCE': 'Driver Advance',
  };

  @override
  void dispose() {
    _nameCtrl.dispose(); _holderCtrl.dispose(); _openCtrl.dispose(); _currCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _svc.updateAccount(widget.account.id, {
        'accountName':    _nameCtrl.text.trim(),
        'holderName':     _holderCtrl.text.trim().isNotEmpty ? _holderCtrl.text.trim() : null,
        'openingBalance': double.parse(_openCtrl.text.trim()),
        'currentBalance': double.parse(_currCtrl.text.trim()),
      });
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account updated'), backgroundColor: _green, behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: _red, behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500, padding: const EdgeInsets.all(24),
        child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.edit_outlined, color: _blue, size: 22)),
            const SizedBox(width: 12),
            const Expanded(child: Text('Edit Account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF7F9FC), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 18, color: _navy), const SizedBox(width: 10),
              Text('Account Type: ${_typeLabels[widget.account.accountType] ?? widget.account.accountType}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navy)),
            ]),
          ),
          const SizedBox(height: 16),
          _field(_nameCtrl,   'Account Name *',   Icons.label_outline,          required: true),
          const SizedBox(height: 14),
          _field(_holderCtrl, 'Holder Name',       Icons.person_outline),
          const SizedBox(height: 14),
          _field(_openCtrl,   'Opening Balance *', Icons.currency_rupee,         required: true, isNum: true),
          const SizedBox(height: 14),
          _field(_currCtrl,   'Current Balance *', Icons.account_balance_wallet, required: true, isNum: true),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Update Account', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
        ])),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon, {bool required = false, bool isNum = false}) {
    return TextFormField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label, prefixIcon: Icon(icon),
        filled: true, fillColor: const Color(0xFFF7F9FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
      keyboardType: isNum ? TextInputType.number : TextInputType.text,
      inputFormatters: isNum ? [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))] : null,
      validator: required ? (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (isNum && double.tryParse(v) == null) return 'Enter a valid number';
        return null;
      } : null,
    );
  }
}