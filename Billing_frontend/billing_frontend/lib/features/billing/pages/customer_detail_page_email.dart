// ============================================================================
// CUSTOMER DETAIL PAGE — ZOHO BOOKS STYLE (5 TABS)
// ============================================================================
// File: lib/features/admin/Billing/pages/customer_detail_page.dart
// Tabs: Overview | Comments | Transactions | Mails | Statement
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../../../../core/services/billing_customers_service.dart';
import 'new_customer.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);
const Color _red        = Color(0xFFE74C3C);
const Color _orange     = Color(0xFFE67E22);

// ============================================================================
class CustomerDetailPage extends StatefulWidget {
  final String customerId;
  const CustomerDetailPage({Key? key, required this.customerId}) : super(key: key);

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  BillingCustomer?        _customer;
  CustomerOverviewData?   _overview;
  List<CustomerTransaction>? _transactions;
  List<CustomerMail>?     _mails;
  CustomerStatementData?  _statement;

  bool _loadingCustomer     = true;
  bool _loadingOverview     = true;
  bool _loadingTransactions = false;
  bool _loadingMails        = false;
  bool _loadingStatement    = false;
  String? _error;
  bool _changed = false;

  // Statement date filters
  DateTime _statementFrom = DateTime.now().subtract(const Duration(days: 365));
  DateTime _statementTo   = DateTime.now();

  // Income chart
  int? _hoveredBarIndex;

  // Comment
  final TextEditingController _commentCtrl = TextEditingController();
  bool _postingComment = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCustomer();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    switch (_tabController.index) {
      case 0: if (_overview      == null) _loadOverview();     break;
      case 1: /* comments loaded with customer */              break;
      case 2: if (_transactions  == null) _loadTransactions(); break;
      case 3: if (_mails         == null) _loadMails();        break;
      case 4: if (_statement     == null) _loadStatement();    break;
    }
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadCustomer() async {
    setState(() { _loadingCustomer = true; _error = null; });
    try {
      final c = await BillingCustomersService.getCustomerById(widget.customerId);
      setState(() { _customer = c; _loadingCustomer = false; });
      _loadOverview();
    } catch (e) {
      setState(() { _error = e.toString(); _loadingCustomer = false; });
    }
  }

  Future<void> _loadOverview() async {
    setState(() => _loadingOverview = true);
    try {
      final o = await BillingCustomersService.getCustomerOverview(widget.customerId);
      setState(() { _overview = o; _loadingOverview = false; });
    } catch (_) { setState(() => _loadingOverview = false); }
  }

  Future<void> _loadTransactions() async {
    setState(() => _loadingTransactions = true);
    try {
      final t = await BillingCustomersService.getCustomerTransactions(widget.customerId);
      setState(() { _transactions = t; _loadingTransactions = false; });
    } catch (_) { setState(() { _transactions = []; _loadingTransactions = false; }); }
  }

  Future<void> _loadMails() async {
    setState(() => _loadingMails = true);
    try {
      final m = await BillingCustomersService.getCustomerMails(widget.customerId);
      setState(() { _mails = m; _loadingMails = false; });
    } catch (_) { setState(() { _mails = []; _loadingMails = false; }); }
  }

  Future<void> _loadStatement() async {
    setState(() => _loadingStatement = true);
    try {
      final s = await BillingCustomersService.getCustomerStatement(
        widget.customerId, fromDate: _statementFrom, toDate: _statementTo);
      setState(() { _statement = s; _loadingStatement = false; });
    } catch (_) { setState(() { _statement = null; _loadingStatement = false; }); }
  }

