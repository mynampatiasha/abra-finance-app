import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// CUSTOMER DETAIL PAGE — ZOHO BOOKS STYLE (5 TABS)
// ============================================================================
// File: lib/features/admin/Billing/pages/customer_detail_page.dart
// Tabs: Overview | Comments | Transactions | Mails | Statement
// FIXES:
//   ✅ Transactions table → SingleChildScrollView horizontal, no vertical text
//   ✅ Statement table    → SingleChildScrollView horizontal, no vertical text
//   ✅ Opening Balance    → added to Overview receivables card
//   ✅ All column alignment correct on mobile
// ============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../../../../core/services/billing_customers_service.dart';
import '../../../../core/services/payment_service.dart';
import 'new_customer.dart';
import 'new_invoice.dart';
import 'new_quote.dart';
import 'new_sales_order.dart';
import 'new_credit_note.dart';
import 'new_payment_page.dart';
import 'reminder_settings_page.dart'; // For ReminderService

const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green = Color(0xFF27AE60);
const Color _red = Color(0xFFE74C3C);
const Color _orange = Color(0xFFE67E22);

// ── Transaction table column widths (fixed for horizontal scroll) ──────────
const double _txnColDate = 90.0;
const double _txnColNum = 160.0;
const double _txnColType = 110.0;
const double _txnColStatus = 110.0;
const double _txnColAmt = 110.0;
const double _txnColBal = 110.0;

// ── Statement table column widths ─────────────────────────────────────────
const double _stmColDate = 90.0;
const double _stmColDet = 180.0;
const double _stmColInv = 100.0;
const double _stmColPay = 100.0;
const double _stmColBal = 110.0;

// ============================================================================
class CustomerDetailPage extends StatefulWidget {
  final String customerId;
  const CustomerDetailPage({Key? key, required this.customerId})
      : super(key: key);

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  BillingCustomer? _customer;
  CustomerOverviewData? _overview;
  List<CustomerTransaction>? _transactions;
  List<CustomerMail>? _mails;
  CustomerStatementData? _statement;
  Map<String, dynamic>? _advanceRegister;

  bool _loadingCustomer = true;
  bool _loadingOverview = true;
  bool _loadingTransactions = false;
  bool _loadingMails = false;
  bool _loadingStatement = false;
  bool _loadingAdvances = false;
  String? _error;
  bool _changed = false;

  String _mailFilter = 'All';

  DateTime _statementFrom = DateTime.now().subtract(const Duration(days: 365));
  DateTime _statementTo = DateTime.now();

  int? _hoveredBarIndex;

  final TextEditingController _commentCtrl = TextEditingController();
  bool _postingComment = false;

