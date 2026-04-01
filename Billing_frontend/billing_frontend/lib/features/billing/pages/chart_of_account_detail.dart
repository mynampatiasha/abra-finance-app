// ============================================================================
// CHART OF ACCOUNT DETAIL PAGE
// ============================================================================
// File: lib/screens/billing/pages/chart_of_account_detail.dart
// Full detail page - Account info + all transactions
// Navy blue gradient theme | Fully responsive
// ============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/chart_of_account_service.dart';
import 'new_chart_of_account.dart';

const Color _navyDark  = Color(0xFF0F172A);
const Color _navyMid   = Color(0xFF1E3A5F);
const Color _navyAccent= Color(0xFF2563EB);
const Color _kPageBg   = Color(0xFFF8FAFC);

// ============================================================================
class ChartOfAccountDetailPage extends StatefulWidget {
  final String accountId;
  const ChartOfAccountDetailPage({Key? key, required this.accountId}) : super(key: key);

  @override
  State<ChartOfAccountDetailPage> createState() => _ChartOfAccountDetailPageState();
}

class _ChartOfAccountDetailPageState extends State<ChartOfAccountDetailPage> {
  ChartOfAccount? _account;
  List<AccountTransaction> _transactions = [];
  bool _loadingAccount = true;
  bool _loadingTxns    = true;
  String? _errorAccount;

  // Date filter for transactions
  DateTime? _fromDate;
  DateTime? _toDate;

  // View mode toggle: true = Table View, false = List View
  bool _isTableView = true;