  Future<void> _postComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _postingComment = true);
    try {
      final comment = await BillingCustomersService.addComment(widget.customerId, text);
      setState(() {
        _customer = BillingCustomer.fromJson({
          ..._customer!.toJson(),
          'comments': [
            ..._customer!.comments.map((c) => {
              '_id': c.id, 'text': c.text,
              'createdBy': c.createdBy, 'createdAt': c.createdAt.toIso8601String(),
            }),
            {'_id': comment.id, 'text': comment.text, 'createdBy': comment.createdBy, 'createdAt': comment.createdAt.toIso8601String()},
          ],
        });
        _commentCtrl.clear();
        _postingComment = false;
      });
    } catch (_) { setState(() => _postingComment = false); }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await BillingCustomersService.deleteComment(widget.customerId, commentId);
      setState(() {
        _customer = BillingCustomer.fromJson({
          ..._customer!.toJson(),
          'comments': _customer!.comments
              .where((c) => c.id != commentId)
              .map((c) => {'_id': c.id, 'text': c.text, 'createdBy': c.createdBy, 'createdAt': c.createdAt.toIso8601String()})
              .toList(),
        });
      });
    } catch (_) {}
  }

  void _openEdit() async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NewCustomerPage(customerId: widget.customerId)));
    if (result == true) { setState(() => _changed = true); _loadCustomer(); }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? _red : _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async { Navigator.pop(context, _changed); return false; },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F8),
        body: _loadingCustomer
            ? const Center(child: CircularProgressIndicator(color: _navyLight))
            : _error != null
                ? _buildError()
                : _buildMain(),
      ),
    );
  }

  Widget _buildMain() {
    final c = _customer!;
    return NestedScrollView(
      headerSliverBuilder: (ctx, _) => [
        SliverAppBar(
          pinned: true,
          expandedHeight: 0,
          backgroundColor: _navyDark,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: Text(c.customerDisplayName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          actions: [
            TextButton.icon(
              onPressed: _openEdit,
              icon: const Icon(Icons.edit, color: Colors.white70, size: 16),
              label: const Text('Edit', style: TextStyle(color: Colors.white70)),
            ),
            _NewTransactionButton(customer: c),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: Colors.white),
              onSelected: (v) {
                if (v == 'refresh') _loadCustomer();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'refresh', child: ListTile(
                  leading: Icon(Icons.refresh), title: Text('Refresh'), contentPadding: EdgeInsets.zero)),
              ],
            ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: _navyAccent,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Comments'),
              Tab(text: 'Transactions'),
              Tab(text: 'Mails'),
              Tab(text: 'Statement'),
            ],
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildCommentsTab(),
          _buildTransactionsTab(),
          _buildMailsTab(),
          _buildStatementTab(),
        ],
      ),
    );
  }

  // ============================================================================
  // TAB 1 — OVERVIEW
  // ============================================================================

  Widget _buildOverviewTab() {
    final c = _customer!;
    return LayoutBuilder(builder: (ctx, cs) {
      final isWide = cs.maxWidth > 800;
      final left = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Customer avatar card
          _avatarCard(c),
          const SizedBox(height: 16),
          // Address
          _addressCard(c),
          const SizedBox(height: 16),
          // Other Details
          _otherDetailsCard(c),
        ]),
      );
      final right = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Payment due period
          _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Payment due period', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(c.paymentTerms.isEmpty ? 'Due on Receipt' : c.paymentTerms,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _navyDark)),
          ])),
          const SizedBox(height: 16),
          // Receivables
          _receivablesCard(),
          const SizedBox(height: 16),
          // Income chart
          _incomeChartCard(),
        ]),
      );
      if (isWide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: left),
          Expanded(flex: 6, child: right),
        ]);
      }
      return SingleChildScrollView(child: Column(children: [left, right]));
    });
  }

  Widget _avatarCard(BillingCustomer c) {
    return _card(child: Row(children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_navyMid, _navyLight]),
          shape: BoxShape.circle,
        ),
        child: Center(child: Text(
          c.customerDisplayName.isNotEmpty ? c.customerDisplayName[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        )),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.customerDisplayName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navyDark)),
        if (c.companyName.isNotEmpty && c.companyName != c.customerDisplayName)
          Text(c.companyName, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: c.portalEnabled ? _green.withOpacity(0.1) : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.portalEnabled ? _green.withOpacity(0.4) : Colors.grey[300]!),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: c.portalEnabled ? _green : Colors.grey,
                    shape: BoxShape.circle,
                  )),
              Text(c.portalEnabled ? 'Portal Enabled' : 'Portal not enabled',
                  style: TextStyle(fontSize: 11, color: c.portalEnabled ? _green : Colors.grey[600], fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
      ])),
      _statusBadge(c.customerStatus),
    ]));
  }

  Widget _addressCard(BillingCustomer c) {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Row(children: [
        const Icon(Icons.location_on_outlined, size: 18, color: _navyAccent),
        const SizedBox(width: 6),
        const Text('ADDRESS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyDark, letterSpacing: 0.8)),
        const Spacer(),
        InkWell(
          onTap: _openEdit,
          child: const Icon(Icons.keyboard_arrow_up, color: Colors.grey),
        ),
      ]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Billing Address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navyDark)),
          const SizedBox(height: 6),
          c.billingAddress.isEmpty
              ? TextButton(
                  onPressed: _openEdit,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('No Billing Address - New Address',
                      style: TextStyle(fontSize: 12, color: _navyAccent)),
                )
              : Text(c.billingAddress.formatted,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5)),
        ])),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Shipping Address', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navyDark)),
          const SizedBox(height: 6),
          c.shippingAddress.isEmpty
              ? TextButton(
                  onPressed: _openEdit,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('No Shipping Address - New Address',
                      style: TextStyle(fontSize: 12, color: _navyAccent)),
                )
              : Text(c.shippingAddress.formatted,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5)),
        ])),
      ]),
    ]));
  }

  Widget _otherDetailsCard(BillingCustomer c) {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.info_outline, size: 18, color: _navyAccent),
        const SizedBox(width: 6),
        const Text('OTHER DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _navyDark, letterSpacing: 0.8)),
        const Spacer(),
        InkWell(onTap: _openEdit, child: const Icon(Icons.keyboard_arrow_up, color: Colors.grey)),
      ]),
      const SizedBox(height: 16),
      _detailRow('Customer Type',     c.customerType),
      _detailRow('Default Currency',  c.defaultCurrency),
      if (c.gstNumber.isNotEmpty)      _detailRow('GSTIN/UIN',       c.gstNumber),
      if (c.gstRegistrationType.isNotEmpty) _detailRow('GST Reg. Type', c.gstRegistrationType),
      if (c.placeOfSupply.isNotEmpty)  _detailRow('Place of Supply', c.placeOfSupply),
      if (c.panNumber.isNotEmpty)      _detailRow('PAN Number',      c.panNumber),
      if (c.taxPreference.isNotEmpty)  _detailRow('Tax Preference',  c.taxPreference),
      _detailRow('Portal Status', c.portalEnabled
          ? '● Enabled\n(${c.contactPersons.length} Contact${c.contactPersons.length == 1 ? '' : 's'})'
          : 'Not enabled'),
    ]));
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 140, child: Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
        Expanded(child: Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _navyDark))),
      ]),
    );
  }

  Widget _receivablesCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Receivables',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      const SizedBox(height: 12),
      if (_loadingOverview)
        const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(strokeWidth: 2)))
      else ...[
        // Header row
        const Row(children: [
          Expanded(child: Text('CURRENCY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8))),
          SizedBox(width: 80, child: Text('OUTSTANDING\nRECEIVABLES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5), textAlign: TextAlign.right)),
          SizedBox(width: 16),
          SizedBox(width: 80, child: Text('UNUSED\nCREDITS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5), textAlign: TextAlign.right)),
        ]),
        const Divider(height: 12),
        Row(children: [
          Expanded(child: Text(
            '${_overview?.currency ?? 'INR'}- Indian Rupee',
            style: const TextStyle(fontSize: 13, color: _navyDark),
          )),
          SizedBox(width: 80, child: Text(
            '₹${(_overview?.outstandingReceivables ?? 0).toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navyDark),
            textAlign: TextAlign.right,
          )),
          const SizedBox(width: 16),
          SizedBox(width: 80, child: Text(
            '₹${(_overview?.unusedCredits ?? 0).toStringAsFixed(2)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: (_overview?.unusedCredits ?? 0) > 0 ? _navyAccent : _navyDark),
            textAlign: TextAlign.right,
          )),
        ]),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () { setState(() => _tabController.index = 2); _loadTransactions(); },
          child: Text('Enter Opening Balance',
              style: const TextStyle(fontSize: 13, color: _navyAccent, fontWeight: FontWeight.w500)),
        ),
      ],
    ]));
  }

  Widget _incomeChartCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Income', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
        const SizedBox(width: 8),
        Text('This chart is displayed in the organisation\'s base currency.',
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const Spacer(),
        _chipBtn('Last 6 Months'),
        const SizedBox(width: 8),
        _chipBtn('Accrual'),
      ]),
      const SizedBox(height: 16),
      if (_loadingOverview)
        const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2)))
      else
        _IncomeBarChart(
          data: _overview?.monthlyIncome ?? [],
          hoveredIndex: _hoveredBarIndex,
          onBarTap: (i) => setState(() => _hoveredBarIndex = _hoveredBarIndex == i ? null : i),
        ),
    ]));
  }

  Widget _chipBtn(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
        const Icon(Icons.arrow_drop_down, size: 14, color: Colors.grey),
      ]),
    );
  }

  // ============================================================================
  // TAB 2 — COMMENTS
  // ============================================================================

  Widget _buildCommentsTab() {
    final comments = _customer?.comments ?? [];
    return Column(children: [
      // Input
      Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _commentCtrl,
              decoration: InputDecoration(
                hintText: 'Add a comment...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                filled: true, fillColor: Colors.grey[50],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _navyLight, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
              maxLines: 3,
              minLines: 1,
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _postingComment ? null : _postComment,
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyLight, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _postingComment
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Post'),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: comments.isEmpty
            ? _emptyState(Icons.comment_outlined, 'No comments yet', 'Add the first comment above')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: comments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final comment = comments[i];
                  return _card(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: _navyLight.withOpacity(0.12), shape: BoxShape.circle),
                      child: Center(child: Text(
                        comment.createdBy.isNotEmpty ? comment.createdBy[0].toUpperCase() : '?',
                        style: const TextStyle(color: _navyLight, fontWeight: FontWeight.bold),
                      )),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(comment.createdBy, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navyDark)),
                        const SizedBox(width: 8),
                        Text(DateFormat('dd MMM yyyy, hh:mm a').format(comment.createdAt),
                            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      ]),
                      const SizedBox(height: 6),
                      Text(comment.text, style: TextStyle(fontSize: 13, color: Colors.grey[800], height: 1.4)),
                    ])),
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
                      onPressed: () => _deleteComment(comment.id),
                      tooltip: 'Delete comment',
                    ),
                  ]));
                },
              ),
      ),
    ]);
  }

  // ============================================================================
  // TAB 3 — TRANSACTIONS
  // ============================================================================

  Widget _buildTransactionsTab() {
    if (_loadingTransactions) return const Center(child: CircularProgressIndicator(color: _navyLight));
    if (_transactions == null) {
      return _emptyState(Icons.sync, 'Loading transactions...', '',
          action: ElevatedButton.icon(onPressed: _loadTransactions, icon: const Icon(Icons.refresh), label: const Text('Load')));
    }
    if (_transactions!.isEmpty) return _emptyState(Icons.receipt_long, 'No transactions yet', 'Transactions will appear here once invoices are created');

    return Column(children: [
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.white,
        child: Row(children: [
          Text('${_transactions!.length} transaction${_transactions!.length == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.bold, color: _navyDark)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _card(child: Column(children: [
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(color: _navyDark, borderRadius: BorderRadius.vertical(top: Radius.circular(6))),
              child: Row(children: const [
                SizedBox(width: 90,  child: Text('DATE',   style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
                Expanded(            child: Text('NUMBER', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
                SizedBox(width: 100, child: Text('TYPE',   style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
                SizedBox(width: 80,  child: Text('STATUS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
                SizedBox(width: 100, child: Text('AMOUNT', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5), textAlign: TextAlign.right)),
                SizedBox(width: 100, child: Text('BALANCE',style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5), textAlign: TextAlign.right)),
              ]),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _transactions!.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final t = _transactions![i];
                final isInvoice = t.type == 'Invoice';
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    SizedBox(width: 90, child: Text(DateFormat('dd MMM yy').format(t.date),
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]))),
                    Expanded(child: Text(t.number,
                        style: const TextStyle(fontSize: 12, color: _navyAccent, fontWeight: FontWeight.w600))),
                    SizedBox(width: 100, child: Row(children: [
                      Icon(isInvoice ? Icons.description_outlined : Icons.payment,
                          size: 14, color: isInvoice ? _navyMid : _green),
                      const SizedBox(width: 4),
                      Text(t.type, style: TextStyle(fontSize: 12, color: isInvoice ? _navyMid : _green, fontWeight: FontWeight.w500)),
                    ])),
                    SizedBox(width: 80, child: _txnStatusBadge(t.status)),
                    SizedBox(width: 100, child: Text('₹${t.amount.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navyDark),
                        textAlign: TextAlign.right)),
                    SizedBox(width: 100, child: Text(
                        t.balance > 0 ? '₹${t.balance.toStringAsFixed(2)}' : '—',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: t.balance > 0 ? _red : Colors.grey[500]),
                        textAlign: TextAlign.right)),
                  ]),
                );
              },
            ),
          ])),
        ),
      ),
    ]);
  }

  Widget _txnStatusBadge(String status) {
    final colors = {
      'PAID': [const Color(0xFFDCFCE7), const Color(0xFF15803D)],
      'UNPAID': [const Color(0xFFFFEDD5), const Color(0xFFEA580C)],
      'OVERDUE': [const Color(0xFFFEE2E2), const Color(0xFFDC2626)],
      'PARTIALLY_PAID': [const Color(0xFFE0E7FF), const Color(0xFF4338CA)],
      'DRAFT': [const Color(0xFFFEF3C7), const Color(0xFFB45309)],
      'SENT': [const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)],
    };
    final c = colors[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(10)),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c[1])),
    );
  }

  // ============================================================================
  // TAB 4 — MAILS
  // ============================================================================

  Widget _buildMailsTab() {
    if (_loadingMails) return const Center(child: CircularProgressIndicator(color: _navyLight));
    if (_mails == null) {
      return _emptyState(Icons.mail_outline, 'Loading mails...', '',
          action: ElevatedButton.icon(onPressed: _loadMails, icon: const Icon(Icons.refresh), label: const Text('Load')));
    }
    if (_mails!.isEmpty) return _emptyState(Icons.mark_email_unread_outlined, 'No emails sent', 'Emails sent via invoices will appear here');

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _mails!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final m = _mails![i];
        final icon = m.emailType == 'payment_receipt' ? Icons.receipt_outlined : Icons.email_outlined;
        final color = m.emailType == 'payment_receipt' ? _green : _navyLight;
        return _card(child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.subject, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navyDark), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text('To: ${m.sentTo}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            Text('Invoice: ${m.invoiceNumber}  •  ₹${m.amount.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(DateFormat('dd MMM yyyy').format(m.sentAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 4),
            Text(DateFormat('hh:mm a').format(m.sentAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ]),
        ]));
      },
    );
  }

  // ============================================================================
  // TAB 5 — STATEMENT
  // ============================================================================

  Widget _buildStatementTab() {
    return Column(children: [
      // Date filter bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.white,
        child: Row(children: [
          const Text('Period:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navyDark)),
          const SizedBox(width: 10),
          _datePicker('From', _statementFrom, (d) { setState(() => _statementFrom = d); _loadStatement(); }),
          const SizedBox(width: 10),
          _datePicker('To', _statementTo, (d) { setState(() => _statementTo = d); _loadStatement(); }),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _loadStatement,
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyLight, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Run', style: TextStyle(fontSize: 13)),
          ),
        ]),
      ),
      const Divider(height: 1),
      if (_loadingStatement)
        const Expanded(child: Center(child: CircularProgressIndicator(color: _navyLight)))
      else if (_statement == null)
        Expanded(child: _emptyState(Icons.bar_chart, 'No statement data', 'Select a date range and tap Run'))
      else
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Summary
            Row(children: [
              Expanded(child: _statCard('Opening Balance', '₹${_statement!.openingBalance.toStringAsFixed(2)}', _navyLight)),
              const SizedBox(width: 10),
              Expanded(child: _statCard('Closing Balance', '₹${_statement!.closingBalance.toStringAsFixed(2)}',
                  _statement!.closingBalance >= 0 ? _green : _red)),
            ]),
            const SizedBox(height: 16),
            // Table
            _card(child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: const BoxDecoration(color: _navyDark, borderRadius: BorderRadius.vertical(top: Radius.circular(6))),
                child: Row(children: const [
                  SizedBox(width: 90,  child: Text('DATE',     style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
                  Expanded(            child: Text('DETAILS',  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
                  SizedBox(width: 80,  child: Text('INVOICES', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5), textAlign: TextAlign.right)),
                  SizedBox(width: 80,  child: Text('PAYMENTS', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5), textAlign: TextAlign.right)),
                  SizedBox(width: 100, child: Text('BALANCE',  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5), textAlign: TextAlign.right)),
                ]),
              ),
              if (_statement!.entries.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('No transactions in this period', style: TextStyle(color: Colors.grey)))
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _statement!.entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final e = _statement!.entries[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(children: [
                        SizedBox(width: 90, child: Text(DateFormat('dd MMM yy').format(e.date),
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]))),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.number, style: const TextStyle(fontSize: 12, color: _navyAccent, fontWeight: FontWeight.w500)),
                          if (e.details.isNotEmpty)
                            Text(e.details, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ])),
                        SizedBox(width: 80, child: Text(
                            e.invoices != null ? '₹${e.invoices!.toStringAsFixed(2)}' : '—',
                            style: TextStyle(fontSize: 12, color: e.invoices != null ? _navyDark : Colors.grey[400], fontWeight: FontWeight.w500),
                            textAlign: TextAlign.right)),
                        SizedBox(width: 80, child: Text(
                            e.payments != null ? '₹${e.payments!.toStringAsFixed(2)}' : '—',
                            style: TextStyle(fontSize: 12, color: e.payments != null ? _green : Colors.grey[400], fontWeight: FontWeight.w500),
                            textAlign: TextAlign.right)),
                        SizedBox(width: 100, child: Text('₹${e.balance.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                                color: e.balance >= 0 ? _navyDark : _red),
                            textAlign: TextAlign.right)),
                      ]),
                    );
                  },
                ),
            ])),
          ]),
        )),
    ]);
  }

  Widget _datePicker(String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context, initialDate: value,
          firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text('$label: ${DateFormat('dd/MM/yyyy').format(value)}',
              style: const TextStyle(fontSize: 12, color: _navyDark)),
        ]),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  // ============================================================================
  // SHARED HELPERS
  // ============================================================================

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _statusBadge(String status) {
    final colors = {
      'Active':   [const Color(0xFFDCFCE7), const Color(0xFF15803D)],
      'Inactive': [const Color(0xFFF1F5F9), const Color(0xFF64748B)],
      'Blocked':  [const Color(0xFFFEE2E2), const Color(0xFFDC2626)],
      'Lead':     [const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)],
      'Closed':   [const Color(0xFFFEF3C7), const Color(0xFFB45309)],
    };
    final c = colors[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: (c[1] as Color).withOpacity(0.3))),
      child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c[1] as Color)),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle, {Widget? action}) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 64, color: Colors.grey[300]),
      const SizedBox(height: 16),
      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _navyDark)),
      if (subtitle.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[500]), textAlign: TextAlign.center),
      ],
      if (action != null) ...[const SizedBox(height: 16), action],
    ]));
  }

  Widget _buildError() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
      const SizedBox(height: 16),
      const Text('Failed to load customer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(_error ?? '', style: TextStyle(color: Colors.grey[600])),
      const SizedBox(height: 16),
      ElevatedButton.icon(onPressed: _loadCustomer, icon: const Icon(Icons.refresh), label: const Text('Retry'),
          style: ElevatedButton.styleFrom(backgroundColor: _navyLight, foregroundColor: Colors.white)),
    ]));
  }
}