  // Scroll controllers for horizontal tables
  final ScrollController _txnHScroll = ScrollController();
  final ScrollController _stmHScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCustomer();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentCtrl.dispose();
    _txnHScroll.dispose();
    _stmHScroll.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return; // wait for animation to settle
    switch (_tabController.index) {
      case 0:
        if (_overview == null) _loadOverview();
        break;
      case 1:
        /* comments loaded with customer */ break;
      case 2:
        if (_transactions == null) _loadTransactions();
        break;
      case 3:
        if (_mails == null) _loadMails();
        break;
      case 4:
        if (_statement == null) _loadStatement();
        break;
      case 5:
        if (_advanceRegister == null) _loadAdvanceRegister();
        break;
    }
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadCustomer() async {
    setState(() {
      _loadingCustomer = true;
      _error = null;
    });
    try {
      final c =
          await BillingCustomersService.getCustomerById(widget.customerId);
      setState(() {
        _customer = c;
        _loadingCustomer = false;
      });
      _loadOverview();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingCustomer = false;
      });
    }
  }

  Future<void> _loadOverview() async {
    setState(() => _loadingOverview = true);
    try {
      final o =
          await BillingCustomersService.getCustomerOverview(widget.customerId);
      setState(() {
        _overview = o;
        _loadingOverview = false;
      });
    } catch (_) {
      setState(() => _loadingOverview = false);
    }
  }

  Future<void> _loadTransactions() async {
    setState(() => _loadingTransactions = true);
    try {
      final t = await BillingCustomersService.getCustomerTransactions(
          widget.customerId);
      setState(() {
        _transactions = t;
        _loadingTransactions = false;
      });
    } catch (_) {
      setState(() {
        _transactions = [];
        _loadingTransactions = false;
      });
    }
  }

  Future<void> _loadMails() async {
    setState(() => _loadingMails = true);
    try {
      final m =
          await BillingCustomersService.getCustomerMails(widget.customerId);
      setState(() {
        _mails = m;
        _loadingMails = false;
      });
    } catch (_) {
      setState(() {
        _mails = [];
        _loadingMails = false;
      });
    }
  }

  Future<void> _loadStatement() async {
    setState(() => _loadingStatement = true);
    try {
      final s = await BillingCustomersService.getCustomerStatement(
          widget.customerId,
          fromDate: _statementFrom,
          toDate: _statementTo);
      setState(() {
        _statement = s;
        _loadingStatement = false;
      });
    } catch (_) {
      setState(() {
        _statement = null;
        _loadingStatement = false;
      });
    }
  }

  Future<void> _loadAdvanceRegister() async {
    setState(() => _loadingAdvances = true);
    try {
      final data =
          await PaymentService.getCustomerAdvanceRegister(widget.customerId);
      setState(() {
        _advanceRegister = data;
        _loadingAdvances = false;
      });
    } catch (_) {
      setState(() {
        _advanceRegister = {};
        _loadingAdvances = false;
      });
    }
  }

  Future<void> _postComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _postingComment = true);
    try {
      final comment =
          await BillingCustomersService.addComment(widget.customerId, text);
      setState(() {
        _customer = BillingCustomer.fromJson({
          ..._customer!.toJson(),
          'comments': [
            ..._customer!.comments.map((c) => {
                  '_id': c.id,
                  'text': c.text,
                  'createdBy': c.createdBy,
                  'createdAt': c.createdAt.toIso8601String(),
                }),
            {
              '_id': comment.id,
              'text': comment.text,
              'createdBy': comment.createdBy,
              'createdAt': comment.createdAt.toIso8601String()
            },
          ],
        });
        _commentCtrl.clear();
        _postingComment = false;
      });
    } catch (_) {
      setState(() => _postingComment = false);
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await BillingCustomersService.deleteComment(widget.customerId, commentId);
      setState(() {
        _customer = BillingCustomer.fromJson({
          ..._customer!.toJson(),
          'comments': _customer!.comments
              .where((c) => c.id != commentId)
              .map((c) => {
                    '_id': c.id,
                    'text': c.text,
                    'createdBy': c.createdBy,
                    'createdAt': c.createdAt.toIso8601String()
                  })
              .toList(),
        });
      });
    } catch (_) {}
  }

  void _openEdit() async {
    final result = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => NewCustomerPage(customerId: widget.customerId)));
    if (result == true) {
      setState(() => _changed = true);
      _loadCustomer();
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _changed);
        return false;
      },
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
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          actions: [
            TextButton.icon(
              onPressed: _openEdit,
              icon: const Icon(Icons.edit, color: Colors.white70, size: 16),
              label:
                  const Text('Edit', style: TextStyle(color: Colors.white70)),
            ),
            _NewTransactionButton(customer: c),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, color: Colors.white),
              onSelected: (v) {
                if (v == 'refresh') _loadCustomer();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'refresh',
                    child: ListTile(
                        leading: Icon(Icons.refresh),
                        title: Text('Refresh'),
                        contentPadding: EdgeInsets.zero)),
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
            labelStyle:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Comments'),
              Tab(text: 'Transactions'),
              Tab(text: 'Mails'),
              Tab(text: 'Statement'),
              Tab(text: 'Advances'),
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
          _buildAdvancesTab(),
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
          _avatarCard(c),
          const SizedBox(height: 16),
          _addressCard(c),
          const SizedBox(height: 16),
          _otherDetailsCard(c),
        ]),
      );
      final right = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _card(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Payment due period',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(c.paymentTerms.isEmpty ? 'Due on Receipt' : c.paymentTerms,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _navyDark)),
              ])),
          const SizedBox(height: 16),
          _receivablesCard(),
          const SizedBox(height: 16),
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
    return _card(
        child: Row(children: [
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_navyMid, _navyLight]),
          shape: BoxShape.circle,
        ),
        child: Center(
            child: Text(
          c.customerDisplayName.isNotEmpty
              ? c.customerDisplayName[0].toUpperCase()
              : '?',
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        )),
      ),
      const SizedBox(width: 14),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.customerDisplayName,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: _navyDark)),
        if (c.companyName.isNotEmpty && c.companyName != c.customerDisplayName)
          Text(c.companyName,
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: c.portalEnabled ? _green.withOpacity(0.1) : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: c.portalEnabled
                    ? _green.withOpacity(0.4)
                    : Colors.grey[300]!),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                    color: c.portalEnabled ? _green : Colors.grey,
                    shape: BoxShape.circle)),
            Text(c.portalEnabled ? 'Portal Enabled' : 'Portal not enabled',
                style: TextStyle(
                    fontSize: 11,
                    color: c.portalEnabled ? _green : Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ])),
      _statusBadge(c.customerStatus),
    ]));
  }

  Widget _addressCard(BillingCustomer c) {
    return _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.location_on_outlined, size: 18, color: _navyAccent),
        const SizedBox(width: 6),
        const Text('ADDRESS',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _navyDark,
                letterSpacing: 0.8)),
        const Spacer(),
        InkWell(
            onTap: _openEdit,
            child: const Icon(Icons.keyboard_arrow_up, color: Colors.grey)),
      ]),
      const SizedBox(height: 16),
      // On small screens stack vertically; on wider show side by side
      LayoutBuilder(builder: (ctx, cs) {
        final isWide = cs.maxWidth > 400;
        final billing =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Billing Address',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _navyDark)),
          const SizedBox(height: 6),
          c.billingAddress.isEmpty
              ? TextButton(
                  onPressed: _openEdit,
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('No Billing Address - New Address',
                      style: TextStyle(fontSize: 12, color: _navyAccent)))
              : Text(c.billingAddress.formatted,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[700], height: 1.5)),
        ]);
        final shipping =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Shipping Address',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _navyDark)),
          const SizedBox(height: 6),
          c.shippingAddress.isEmpty
              ? TextButton(
                  onPressed: _openEdit,
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('No Shipping Address - New Address',
                      style: TextStyle(fontSize: 12, color: _navyAccent)))
              : Text(c.shippingAddress.formatted,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[700], height: 1.5)),
        ]);
        if (isWide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: billing),
            const SizedBox(width: 16),
            Expanded(child: shipping),
          ]);
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [billing, const SizedBox(height: 16), shipping]);
      }),
    ]));
  }

  Widget _otherDetailsCard(BillingCustomer c) {
    return _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.info_outline, size: 18, color: _navyAccent),
        const SizedBox(width: 6),
        const Text('OTHER DETAILS',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _navyDark,
                letterSpacing: 0.8)),
        const Spacer(),
        InkWell(
            onTap: _openEdit,
            child: const Icon(Icons.keyboard_arrow_up, color: Colors.grey)),
      ]),
      const SizedBox(height: 16),
      _detailRow('Customer Type', c.customerType),
      _detailRow('Default Currency', c.defaultCurrency),
      if (c.gstNumber.isNotEmpty) _detailRow('GSTIN/UIN', c.gstNumber),
      if (c.gstRegistrationType.isNotEmpty)
        _detailRow('GST Reg. Type', c.gstRegistrationType),
      if (c.placeOfSupply.isNotEmpty)
        _detailRow('Place of Supply', c.placeOfSupply),
      if (c.panNumber.isNotEmpty) _detailRow('PAN Number', c.panNumber),
      if (c.taxPreference.isNotEmpty)
        _detailRow('Tax Preference', c.taxPreference),
      _detailRow(
          'Portal Status',
          c.portalEnabled
              ? '● Enabled\n(${c.contactPersons.length} Contact${c.contactPersons.length == 1 ? '' : 's'})'
              : 'Not enabled'),
    ]));
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(builder: (ctx, cs) {
        // On very narrow screens, stack label above value
        if (cs.maxWidth < 280) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _navyDark)),
              ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: _navyDark))),
        ]);
      }),
    );
  }

  // ── Receivables card — now includes Opening Balance ───────────────────────
  Widget _receivablesCard() {
    return _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Receivables',
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      const SizedBox(height: 12),
      if (_loadingOverview)
        const Center(
            child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(strokeWidth: 2)))
      else ...[
        // ── Opening Balance row ───────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _navyDark.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _navyDark.withOpacity(0.12)),
          ),
          child: Row(children: [
            Expanded(
                child: Text('Opening Balance',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500))),
            Text(
              '₹${(_overview?.customer.openingBalance ?? 0).toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: _navyDark),
            ),
          ]),
        ),
        // ── Header row ───────────────────────────────────────────────────
        Row(children: [
          const Expanded(
              child: Text('CURRENCY',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 0.8))),
          const SizedBox(width: 8),
          SizedBox(
              width: 90,
              child: Text('OUTSTANDING\nRECEIVABLES',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 0.5),
                  textAlign: TextAlign.right)),
          const SizedBox(width: 8),
          SizedBox(
              width: 80,
              child: Text('UNUSED\nCREDITS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 0.5),
                  textAlign: TextAlign.right)),
        ]),
        const Divider(height: 12),
        Row(children: [
          Expanded(
              child: Text(
            '${_overview?.currency ?? 'INR'} - Indian Rupee',
            style: const TextStyle(fontSize: 13, color: _navyDark),
          )),
          const SizedBox(width: 8),
          SizedBox(
              width: 90,
              child: Text(
                '₹${(_overview?.outstandingReceivables ?? 0).toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _navyDark),
                textAlign: TextAlign.right,
              )),
          const SizedBox(width: 8),
          SizedBox(
              width: 80,
              child: Text(
                '₹${(_overview?.unusedCredits ?? 0).toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: (_overview?.unusedCredits ?? 0) > 0
                        ? _navyAccent
                        : _navyDark),
                textAlign: TextAlign.right,
              )),
        ]),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            setState(() => _tabController.index = 2);
            _loadTransactions();
          },
          child: const Text('Enter Opening Balance',
              style: TextStyle(
                  fontSize: 13,
                  color: _navyAccent,
                  fontWeight: FontWeight.w500)),
        ),
      ],
    ]));
  }

  Widget _incomeChartCard() {
    return _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Income',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
          Text('Displayed in organisation\'s base currency.',
              style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          _chipBtn('Last 6 Months'),
          _chipBtn('Accrual'),
        ],
      ),
      const SizedBox(height: 16),
      if (_loadingOverview)
        const Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2)))
      else
        _IncomeBarChart(
          data: _overview?.monthlyIncome ?? [],
          hoveredIndex: _hoveredBarIndex,
          onBarTap: (i) => setState(
              () => _hoveredBarIndex = _hoveredBarIndex == i ? null : i),
        ),
    ]));
  }

  Widget _chipBtn(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12)),
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
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: _navyLight, width: 1.5)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              backgroundColor: _navyLight,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: _postingComment
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Post'),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: comments.isEmpty
            ? _emptyState(Icons.comment_outlined, 'No comments yet',
                'Add the first comment above')
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: comments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final comment = comments[i];
                  return _card(
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                              color: _navyLight.withOpacity(0.12),
                              shape: BoxShape.circle),
                          child: Center(
                              child: Text(
                            comment.createdBy.isNotEmpty
                                ? comment.createdBy[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: _navyLight, fontWeight: FontWeight.bold),
                          )),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  children: [
                                    Text(comment.createdBy,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: _navyDark)),
                                    Text(
                                        DateFormat('dd MMM yyyy, hh:mm a')
                                            .format(comment.createdAt),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500])),
                                  ]),
                              const SizedBox(height: 6),
                              Text(comment.text,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[800],
                                      height: 1.4)),
                            ])),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: Colors.red[400]),
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
  // TAB 3 — TRANSACTIONS (horizontal scrollable, no vertical text)
  // ============================================================================

  Widget _buildTransactionsTab() {
    if (_loadingTransactions)
      return const Center(child: CircularProgressIndicator(color: _navyLight));
    if (_transactions == null) {
      return _emptyState(Icons.sync, 'Loading transactions...', '',
          action: ElevatedButton.icon(
              onPressed: _loadTransactions,
              icon: const Icon(Icons.refresh),
              label: const Text('Load')));
    }
    if (_transactions!.isEmpty)
      return _emptyState(Icons.receipt_long, 'No transactions yet',
          'Transactions will appear here once invoices are created');

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.white,
        child: Text(
            '${_transactions!.length} transaction${_transactions!.length == 1 ? '' : 's'}',
            style:
                const TextStyle(fontWeight: FontWeight.bold, color: _navyDark)),
      ),
      const Divider(height: 1),
      Expanded(
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ],
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            return Scrollbar(
              controller: _txnHScroll,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 8,
              radius: const Radius.circular(4),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad
                    }),
                child: SingleChildScrollView(
                  controller: _txnHScroll,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(_navyDark),
                      headingTextStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.4),
                      headingRowHeight: 52,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 64,
                      dataTextStyle: const TextStyle(fontSize: 13),
                      dataRowColor: WidgetStateProperty.resolveWith((s) {
                        if (s.contains(WidgetState.hovered))
                          return _navyDark.withOpacity(0.04);
                        return null;
                      }),
                      dividerThickness: 1,
                      columnSpacing: 16,
                      horizontalMargin: 14,
                      columns: const [
                        DataColumn(label: Text('DATE')),
                        DataColumn(label: Text('NUMBER')),
                        DataColumn(label: Text('TYPE')),
                        DataColumn(label: Text('STATUS')),
                        DataColumn(label: Text('AMOUNT'), numeric: true),
                        DataColumn(label: Text('BALANCE'), numeric: true),
                      ],
                      rows: _transactions!.asMap().entries.map((entry) {
                        final i = entry.key;
                        final t = entry.value;
                        final isInvoice = t.type == 'Invoice';
                        return DataRow(
                          color: WidgetStateProperty.resolveWith((s) {
                            if (s.contains(WidgetState.hovered))
                              return _navyDark.withOpacity(0.04);
                            return i.isOdd
                                ? const Color(0xFFF7F9FC)
                                : Colors.white;
                          }),
                          cells: [
                            DataCell(Text(
                                DateFormat('dd/MM/yyyy').format(t.date),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[700]))),
                            DataCell(Text(t.number,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: _navyAccent,
                                    fontWeight: FontWeight.w600))),
                            DataCell(
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(
                                  isInvoice
                                      ? Icons.description_outlined
                                      : Icons.payment,
                                  size: 14,
                                  color: isInvoice ? _navyMid : _green),
                              const SizedBox(width: 4),
                              Text(t.type,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: isInvoice ? _navyMid : _green,
                                      fontWeight: FontWeight.w500)),
                            ])),
                            DataCell(_txnStatusBadge(t.status)),
                            DataCell(Text('₹${t.amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _navyDark))),
                            DataCell(Text(
                                t.balance > 0
                                    ? '₹${t.balance.toStringAsFixed(2)}'
                                    : '—',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: t.balance > 0
                                        ? _red
                                        : Colors.grey[500]))),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            );
          }),
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
    final c =
        colors[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(10)),
      child: Text(status.replaceAll('_', ' '),
          style:
              TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: c[1]),
          overflow: TextOverflow.ellipsis),
    );
  }

  // ============================================================================
  // TAB 4 — MAILS
  // ============================================================================

  Widget _buildMailsTab() {
    if (_loadingMails) {
      return const Center(child: CircularProgressIndicator(color: _navyLight));
    }
    if (_mails == null) {
      return _emptyState(Icons.mail_outline, 'Loading mails...', '',
          action: ElevatedButton.icon(
            onPressed: _loadMails,
            icon: const Icon(Icons.refresh),
            label: const Text('Load'),
          ));
    }

    // ── Filter ─────────────────────────────────────────────────────────────
    final filtered = _mailFilter == 'All'
        ? _mails!
        : _mails!.where((m) {
            if (_mailFilter == 'Invoice') return m.emailType == 'invoice';
            if (_mailFilter == 'Reminder')
              return m.emailType == 'reminder' && m.channel == 'email';
            if (_mailFilter == 'WhatsApp') return m.channel == 'whatsapp';
            if (_mailFilter == 'Payment Receipt')
              return m.emailType == 'payment_receipt';
            return true;
          }).toList();

    // ── Counts ─────────────────────────────────────────────────────────────
    final whatsappCount = _mails!.where((m) => m.channel == 'whatsapp').length;
    final invoiceCount = _mails!.where((m) => m.emailType == 'invoice').length;
    final reminderCount = _mails!
        .where((m) => m.emailType == 'reminder' && m.channel == 'email')
        .length;
    final receiptCount =
        _mails!.where((m) => m.emailType == 'payment_receipt').length;

    return Column(children: [
      // ── Filter bar ────────────────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(
              '${_mails!.length} message${_mails!.length == 1 ? '' : 's'} total',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: _navyDark, fontSize: 13),
            )),
            // WhatsApp preview buttons
            TextButton.icon(
              onPressed: () => _showWhatsAppPreviewDialog('overdue'),
              icon: const Icon(Icons.chat_rounded,
                  size: 14, color: Color(0xFF25D366)),
              label: const Text('Preview Overdue',
                  style: TextStyle(fontSize: 11, color: Color(0xFF25D366))),
              style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            ),
            TextButton.icon(
              onPressed: () => _showWhatsAppPreviewDialog('predue'),
              icon: const Icon(Icons.chat_rounded,
                  size: 14, color: Color(0xFFD97706)),
              label: const Text('Preview Pre-Due',
                  style: TextStyle(fontSize: 11, color: Color(0xFFD97706))),
              style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            ),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _mailFilterChip('All', _mails!.length),
              const SizedBox(width: 6),
              _mailFilterChip('Invoice', invoiceCount),
              const SizedBox(width: 6),
              _mailFilterChip('Reminder', reminderCount, color: _orange),
              const SizedBox(width: 6),
              _mailFilterChip('WhatsApp', whatsappCount,
                  color: const Color(0xFF25D366)),
              const SizedBox(width: 6),
              _mailFilterChip('Payment Receipt', receiptCount, color: _green),
            ]),
          ),
        ]),
      ),

      const Divider(height: 1),

      // ── List ─────────────────────────────────────────────────────────────
      if (filtered.isEmpty)
        Expanded(
            child: _emptyState(
          Icons.mark_email_unread_outlined,
          'No ${_mailFilter == 'All' ? '' : _mailFilter} messages',
          '',
        ))
      else
        Expanded(
            child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _buildMailCard(filtered[i]),
        )),
    ]);
  }

  Widget _buildMailCard(CustomerMail m) {
    final isWhatsApp = m.channel == 'whatsapp';
    final isOverdue = m.reminderType == 'overdue';
    final isPredue = m.reminderType == 'predue';

    final Color color = isWhatsApp
        ? (isOverdue
            ? _red
            : isPredue
                ? _orange
                : const Color(0xFF25D366))
        : m.emailType == 'payment_receipt'
            ? _green
            : m.emailType == 'reminder'
                ? _orange
                : _navyLight;

    final IconData icon = isWhatsApp
        ? Icons.chat_rounded
        : m.emailType == 'payment_receipt'
            ? Icons.receipt_outlined
            : m.emailType == 'reminder'
                ? Icons.notifications_outlined
                : Icons.email_outlined;

    final String typeLabel = isWhatsApp
        ? 'WhatsApp ${isOverdue ? 'Overdue' : isPredue ? 'Pre-Due' : 'Reminder'}'
        : m.emailType == 'payment_receipt'
            ? 'Payment Receipt'
            : m.emailType == 'reminder'
                ? 'Reminder Email'
                : 'Invoice Email';

    return _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        // Channel icon
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(
              m.subject,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13, color: _navyDark),
              overflow: TextOverflow.ellipsis,
            )),
            // Success/fail badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: m.success
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                m.success ? '✓ Sent' : '✗ Failed',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: m.success
                      ? const Color(0xFF15803D)
                      : const Color(0xFFDC2626),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 3),
          // To: line — phone for WA, email for others
          Text(
            isWhatsApp
                ? 'To: ${m.customerPhone.isNotEmpty ? m.customerPhone : m.sentTo}'
                : 'To: ${m.sentTo}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Text(
            'Invoice: ${m.invoiceNumber}  •  ₹${m.amount.toStringAsFixed(2)}'
            '${m.amountDue > 0 ? '  •  Due: ₹${m.amountDue.toStringAsFixed(2)}' : ''}',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          if (m.failReason != null && m.failReason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Error: ${m.failReason}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(DateFormat('dd MMM yyyy').format(m.sentAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          const SizedBox(height: 4),
          Text(DateFormat('hh:mm a').format(m.sentAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ]),
      ]),
      const SizedBox(height: 10),
      // Type badge + preview button
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(typeLabel,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ),
        if (isWhatsApp) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _showWhatsAppMessagePreview(m),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: const Color(0xFF25D366).withOpacity(0.4)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.visibility_outlined,
                    size: 12, color: Color(0xFF25D366)),
                SizedBox(width: 4),
                Text('View Message',
                    style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF25D366),
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ],
      ]),
    ]));
  }

  Widget _mailFilterChip(String label, int count, {Color color = _navyDark}) {
    final isSelected = _mailFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _mailFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white.withOpacity(0.25)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── WhatsApp message preview from reminder log ────────────────────────────────
  void _showWhatsAppMessagePreview(CustomerMail m) {
    final isOverdue = m.reminderType == 'overdue';
    final color = isOverdue ? _red : _orange;
    final customer = _customer!;

    // Rebuild the message text using the same template logic
    final customerName = customer.customerDisplayName;
    final phone = customer.primaryPhone;
    final invoiceNumber = m.invoiceNumber;
    final amountDue = m.amountDue > 0
        ? m.amountDue.toStringAsFixed(2)
        : m.amount.toStringAsFixed(2);

    final message = isOverdue
        ? 'Hello *$customerName*,\n\nInvoice *$invoiceNumber* is *overdue*.\n\nBalance Due: Rs. $amountDue\n\nPlease arrange payment at the earliest.\n\nThank you!'
        : 'Hello *$customerName*,\n\nInvoice *$invoiceNumber* payment is due soon.\n\nAmount Due: Rs. $amountDue\n\nPlease arrange payment before the due date.\n\nThank you!';

    _showWhatsAppBubbleDialog(
      type: isOverdue ? 'overdue' : 'predue',
      message: message,
      phone: phone,
      invoiceNumber: invoiceNumber,
      customerName: customerName,
      isLiveMessage: true,
      sentAt: m.sentAt,
      success: m.success,
      failReason: m.failReason,
    );
  }

  // ── WhatsApp preview dialog (for preview buttons — test data) ─────────────────
  void _showWhatsAppPreviewDialog(String type) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
          child: CircularProgressIndicator(color: Color(0xFF25D366))),
    );

    try {
      final result = await ReminderService.getWhatsAppPreview(type);
      if (!mounted) return;
      Navigator.pop(context); // close loader

      final data = result;
      _showWhatsAppBubbleDialog(
        type: type,
        message: data['message'] ?? '',
        phone: data['testPhone'] ?? '+91 98765 43210',
        invoiceNumber: data['invoiceNumber'] ?? 'INV-2024-0042',
        customerName: data['customerName'] ?? 'Rajesh Kumar',
        isLiveMessage: false,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Could not load preview: $e', error: true);
    }
  }

  // ── The actual WhatsApp bubble dialog ──────────────────────────────────────────
  void _showWhatsAppBubbleDialog({
    required String type,
    required String message,
    required String phone,
    required String invoiceNumber,
    required String customerName,
    required bool isLiveMessage,
    DateTime? sentAt,
    bool? success,
    String? failReason,
  }) {
    final isOverdue = type == 'overdue';
    final color = isOverdue ? _red : _orange;
    final label = isOverdue ? 'Overdue Reminder' : 'Pre-Due Reminder';
    final bgColor =
        isOverdue ? const Color(0xFFFFF1F1) : const Color(0xFFFFFBEB);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: Color(0xFF128C7E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      isLiveMessage ? customerName : 'Preview — $customerName',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                    Text(
                      phone,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ])),
              // Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.5)),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ]),
          ),

          // ── WhatsApp chat background ───────────────────────────────────────
          Container(
            color: const Color(0xFFECE5DD), // WhatsApp chat bg
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              // Date chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isLiveMessage && sentAt != null
                      ? DateFormat('dd MMM yyyy').format(sentAt)
                      : DateFormat('dd MMM yyyy').format(DateTime.now()),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF555555)),
                ),
              ),
              const SizedBox(height: 12),

              // Message bubble (right side — sender)
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 300),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCF8C6), // WhatsApp green bubble
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 4,
                          offset: const Offset(1, 2)),
                    ],
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Message text — bold markers rendered
                        _buildWhatsAppText(message),
                        const SizedBox(height: 4),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            isLiveMessage && sentAt != null
                                ? DateFormat('hh:mm a').format(sentAt)
                                : DateFormat('hh:mm a').format(DateTime.now()),
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF777777)),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.done_all,
                            size: 14,
                            color: (success == false)
                                ? _red
                                : const Color(0xFF4FC3F7),
                          ),
                        ]),
                      ]),
                ),
              ),

              // Fail reason if any
              if (isLiveMessage && success == false && failReason != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        size: 14, color: Color(0xFFDC2626)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(
                      'Failed: $failReason',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF991B1B)),
                    )),
                  ]),
                ),
              ],

              const SizedBox(height: 8),

              // Info label
              if (!isLiveMessage)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'This is a preview with test data.\nActual messages use real invoice details.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[600], height: 1.4),
                  ),
                ),
            ]),
          ),

          // ── Footer ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(children: [
              Expanded(
                  child: Text(
                'Invoice: $invoiceNumber',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              )),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close', style: TextStyle(color: _navyDark)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Render WhatsApp bold markers (*text*) ──────────────────────────────────────
  Widget _buildWhatsAppText(String message) {
    final lines = message.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final spans = <TextSpan>[];
        final parts = line.split('*');
        for (int i = 0; i < parts.length; i++) {
          spans.add(TextSpan(
            text: parts[i],
            style: TextStyle(
              fontSize: 13,
              color: const Color(0xFF111111),
              fontWeight: i.isOdd ? FontWeight.bold : FontWeight.normal,
            ),
          ));
        }
        return RichText(text: TextSpan(children: spans));
      }).toList(),
    );
  }

  // ============================================================================
  // TAB 5 — STATEMENT (horizontal scrollable, no vertical text)
  // ============================================================================

  Widget _buildStatementTab() {
    return Column(children: [
      // ── Date range picker bar ─────────────────────────────────────────────
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: Colors.white,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            const Text('Period:',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _navyDark)),
            const SizedBox(width: 10),
            _datePicker('From', _statementFrom, (d) {
              setState(() => _statementFrom = d);
              _loadStatement();
            }),
            const SizedBox(width: 10),
            _datePicker('To', _statementTo, (d) {
              setState(() => _statementTo = d);
              _loadStatement();
            }),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _loadStatement,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyLight,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Run', style: TextStyle(fontSize: 13)),
            ),
          ]),
        ),
      ),
      const Divider(height: 1),

      if (_loadingStatement)
        const Expanded(
            child: Center(child: CircularProgressIndicator(color: _navyLight)))
      else if (_statement == null)
        Expanded(
            child: _emptyState(Icons.bar_chart, 'No statement data',
                'Select a date range and tap Run'))
      else ...[
        // ── Opening / Closing balance cards ────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
                child: _statCard(
                    'Opening Balance',
                    '₹${_statement!.openingBalance.toStringAsFixed(2)}',
                    _navyLight)),
            const SizedBox(width: 10),
            Expanded(
                child: _statCard(
                    'Closing Balance',
                    '₹${_statement!.closingBalance.toStringAsFixed(2)}',
                    _statement!.closingBalance >= 0 ? _green : _red)),
          ]),
        ),

        // ── DataTable ──────────────────────────────────────────────────────
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
            ),
            child: _statement!.entries.isEmpty
                ? Center(
                    child: Text('No transactions in this period',
                        style: TextStyle(color: Colors.grey[500])))
                : LayoutBuilder(builder: (context, constraints) {
                    return Scrollbar(
                      controller: _stmHScroll,
                      thumbVisibility: true,
                      trackVisibility: true,
                      thickness: 8,
                      radius: const Radius.circular(4),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                            dragDevices: {
                              PointerDeviceKind.touch,
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.trackpad
                            }),
                        child: SingleChildScrollView(
                          controller: _stmHScroll,
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minWidth: constraints.maxWidth),
                            child: DataTable(
                              headingRowColor:
                                  WidgetStateProperty.all(_navyDark),
                              headingTextStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 0.4),
                              headingRowHeight: 52,
                              dataRowMinHeight: 52,
                              dataRowMaxHeight: 68,
                              dataTextStyle: const TextStyle(fontSize: 13),
                              dataRowColor:
                                  WidgetStateProperty.resolveWith((s) {
                                if (s.contains(WidgetState.hovered))
                                  return _navyDark.withOpacity(0.04);
                                return null;
                              }),
                              dividerThickness: 1,
                              columnSpacing: 16,
                              horizontalMargin: 14,
                              columns: const [
                                DataColumn(label: Text('DATE')),
                                DataColumn(label: Text('DETAILS')),
                                DataColumn(
                                    label: Text('INVOICES'), numeric: true),
                                DataColumn(
                                    label: Text('PAYMENTS'), numeric: true),
                                DataColumn(
                                    label: Text('BALANCE'), numeric: true),
                              ],
                              rows: _statement!.entries
                                  .asMap()
                                  .entries
                                  .map((entry) {
                                final i = entry.key;
                                final e = entry.value;
                                return DataRow(
                                  color: WidgetStateProperty.resolveWith((s) {
                                    if (s.contains(WidgetState.hovered))
                                      return _navyDark.withOpacity(0.04);
                                    return i.isOdd
                                        ? const Color(0xFFF7F9FC)
                                        : Colors.white;
                                  }),
                                  cells: [
                                    DataCell(Text(
                                        DateFormat('dd/MM/yyyy').format(e.date),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700]))),
                                    DataCell(Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(e.number,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: _navyAccent,
                                                fontWeight: FontWeight.w500)),
                                        if (e.details.isNotEmpty)
                                          Text(e.details,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[500])),
                                      ],
                                    )),
                                    DataCell(Text(
                                        e.invoices != null
                                            ? '₹${e.invoices!.toStringAsFixed(2)}'
                                            : '—',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: e.invoices != null
                                                ? _navyDark
                                                : Colors.grey[400],
                                            fontWeight: FontWeight.w500))),
                                    DataCell(Text(
                                        e.payments != null
                                            ? '₹${e.payments!.toStringAsFixed(2)}'
                                            : '—',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: e.payments != null
                                                ? _green
                                                : Colors.grey[400],
                                            fontWeight: FontWeight.w500))),
                                    DataCell(Text(
                                        '₹${e.balance.toStringAsFixed(2)}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: e.balance >= 0
                                                ? _navyDark
                                                : _red))),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
          ),
        ),
      ],
    ]);
  }

  Widget _datePicker(
      String label, DateTime value, ValueChanged<DateTime> onChanged) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
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
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color)),
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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: child,
    );
  }

  Widget _statusBadge(String status) {
    final colors = {
      'Active': [const Color(0xFFDCFCE7), const Color(0xFF15803D)],
      'Inactive': [const Color(0xFFF1F5F9), const Color(0xFF64748B)],
      'Blocked': [const Color(0xFFFEE2E2), const Color(0xFFDC2626)],
      'Lead': [const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)],
      'Closed': [const Color(0xFFFEF3C7), const Color(0xFFB45309)],
    };
    final c =
        colors[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: c[0],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: (c[1] as Color).withOpacity(0.3))),
      child: Text(status,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: c[1] as Color)),
    );
  }

  Widget _emptyState(IconData icon, String title, String subtitle,
      {Widget? action}) {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 64, color: Colors.grey[300]),
      const SizedBox(height: 16),
      Text(title,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: _navyDark)),
      if (subtitle.isNotEmpty) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              textAlign: TextAlign.center),
        ),
      ],
      if (action != null) ...[const SizedBox(height: 16), action],
    ]));
  }

  // ============================================================================
  // TAB 6 — ADVANCES
  // ============================================================================

  Widget _buildAdvancesTab() {
    if (_loadingAdvances) {
      return const Center(child: CircularProgressIndicator(color: _navyLight));
    }
    if (_advanceRegister == null) {
      return _emptyState(
        Icons.account_balance_wallet_outlined,
        'Loading advance register...',
        '',
        action: ElevatedButton.icon(
          onPressed: _loadAdvanceRegister,
          icon: const Icon(Icons.refresh),
          label: const Text('Load'),
          style: ElevatedButton.styleFrom(
              backgroundColor: _navyLight, foregroundColor: Colors.white),
        ),
      );
    }

    final summary = _advanceRegister!['summary'] as Map? ?? {};
    final advances = (_advanceRegister!['advances'] as List? ?? []);
    final utilization =
        (_advanceRegister!['utilizationHistory'] as List? ?? []);
    final fmt = (dynamic v) =>
        '₹${(double.tryParse(v?.toString() ?? '0') ?? 0).toStringAsFixed(2)}';
    final fmtDate = (dynamic d) {
      if (d == null) return '—';
      try {
        return DateFormat('dd MMM yyyy').format(DateTime.parse(d.toString()));
      } catch (_) {
        return d.toString();
      }
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Summary cards ──────────────────────────────────────────────────
        Row(children: [
          _advSummaryCard('Total Advanced', fmt(summary['totalAdvanced']),
              Icons.arrow_downward, Colors.blue.shade700, Colors.blue.shade50),
          const SizedBox(width: 12),
          _advSummaryCard(
              'Total Utilized',
              fmt(summary['totalUtilized']),
              Icons.check_circle_outline,
              Colors.orange.shade700,
              Colors.orange.shade50),
          const SizedBox(width: 12),
          _advSummaryCard(
              'Available Balance',
              fmt(summary['availableBalance']),
              Icons.account_balance_wallet,
              Colors.green.shade700,
              Colors.green.shade50),
        ]),

        const SizedBox(height: 20),

        // ── Advance payments list ──────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Advance Payments',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
          ElevatedButton.icon(
            onPressed: _loadAdvanceRegister,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyLight,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ]),
        const SizedBox(height: 10),

        if (advances.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Column(children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text('No advance payments recorded',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14)),
              ]),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Column(children: [
              // Table header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [_navyDark, _navyMid]),
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10)),
                ),
                child: const Row(children: [
                  Expanded(
                      flex: 2,
                      child: Text('DATE',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12))),
                  Expanded(
                      flex: 2,
                      child: Text('RECEIPT #',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12))),
                  Expanded(
                      flex: 2,
                      child: Text('MODE',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12))),
                  Expanded(
                      flex: 2,
                      child: Text('AMOUNT',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                          textAlign: TextAlign.right)),
                  Expanded(
                      flex: 2,
                      child: Text('NET CREDIT',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                          textAlign: TextAlign.right)),
                  Expanded(
                      flex: 1,
                      child: Text('STATUS',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                          textAlign: TextAlign.center)),
                ]),
              ),
              // Rows
              ...advances.asMap().entries.map((e) {
                final idx = e.key;
                final a = e.value as Map;
                final bg =
                    idx % 2 == 0 ? Colors.white : const Color(0xFFF8F9FA);
                return Container(
                  color: bg,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                        flex: 2,
                        child: Text(fmtDate(a['date']),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]))),
                    Expanded(
                        flex: 2,
                        child: Text(a['paymentNumber']?.toString() ?? '—',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _navyAccent))),
                    Expanded(
                        flex: 2,
                        child: Text(a['paymentMode']?.toString() ?? '—',
                            style: const TextStyle(fontSize: 12))),
                    Expanded(
                        flex: 2,
                        child: Text(fmt(a['amount']),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 12))),
                    Expanded(
                        flex: 2,
                        child: Text(fmt(a['netAmount']),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF15803D)))),
                    Expanded(
                        flex: 1,
                        child: Center(
                            child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                              a['status']?.toString().toUpperCase() ?? 'PAID',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800)),
                        ))),
                  ]),
                );
              }),
            ]),
          ),

        const SizedBox(height: 24),

        // ── Utilization history ────────────────────────────────────────────
        if (utilization.isNotEmpty) ...[
          const Text('Credit Utilization History',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Column(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF15803D), Color(0xFF166534)]),
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10)),
                ),
                child: const Row(children: [
                  Expanded(
                      flex: 2,
                      child: Text('DATE',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12))),
                  Expanded(
                      flex: 2,
                      child: Text('PAYMENT #',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12))),
                  Expanded(
                      flex: 2,
                      child: Text('CREDITS APPLIED',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                          textAlign: TextAlign.right)),
                ]),
              ),
              ...utilization.asMap().entries.map((e) {
                final idx = e.key;
                final u = e.value as Map;
                final bg =
                    idx % 2 == 0 ? Colors.white : const Color(0xFFF8F9FA);
                return Container(
                  color: bg,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                        flex: 2,
                        child: Text(fmtDate(u['date']),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]))),
                    Expanded(
                        flex: 2,
                        child: Text(u['paymentNumber']?.toString() ?? '—',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _navyAccent))),
                    Expanded(
                        flex: 2,
                        child: Text(fmt(u['creditsApplied']),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDC2626)))),
                  ]),
                );
              }),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _advSummaryCard(
      String label, String value, IconData icon, Color color, Color bg) {
    return Expanded(
        child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ]),
    ));
  }

  Widget _buildError() {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
      const SizedBox(height: 16),
      const Text('Failed to load customer',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(_error ?? '',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center),
      ),
      const SizedBox(height: 16),
      ElevatedButton.icon(
          onPressed: _loadCustomer,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
              backgroundColor: _navyLight, foregroundColor: Colors.white)),
    ]));
  }
}