  final _hScrollCtrl = ScrollController();
  final _vScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadAccount();
    _loadTransactions();
  }

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    _vScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAccount() async {
    setState(() { _loadingAccount = true; _errorAccount = null; });
    try {
      final acc = await ChartOfAccountService.getAccount(widget.accountId);
      if (mounted) setState(() { _account = acc; _loadingAccount = false; });
    } catch (e) {
      if (mounted) setState(() { _errorAccount = e.toString(); _loadingAccount = false; });
    }
  }

  Future<void> _loadTransactions() async {
    setState(() => _loadingTxns = true);
    try {
      final txns = await ChartOfAccountService.getTransactions(
        widget.accountId, fromDate: _fromDate, toDate: _toDate);
      if (mounted) setState(() { _transactions = txns; _loadingTxns = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingTxns = false);
    }
  }

  Future<void> _goToEdit() async {
    if (_account == null) return;
    final ok = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => NewChartOfAccountScreen(accountId: _account!.id)));
    if (ok == true) { _loadAccount(); _loadTransactions(); }
  }

  Future<void> _toggleActive() async {
    if (_account == null || _account!.isSystemAccount) {
      _snack('System accounts cannot be modified', Colors.orange);
      return;
    }
    try {
      await ChartOfAccountService.toggleActive(_account!.id, !_account!.isActive);
      _snack(_account!.isActive ? 'Account deactivated' : 'Account activated', Colors.green);
      _loadAccount();
    } catch (e) {
      _snack('Failed: $e', Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  // ============================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      appBar: _buildAppBar(),
      body: _loadingAccount
          ? const Center(child: CircularProgressIndicator())
          : _errorAccount != null
              ? _buildError()
              : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() => PreferredSize(
    preferredSize: const Size.fromHeight(60),
    child: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_navyDark, _navyMid],
            begin: Alignment.centerLeft, end: Alignment.centerRight),
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(_account?.accountName ?? 'Account Detail',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          if (_account != null && !_account!.isSystemAccount) ...[
            TextButton.icon(
              onPressed: _toggleActive,
              icon: Icon(_account!.isActive ? Icons.block : Icons.check_circle_outline,
                  color: Colors.white70, size: 18),
              label: Text(_account!.isActive ? 'Deactivate' : 'Activate',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            ElevatedButton.icon(
              onPressed: _goToEdit,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
    ),
  );

  Widget _buildError() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
    const SizedBox(height: 16),
    Text(_errorAccount!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
    const SizedBox(height: 16),
    ElevatedButton.icon(onPressed: _loadAccount, icon: const Icon(Icons.refresh), label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white)),
  ]));

  Widget _buildBody() {
    final acc = _account!;
    return Scrollbar(
      controller: _vScrollCtrl,
      thumbVisibility: true,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
        ),
        child: SingleChildScrollView(
          controller: _vScrollCtrl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAccountHeader(acc),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildInfoCards(acc),
              ),
              const SizedBox(height: 16),
              if (acc.description != null && acc.description!.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildDescriptionCard(acc),
                ),
                const SizedBox(height: 16),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTransactionsSection(),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Account Header ────────────────────────────────────────────────────────

  Widget _buildAccountHeader(ChartOfAccount acc) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [_navyDark, _navyMid],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    child: LayoutBuilder(builder: (_, c) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_typeIcon(acc.accountType), color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(acc.accountName,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text('${acc.accountType} • ${acc.accountSubType}',
                style: const TextStyle(fontSize: 14, color: Colors.white70)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: acc.isActive ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: acc.isActive ? Colors.green : Colors.red, width: 1),
              ),
              child: Text(acc.isActive ? 'Active' : 'Inactive',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            if (acc.isSystemAccount) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('System Account',
                    style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
        ]),
        const SizedBox(height: 20),
        // Closing balance highlight
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Closing Balance', style: TextStyle(fontSize: 12, color: Colors.white70)),
              const SizedBox(height: 2),
              Text(
                '₹${NumberFormat('#,##0.00').format(acc.closingBalance)} (${acc.balanceType})',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ]),
          ]),
        ),
      ]);
    }),
  );

  // ── Info Cards ────────────────────────────────────────────────────────────

  Widget _buildInfoCards(ChartOfAccount acc) {
    final cards = [
      _InfoCard('Account Code', acc.accountCode.isNotEmpty ? acc.accountCode : '-', Icons.tag, Colors.blue),
      _InfoCard('Currency', acc.currency, Icons.currency_rupee, Colors.teal),
      _InfoCard('Transactions', acc.transactionCount.toString(), Icons.receipt_long_outlined, Colors.orange),
      _InfoCard('Parent Account', acc.parentAccountName ?? 'None', Icons.account_tree_outlined, Colors.purple),
    ];

    return LayoutBuilder(builder: (_, c) {
      final cols = c.maxWidth > 700 ? 4 : c.maxWidth > 400 ? 2 : 1;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards.map((card) => SizedBox(
          width: cols == 4
              ? (c.maxWidth - 36) / 4
              : cols == 2
                  ? (c.maxWidth - 12) / 2
                  : c.maxWidth,
          child: _buildInfoCard(card),
        )).toList(),
      );
    });
  }

  Widget _buildInfoCard(_InfoCard card) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.grey.shade100),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
    ),
    child: Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: card.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(card.icon, size: 20, color: card.color),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(card.label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(card.value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );

  // ── Description ───────────────────────────────────────────────────────────

  Widget _buildDescriptionCard(ChartOfAccount acc) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.grey.shade100),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Description', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(acc.description!,
          style: const TextStyle(fontSize: 14, color: Color(0xFF374151), height: 1.5)),
    ]),
  );

  // ── Transactions ──────────────────────────────────────────────────────────

  Widget _buildTransactionsSection() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with toggle
        Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(builder: (_, c) {
            final isMobile = c.maxWidth < 600;
            if (isMobile) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.receipt_long_outlined, size: 20, color: _navyAccent),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Transactions',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navyDark))),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    // View toggle
                    _buildViewToggle(),
                    const Spacer(),
                    // Date filter
                    OutlinedButton.icon(
                      onPressed: _showDateFilter,
                      icon: const Icon(Icons.filter_alt_outlined, size: 14),
                      label: Text(
                        _fromDate != null ? 'Filtered' : 'Filter',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navyAccent,
                        side: const BorderSide(color: _navyAccent),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      ),
                    ),
                    if (_fromDate != null) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.clear, size: 14, color: Colors.red),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () { setState(() { _fromDate = null; _toDate = null; }); _loadTransactions(); },
                      ),
                    ],
                  ]),
                ],
              );
            }
            return Row(children: [
              const Icon(Icons.receipt_long_outlined, size: 20, color: _navyAccent),
              const SizedBox(width: 8),
              const Expanded(child: Text('Transactions',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navyDark))),
              // View toggle
              _buildViewToggle(),
              const SizedBox(width: 12),
              // Date filter
              OutlinedButton.icon(
                onPressed: _showDateFilter,
                icon: const Icon(Icons.filter_alt_outlined, size: 16),
                label: Text(
                  _fromDate != null ? '${DateFormat('dd MMM').format(_fromDate!)} – ${_toDate != null ? DateFormat('dd MMM').format(_toDate!) : 'now'}' : 'All Dates',
                  style: const TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navyAccent,
                  side: const BorderSide(color: _navyAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              if (_fromDate != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.clear, size: 16, color: Colors.red),
                  onPressed: () { setState(() { _fromDate = null; _toDate = null; }); _loadTransactions(); },
                ),
              ],
            ]);
          }),
        ),
        const Divider(height: 1),
        // Content based on view mode
        _loadingTxns
            ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
            : _transactions.isEmpty
                ? SizedBox(
                    height: 200,
                    child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('There are no transactions available',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
                    ])),
                  )
                : _isTableView ? _buildTableView() : _buildListView(),
      ],
    ),
  );

  // View toggle button
  Widget _buildViewToggle() => Container(
    decoration: BoxDecoration(
      border: Border.all(color: Colors.grey.shade300),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _toggleButton(
          icon: Icons.view_list_rounded,
          label: 'List',
          isSelected: !_isTableView,
          onTap: () => setState(() => _isTableView = false),
        ),
        Container(width: 1, height: 24, color: Colors.grey.shade300),
        _toggleButton(
          icon: Icons.table_chart_rounded,
          label: 'Table',
          isSelected: _isTableView,
          onTap: () => setState(() => _isTableView = true),
        ),
      ],
    ),
  );

  Widget _toggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(7),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? _navyAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    ),
  );

  // Table View - Full width with horizontal scroll
  Widget _buildTableView() => Scrollbar(
    controller: _hScrollCtrl,
    thumbVisibility: true,
    trackVisibility: true,
    child: ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad},
      ),
      child: SingleChildScrollView(
        controller: _hScrollCtrl,
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.of(context).size.width - 32, // Full page width minus padding
          ),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFF1A252F)),
            headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            dataTextStyle: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
            dataRowMinHeight: 50,
            dataRowMaxHeight: 60,
            dividerThickness: 0.8,
            columnSpacing: 20,
            horizontalMargin: 16,
            columns: const [
              DataColumn(label: SizedBox(width: 110, child: Text('DATE'))),
              DataColumn(label: SizedBox(width: 220, child: Text('DESCRIPTION'))),
              DataColumn(label: SizedBox(width: 120, child: Text('REF TYPE'))),
              DataColumn(label: SizedBox(width: 140, child: Text('REF NUMBER'))),
              DataColumn(label: SizedBox(width: 110, child: Text('DEBIT (₹)'))),
              DataColumn(label: SizedBox(width: 110, child: Text('CREDIT (₹)'))),
              DataColumn(label: SizedBox(width: 120, child: Text('BALANCE (₹)'))),
            ],
            rows: _transactions.map((t) => DataRow(cells: [
              DataCell(SizedBox(width: 110,
                  child: Text(DateFormat('dd MMM yyyy').format(t.date),
                      style: const TextStyle(fontSize: 12)))),
              DataCell(SizedBox(width: 220,
                  child: Text(t.description, overflow: TextOverflow.ellipsis))),
              DataCell(SizedBox(width: 120,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _refTypeColor(t.referenceType).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(t.referenceType,
                        style: TextStyle(fontSize: 11, color: _refTypeColor(t.referenceType),
                            fontWeight: FontWeight.w600)),
                  ))),
              DataCell(SizedBox(width: 140,
                  child: Text(t.referenceNumber,
                      style: const TextStyle(color: _navyAccent, fontWeight: FontWeight.w600, fontSize: 12)))),
              DataCell(SizedBox(width: 110,
                  child: Text(
                    t.debit > 0 ? NumberFormat('#,##0.00').format(t.debit) : '-',
                    style: TextStyle(color: t.debit > 0 ? Colors.red.shade700 : Colors.grey.shade400,
                        fontWeight: t.debit > 0 ? FontWeight.bold : FontWeight.normal),
                  ))),
              DataCell(SizedBox(width: 110,
                  child: Text(
                    t.credit > 0 ? NumberFormat('#,##0.00').format(t.credit) : '-',
                    style: TextStyle(color: t.credit > 0 ? Colors.green.shade700 : Colors.grey.shade400,
                        fontWeight: t.credit > 0 ? FontWeight.bold : FontWeight.normal),
                  ))),
              DataCell(SizedBox(width: 120,
                  child: Text(NumberFormat('#,##0.00').format(t.balance),
                      style: const TextStyle(fontWeight: FontWeight.bold)))),
            ])).toList(),
          ),
        ),
      ),
    ),
  );

  // List View - Card-based layout
  Widget _buildListView() => ListView.separated(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(16),
    itemCount: _transactions.length,
    separatorBuilder: (_, __) => const SizedBox(height: 12),
    itemBuilder: (_, i) {
      final t = _transactions[i];
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kPageBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and Ref Type
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  DateFormat('dd MMM yyyy').format(t.date),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _refTypeColor(t.referenceType).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    t.referenceType,
                    style: TextStyle(
                      fontSize: 11,
                      color: _refTypeColor(t.referenceType),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Description
            Text(
              t.description,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark),
            ),
            const SizedBox(height: 8),
            // Ref Number
            Row(
              children: [
                Text('Ref: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                Text(
                  t.referenceNumber,
                  style: const TextStyle(fontSize: 12, color: _navyAccent, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const Divider(height: 20),
            // Amounts
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Debit', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      const SizedBox(height: 3),
                      Text(
                        t.debit > 0 ? '₹${NumberFormat('#,##0.00').format(t.debit)}' : '-',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: t.debit > 0 ? FontWeight.bold : FontWeight.normal,
                          color: t.debit > 0 ? Colors.red.shade700 : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Credit', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      const SizedBox(height: 3),
                      Text(
                        t.credit > 0 ? '₹${NumberFormat('#,##0.00').format(t.credit)}' : '-',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: t.credit > 0 ? FontWeight.bold : FontWeight.normal,
                          color: t.credit > 0 ? Colors.green.shade700 : Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('Balance', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      const SizedBox(height: 3),
                      Text(
                        '₹${NumberFormat('#,##0.00').format(t.balance)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _navyDark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  // ── Date filter ───────────────────────────────────────────────────────────

  void _showDateFilter() {
    DateTime? from = _fromDate, to = _toDate;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Filter by Date'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _dateTile(ctx, from, 'From Date', (d) => setS(() => from = d)),
          const SizedBox(height: 14),
          _dateTile(ctx, to, 'To Date', (d) => setS(() => to = d)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() { _fromDate = from; _toDate = to; });
              Navigator.pop(ctx);
              _loadTransactions();
            },
            style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white),
            child: const Text('Apply'),
          ),
        ],
      )),
    );
  }

  Widget _dateTile(BuildContext ctx, DateTime? date, String label, void Function(DateTime) onPick) =>
      InkWell(
        onTap: () async {
          final d = await showDatePicker(context: ctx,
              initialDate: date ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
          if (d != null) onPick(d);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey),
            const SizedBox(width: 10),
            Text(date != null ? DateFormat('dd MMM yyyy').format(date) : label,
                style: TextStyle(color: date != null ? _navyDark : Colors.grey.shade500, fontSize: 14)),
          ]),
        ),
      );

  // ── Helpers ───────────────────────────────────────────────────────────────

  IconData _typeIcon(String type) {
    switch (type) {
      case 'Asset':     return Icons.account_balance_wallet_outlined;
      case 'Liability': return Icons.credit_card_outlined;
      case 'Equity':    return Icons.pie_chart_outline;
      case 'Income':    return Icons.trending_up;
      case 'Expense':   return Icons.trending_down;
      default:          return Icons.account_balance_outlined;
    }
  }

  Color _refTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'invoice':  return Colors.blue;
      case 'bill':     return Colors.orange;
      case 'payment':  return Colors.green;
      case 'journal':  return Colors.purple;
      case 'expense':  return Colors.red;
      default:         return Colors.grey;
    }
  }
}

// ── Helper Data Class ─────────────────────────────────────────────────────────
class _InfoCard {
  final String label, value;
  final IconData icon;
  final Color color;
  const _InfoCard(this.label, this.value, this.icon, this.color);
}