// ============================================================================
// NEW TRANSACTION BUTTON
// ============================================================================
class _NewTransactionButton extends StatelessWidget {
  final BillingCustomer customer;
  const _NewTransactionButton({required this.customer});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (v) {
        // Navigate to new invoice/quote etc. pre-filled with customer
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Creating $v for ${customer.customerDisplayName}'),
              behavior: SnackBarBehavior.floating));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: _navyAccent, borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Text('New Transaction', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
        ]),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'Invoice',        child: ListTile(leading: Icon(Icons.description_outlined), title: Text('Invoice'),        contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'Quote',          child: ListTile(leading: Icon(Icons.request_quote_outlined), title: Text('Quote'),         contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'Sales Order',    child: ListTile(leading: Icon(Icons.shopping_cart_outlined), title: Text('Sales Order'),   contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'Credit Note',    child: ListTile(leading: Icon(Icons.note_alt_outlined),     title: Text('Credit Note'),   contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(value: 'Payment',        child: ListTile(leading: Icon(Icons.payment_outlined),       title: Text('Payment'),       contentPadding: EdgeInsets.zero)),
      ],
    );
  }
}

// ============================================================================
// INCOME BAR CHART WIDGET
// ============================================================================
class _IncomeBarChart extends StatelessWidget {
  final List<MonthlyIncome> data;
  final int?  hoveredIndex;
  final void Function(int) onBarTap;