// ── Table header text style (used in both tabs) ───────────────────────────────
const TextStyle _thStyle = TextStyle(
  color: Colors.white,
  fontSize: 11,
  fontWeight: FontWeight.bold,
  letterSpacing: 0.5,
);

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
        switch (v) {
          case 'Invoice':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewInvoiceScreen(),
              ),
            );
            break;
          case 'Quote':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewQuoteScreen(),
              ),
            );
            break;
          case 'Sales Order':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewSalesOrderScreen(),
              ),
            );
            break;
          case 'Credit Note':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewCreditNoteScreen(),
              ),
            );
            break;
          case 'Payment':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewPaymentPage(
                  prefilledCustomerName: customer.customerDisplayName,
                ),
              ),
            );
            break;
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
            color: _navyAccent, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Text('New Transaction',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
        ]),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(
            value: 'Invoice',
            child: ListTile(
                leading: Icon(Icons.description_outlined),
                title: Text('Invoice'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'Quote',
            child: ListTile(
                leading: Icon(Icons.request_quote_outlined),
                title: Text('Quote'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'Sales Order',
            child: ListTile(
                leading: Icon(Icons.shopping_cart_outlined),
                title: Text('Sales Order'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'Credit Note',
            child: ListTile(
                leading: Icon(Icons.note_alt_outlined),
                title: Text('Credit Note'),
                contentPadding: EdgeInsets.zero)),
        const PopupMenuItem(
            value: 'Payment',
            child: ListTile(
                leading: Icon(Icons.payment_outlined),
                title: Text('Payment'),
                contentPadding: EdgeInsets.zero)),
      ],
    );
  }
}

// ============================================================================
// INCOME BAR CHART WIDGET
// ============================================================================
class _IncomeBarChart extends StatelessWidget {
  final List<MonthlyIncome> data;
  final int? hoveredIndex;
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
        child:
            Text('No income data', style: TextStyle(color: Colors.grey[400])),
      );
    }

    final maxVal = data.map((d) => d.total).reduce(math.max);

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
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            ],
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('₹${data[hoveredIndex!].total.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _navyDark)),
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
            return Expanded(
                child: GestureDetector(
              onTap: () => onBarTap(i),
              child:
                  Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: (ratio * 80).clamp(2.0, 80.0),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isHovered
                        ? _navyAccent
                        : (d.total > 0
                            ? _green.withOpacity(0.75)
                            : Colors.grey[200]),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
              ]),
            ));
          }).toList(),
        ),
      ),
      const SizedBox(height: 6),
      // Month labels
      Row(
          children: data.asMap().entries.map((e) {
        return Expanded(
            child: Text(e.value.month,
                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                textAlign: TextAlign.center));
      }).toList()),
    ]);
  }
}