  const _IncomeBarChart({
    required this.data,
    required this.hoveredIndex,
    required this.onBarTap,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Container(
        height: 120,
        alignment: Alignment.center,
        child: Text('No income data', style: TextStyle(color: Colors.grey[400])),
      );
    }

    final maxVal = data.map((d) => d.total).reduce(math.max);
    final fmt = NumberFormat.compact(locale: 'en_IN');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Tooltip
      if (hoveredIndex != null && hoveredIndex! < data.length)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('₹${data[hoveredIndex!].total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
            Text('${data[hoveredIndex!].month} ${data[hoveredIndex!].year}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ]),
        ),
      // Bars
      SizedBox(
        height: 100,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: data.asMap().entries.map((e) {
            final i = e.key;
            final d = e.value;
            final ratio = maxVal > 0 ? d.total / maxVal : 0.0;
            final isHovered = hoveredIndex == i;
            return Expanded(child: GestureDetector(
              onTap: () => onBarTap(i),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: (ratio * 80).clamp(2.0, 80.0),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isHovered ? _navyAccent : (d.total > 0 ? _green.withOpacity(0.75) : Colors.grey[200]),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
              ]),
            ));
          }).toList(),
        ),
      ),
      const SizedBox(height: 6),
      // Labels
      Row(children: data.asMap().entries.map((e) {
        return Expanded(child: Text(e.value.month,
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            textAlign: TextAlign.center));
      }).toList()),
    ]);
  }
}