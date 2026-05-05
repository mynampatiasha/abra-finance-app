// ============================================================================
// VENDOR DETAIL PAGE — ZOHO BOOKS STYLE
// ============================================================================
// File: lib/screens/billing/pages/vendor_detail_page.dart
//
// 5 TABS exactly like Zoho Books:
//   1. Overview        — responsive two-column on wide, avatar card, address
//                        cards, other details, payables card, expense bar chart
//   2. Comments        — add / delete internal comments with timestamp
//   3. Transactions    — horizontal-scrollable DataTable (no vertical text)
//   4. Mails           — all emails sent related to this vendor
//   5. Statement       — horizontal-scrollable DataTable, date range picker
//
// CHANGES vs previous version:
//   ✅ Transactions table  → DataTable inside horizontal SingleChildScrollView
//   ✅ Statement table     → DataTable inside horizontal SingleChildScrollView
//   ✅ Overview layout     → responsive two-column (>800px) / stacked (<800px)
//   ✅ Scrollbar + touch/mouse/trackpad drag support on both tables
//   ✅ Type & Status badge colours UNCHANGED from original
//   ✅ SliverAppBar gradient header UNCHANGED
// ============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/billing_vendors_service.dart';
import '../../../../core/services/payment_made_service.dart';
import 'new_vendor.dart';

// ── Colours ───────────────────────────────────────────────────────────────────
const Color _navy       = Color(0xFF1e3a8a);
const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _green      = Color(0xFF27AE60);
const Color _red        = Color(0xFFE74C3C);
const Color _orange     = Color(0xFFE67E22);
const Color _purple     = Color(0xFF9B59B6);

final _fmt     = NumberFormat('#,##,##0.00', 'en_IN');
final _dateFmt = DateFormat('dd MMM yyyy');

// =============================================================================
//  PAGE
// =============================================================================

class VendorDetailPage extends StatefulWidget {
  final String vendorId;
  const VendorDetailPage({Key? key, required this.vendorId}) : super(key: key);

  @override
  State<VendorDetailPage> createState() => _VendorDetailPageState();
}

class _VendorDetailPageState extends State<VendorDetailPage>
    with SingleTickerProviderStateMixin {

  late TabController _tabCtrl;

  BillingVendor?      _vendor;
  VendorOverviewData? _overview;
  bool _loadingVendor   = true;
  bool _loadingOverview = true;

  // Transactions
  List<VendorTransaction> _transactions = [];
  bool _loadingTxns = true;

  // Mails
  List<VendorMail> _mails = [];
  bool _loadingMails = true;

  // Statement
  Map<String, dynamic>? _statement;
  bool _loadingStatement = false;
  DateTime _stmtFrom = DateTime.now().subtract(const Duration(days: 90));
  DateTime _stmtTo   = DateTime.now();
  String?  _stmtErr;

  // Comments
  final _commentCtrl    = TextEditingController();
  bool  _postingComment = false;

  // Bar chart tooltip
  int? _hoveredBarIndex;

  // Advances
  List<Map<String, dynamic>> _advances     = [];
  bool   _advancesLoading = false;
  double _totalAdvance    = 0;
  double _totalUnused     = 0;

  // Horizontal scroll controllers for DataTables
  final ScrollController _txnHScroll = ScrollController();
  final ScrollController _stmHScroll = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    _loadVendor();
    _loadOverview();
    _loadTransactions();
    _loadMails();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _commentCtrl.dispose();
    _txnHScroll.dispose();
    _stmHScroll.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabCtrl.indexIsChanging) return;
    if (_tabCtrl.index == 4 && _statement == null) _loadStatement();
    if (_tabCtrl.index == 5 && _advances.isEmpty) _loadAdvances();
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadVendor() async {
    setState(() => _loadingVendor = true);
    try {
      final result = await BillingVendorsService.getVendorById(widget.vendorId);
      if (result['success'] == true) {
        setState(() {
          _vendor        = BillingVendor.fromJson(result['data']);
          _loadingVendor = false;
        });
      }
    } catch (e) {
      setState(() => _loadingVendor = false);
    }
  }

  Future<void> _loadOverview() async {
    setState(() => _loadingOverview = true);
    try {
      final data = await BillingVendorsService.getVendorOverview(widget.vendorId);
      setState(() { _overview = data; _loadingOverview = false; });
    } catch (e) {
      setState(() => _loadingOverview = false);
    }
  }

  Future<void> _loadTransactions() async {
    setState(() => _loadingTxns = true);
    try {
      final list = await BillingVendorsService.getVendorTransactions(widget.vendorId);
      setState(() { _transactions = list; _loadingTxns = false; });
    } catch (e) {
      setState(() => _loadingTxns = false);
    }
  }

  Future<void> _loadMails() async {
    setState(() => _loadingMails = true);
    try {
      final list = await BillingVendorsService.getVendorMails(widget.vendorId);
      setState(() { _mails = list; _loadingMails = false; });
    } catch (e) {
      setState(() => _loadingMails = false);
    }
  }

  Future<void> _loadStatement() async {
    setState(() { _loadingStatement = true; _stmtErr = null; });
    try {
      final data = await BillingVendorsService.getVendorStatement(
        widget.vendorId,
        fromDate: _stmtFrom.toIso8601String(),
        toDate  : _stmtTo.toIso8601String(),
      );
      setState(() { _statement = data; _loadingStatement = false; });
    } catch (e) {
      setState(() { _loadingStatement = false; _stmtErr = e.toString(); });
    }
  }

  Future<void> _postComment() async {
    if (_commentCtrl.text.trim().isEmpty) return;
    setState(() => _postingComment = true);
    try {
      await BillingVendorsService.addComment(
          widget.vendorId, _commentCtrl.text.trim());
      _commentCtrl.clear();
      await _loadVendor();
      setState(() => _postingComment = false);
    } catch (e) {
      setState(() => _postingComment = false);
      _showError('Failed to add comment: $e');
    }
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      await BillingVendorsService.deleteComment(widget.vendorId, commentId);
      await _loadVendor();
    } catch (e) {
      _showError('Failed to delete comment: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: _red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _openEdit() async {
    final ok = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => NewVendorPage(vendorId: widget.vendorId)));
    if (ok == true) { _loadVendor(); _loadOverview(); }
  }

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: _loadingVendor
          ? const Center(child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)))
          : _vendor == null
              ? _buildErrorState()
              : NestedScrollView(
                  headerSliverBuilder: (_, __) => [_buildSliverAppBar()],
                  body: Column(children: [
                    _buildTabBar(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabCtrl,
                        children: [
                          _buildOverviewTab(),
                          _buildCommentsTab(),
                          _buildTransactionsTab(),
                          _buildMailsTab(),
                          _buildStatementTab(),
                          _buildAdvancesTab(),
                        ],
                      ),
                    ),
                  ]),
                ),
    );
  }

  // ── SliverAppBar (unchanged) ──────────────────────────────────────────────

  Widget _buildSliverAppBar() {
    final v = _vendor!;
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_navyDark, _navyMid, _navyLight],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: Text(
                    v.vendorName.isNotEmpty ? v.vendorName[0].toUpperCase() : 'V',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(v.vendorName,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    if (v.companyName.isNotEmpty)
                      Text(v.companyName,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.8), fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(children: [
                      _statusChip(v.status),
                      const SizedBox(width: 8),
                      if (v.portalEnabled)
                        _chip('Portal Enabled', Colors.green[300]!),
                    ]),
                  ],
                )),
              ]),
            ),
          ),
        ),
        collapseMode: CollapseMode.parallax,
      ),
      backgroundColor: _navyDark,
      foregroundColor: Colors.white,
      actions: [
        TextButton.icon(
          onPressed: _openEdit,
          icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
          label: const Text('Edit', style: TextStyle(color: Colors.white)),
        ),
        _buildNewTransactionButton(),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildNewTransactionButton() {
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _navyAccent, borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.add, color: Colors.white, size: 16),
          SizedBox(width: 4),
          Text('New', style: TextStyle(color: Colors.white,
              fontWeight: FontWeight.w600, fontSize: 13)),
          SizedBox(width: 4),
          Icon(Icons.expand_more, color: Colors.white, size: 16),
        ]),
      ),
      itemBuilder: (_) => [
        _menuItem('bill',    Icons.receipt_long_outlined,  _navy,   'Bill'),
        _menuItem('po',      Icons.shopping_cart_outlined, _green,  'Purchase Order'),
        _menuItem('payment', Icons.payment_outlined,       _orange, 'Payment Made'),
        _menuItem('credit',  Icons.credit_card_outlined,  _purple, 'Vendor Credit'),
      ],
      onSelected: (val) {
        switch (val) {
          case 'bill':    _showInfo('Navigate to New Bill screen for ${_vendor!.vendorName}'); break;
          case 'po':      _showInfo('Navigate to New Purchase Order screen'); break;
          case 'payment': _showInfo('Navigate to New Payment Made screen'); break;
          case 'credit':  _showInfo('Navigate to New Vendor Credit screen'); break;
        }
      },
    );
  }

  void _showInfo(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2)));

  PopupMenuItem<String> _menuItem(
      String val, IconData icon, Color color, String label) {
    return PopupMenuItem(value: val, child: ListTile(
      leading: Icon(icon, size: 18, color: color),
      title: Text(label),
      contentPadding: EdgeInsets.zero, dense: true,
    ));
  }

  // ── TabBar ────────────────────────────────────────────────────────────────

  Widget _buildTabBar() => Container(
    color: Colors.white,
    child: TabBar(
      controller: _tabCtrl,
      isScrollable: true,
      labelColor: _navyAccent,
      unselectedLabelColor: Colors.grey[600],
      indicatorColor: _navyAccent,
      indicatorWeight: 3,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      tabs: const [
        Tab(text: 'Overview'),
        Tab(text: 'Comments'),
        Tab(text: 'Transactions'),
        Tab(text: 'Mails'),
        Tab(text: 'Statement'),
        Tab(text: 'Advances'),
      ],
    ),
  );

  // =========================================================================
  //  TAB 1 — OVERVIEW  (responsive two-column layout)
  // =========================================================================

  Widget _buildOverviewTab() {
    return LayoutBuilder(builder: (ctx, cs) {
      final isWide = cs.maxWidth > 800;

      final leftCol = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildAvatarCard(),
          const SizedBox(height: 16),
          _buildAddressCard('Billing Address',
              Icons.location_on_outlined, _vendor!.billingAddress),
          const SizedBox(height: 12),
          _buildAddressCard('Shipping Address',
              Icons.local_shipping_outlined, _vendor!.shippingAddress),
          const SizedBox(height: 16),
          _buildOtherDetailsCard(),
        ]),
      );

      final rightCol = SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildPayablesCard(),
          const SizedBox(height: 16),
          _buildExpenseChartCard(),
        ]),
      );

      if (isWide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: leftCol),
          Expanded(flex: 6, child: rightCol),
        ]);
      }
      // narrow: stack left then right
      return SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          leftCol, rightCol,
        ]),
      );
    });
  }

  // ── Avatar card ───────────────────────────────────────────────────────────

  Widget _buildAvatarCard() {
    final v = _vendor!;
    return _card(child: Row(children: [
      Container(
        width: 56, height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_navyMid, _navyLight]),
          shape: BoxShape.circle,
        ),
        child: Center(child: Text(
          v.vendorName.isNotEmpty ? v.vendorName[0].toUpperCase() : 'V',
          style: const TextStyle(color: Colors.white,
              fontSize: 22, fontWeight: FontWeight.bold),
        )),
      ),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v.vendorName, style: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: _navyDark)),
        if (v.companyName.isNotEmpty)
          Text(v.companyName,
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: v.portalEnabled
                ? _green.withOpacity(0.1)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: v.portalEnabled
                    ? _green.withOpacity(0.4)
                    : Colors.grey[300]!),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6, height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                  color: v.portalEnabled ? _green : Colors.grey,
                  shape: BoxShape.circle),
            ),
            Text(v.portalEnabled ? 'Portal Enabled' : 'Portal not enabled',
                style: TextStyle(fontSize: 11,
                    color: v.portalEnabled ? _green : Colors.grey[600],
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ])),
      _statusChip(v.status),
    ]));
  }

  // ── Address card ──────────────────────────────────────────────────────────

  Widget _buildAddressCard(String title, IconData icon, VendorAddress address) {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: _navyAccent, size: 18),
        const SizedBox(width: 6),
        Text(title.toUpperCase(), style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold,
            color: _navyDark, letterSpacing: 0.8)),
        const Spacer(),
        InkWell(onTap: _openEdit,
            child: const Icon(Icons.keyboard_arrow_up, color: Colors.grey)),
      ]),
      const SizedBox(height: 12),
      if (address.isEmpty)
        TextButton(
          onPressed: _openEdit,
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero, minimumSize: Size.zero),
          child: Text('No $title - Add Address',
              style: const TextStyle(fontSize: 12, color: _navyAccent)),
        )
      else
        Text(address.formatted,
            style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.5)),
      if (!address.isEmpty && address.phone.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('Ph: ${address.phone}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    ]));
  }

  // ── Other details card ────────────────────────────────────────────────────

  Widget _buildOtherDetailsCard() {
    final v = _vendor!;
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.info_outline, size: 18, color: _navyAccent),
        const SizedBox(width: 6),
        const Text('OTHER DETAILS', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold,
            color: _navyDark, letterSpacing: 0.8)),
        const Spacer(),
        InkWell(onTap: _openEdit,
            child: const Icon(Icons.keyboard_arrow_up, color: Colors.grey)),
      ]),
      const SizedBox(height: 16),
      _detailRow('Vendor Type',      v.vendorType),
      _detailRow('Status',           v.status),
      _detailRow('Payment Terms',    v.paymentTerms),
      _detailRow('Default Currency', v.defaultCurrency),
      if (v.gstNumber.isNotEmpty)
        _detailRow('GST Number',           v.gstNumber),
      if (v.gstRegistrationType.isNotEmpty)
        _detailRow('GST Reg. Type',        v.gstRegistrationType),
      if (v.placeOfSupply.isNotEmpty)
        _detailRow('Place of Supply',      v.placeOfSupply),
      if (v.panNumber.isNotEmpty)
        _detailRow('PAN Number',           v.panNumber),
      if (v.taxPreference.isNotEmpty)
        _detailRow('Tax Preference',       v.taxPreference),
      if (v.tdsApplicable)
        _detailRow('TDS Section',          '${v.tdsSection} (${v.tdsRate}%)'),
      if (v.email.isNotEmpty)
        _detailRow('Email',                v.email),
      if (v.phoneNumber.isNotEmpty)
        _detailRow('Phone',                v.phoneNumber),
    ]));
  }

  Widget _detailRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: LayoutBuilder(builder: (ctx, cs) {
        // Very narrow: stack vertically
        if (cs.maxWidth < 280) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: _navyDark)),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 150, child: Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
          Expanded(child: Text(value, style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w500, color: _navyDark))),
        ]);
      }),
    );
  }

  // ── Payables card ─────────────────────────────────────────────────────────

  Widget _buildPayablesCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Payables', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      const SizedBox(height: 12),
      if (_loadingOverview)
        const Center(child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_navyAccent))))
      else if (_overview == null)
        Text('Could not load payables data',
            style: TextStyle(color: Colors.grey[500]))
      else ...[
        // Column headers
        Row(children: [
          const Expanded(child: Text('CURRENCY', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold,
              color: Colors.grey, letterSpacing: 0.8))),
          const SizedBox(width: 8),
          SizedBox(width: 110, child: Text('OUTSTANDING\nPAYABLES',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                  color: Colors.grey, letterSpacing: 0.5),
              textAlign: TextAlign.right)),
          const SizedBox(width: 8),
          SizedBox(width: 90, child: Text('UNUSED\nCREDITS',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                  color: Colors.grey, letterSpacing: 0.5),
              textAlign: TextAlign.right)),
        ]),
        const Divider(height: 12),
        // Data row
        Row(children: [
          Expanded(child: Text(
            '${_overview!.currency} - Indian Rupee',
            style: const TextStyle(fontSize: 13, color: _navyDark),
          )),
          const SizedBox(width: 8),
          SizedBox(width: 110, child: Text(
            '₹${_fmt.format(_overview!.outstandingPayables)}',
            style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600, color: _red),
            textAlign: TextAlign.right,
          )),
          const SizedBox(width: 8),
          SizedBox(width: 90, child: Text(
            '₹${_fmt.format(_overview!.unusedCredits)}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: _overview!.unusedCredits > 0 ? _navyAccent : _navyDark),
            textAlign: TextAlign.right,
          )),
        ]),
      ],
    ]));
  }

  // ── Expense chart card ────────────────────────────────────────────────────

  Widget _buildExpenseChartCard() {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Expenses', style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
            Text('Last 6 months',
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ]),
      const SizedBox(height: 16),
      if (_loadingOverview)
        const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_navyAccent))))
      else if (_overview == null || _overview!.monthlyExpenses.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No expense data',
              style: TextStyle(color: Colors.grey[500]))))
      else
        _buildBarChart(),
    ]));
  }

  // ── Bar Chart ─────────────────────────────────────────────────────────────

  Widget _buildBarChart() {
    final expenses    = _overview!.monthlyExpenses;
    final maxVal      = expenses.map((e) => e.total).fold(0.0, (a, b) => a > b ? a : b);
    final chartMaxVal = maxVal == 0 ? 1.0 : maxVal * 1.2;

    return Column(children: [
      // Tooltip shown above bars when one is tapped
      if (_hoveredBarIndex != null && _hoveredBarIndex! < expenses.length)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
                blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('₹${_fmt.format(expenses[_hoveredBarIndex!].total)}',
                style: const TextStyle(fontSize: 15,
                    fontWeight: FontWeight.bold, color: _navyDark)),
            Text(expenses[_hoveredBarIndex!].label,
                style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          ]),
        ),
      SizedBox(
        height: 100,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: expenses.asMap().entries.map((entry) {
            final i         = entry.key;
            final exp       = entry.value;
            final ratio     = maxVal == 0
                ? 0.0
                : exp.total / chartMaxVal;
            final isHovered = _hoveredBarIndex == i;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() =>
                  _hoveredBarIndex = _hoveredBarIndex == i ? null : i),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: (ratio * 80).clamp(2.0, 80.0),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isHovered
                          ? [_navyLight, _navyDark]
                          : [_navyAccent.withOpacity(0.7), _navyAccent],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
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
      Row(children: expenses.map((e) => Expanded(
        child: Text(e.label.split(' ').first,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey[500])),
      )).toList()),
    ]);
  }

  // =========================================================================
  //  TAB 2 — COMMENTS
  // =========================================================================

  Widget _buildCommentsTab() {
    final comments = _vendor?.comments ?? [];
    return Column(children: [
      // Input area
      Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(
            controller: _commentCtrl,
            maxLines: 3, minLines: 1,
            decoration: InputDecoration(
              hintText: 'Add a comment…',
              hintStyle: TextStyle(color: Colors.grey[400]),
              filled: true, fillColor: Colors.grey[50],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navyLight, width: 1.5)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              isDense: true,
            ),
          )),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _postingComment ? null : _postComment,
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyAccent, foregroundColor: Colors.white,
              elevation: 0, minimumSize: const Size(80, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: _postingComment
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Post',
                    style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
      const Divider(height: 1),
      // List
      Expanded(
        child: comments.isEmpty
            ? Center(child: Column(
                mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.chat_bubble_outline,
                    size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('No comments yet',
                    style: TextStyle(color: Colors.grey[500], fontSize: 15)),
              ]))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: comments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final c = comments[i];
                  return _card(child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                            color: _navyLight.withOpacity(0.12),
                            shape: BoxShape.circle),
                        child: Center(child: Text(
                          c.createdBy.isNotEmpty
                              ? c.createdBy[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                              color: _navyLight, fontWeight: FontWeight.bold),
                        )),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Wrap(crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8, children: [
                          Text(c.createdBy, style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13, color: _navyDark)),
                          Text(DateFormat('dd MMM yyyy, hh:mm a')
                              .format(c.createdAt),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500])),
                        ]),
                        const SizedBox(height: 6),
                        Text(c.text, style: TextStyle(
                            fontSize: 13, color: Colors.grey[800], height: 1.4)),
                      ])),
                      IconButton(
                        onPressed: () => _deleteComment(c.id),
                        icon: Icon(Icons.delete_outline,
                            size: 18, color: Colors.red[400]),
                        tooltip: 'Delete comment',
                      ),
                    ],
                  ));
                },
              ),
      ),
    ]);
  }

  // =========================================================================
  //  TAB 3 — TRANSACTIONS  (horizontal-scrollable DataTable)
  // =========================================================================

  Widget _buildTransactionsTab() {
    if (_loadingTxns) {
      return const Center(child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)));
    }
    if (_transactions.isEmpty) {
      return Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text('No transactions found',
            style: TextStyle(color: Colors.grey[500], fontSize: 15)),
      ]));
    }

    return Column(children: [
      // Count bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.white,
        child: Text(
          '${_transactions.length} transaction${_transactions.length == 1 ? '' : 's'}',
          style: const TextStyle(fontWeight: FontWeight.bold, color: _navyDark),
        ),
      ),
      const Divider(height: 1),
      // Table
      Expanded(
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
                blurRadius: 10, offset: const Offset(0, 3))],
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
                      PointerDeviceKind.trackpad,
                    }),
                child: SingleChildScrollView(
                  controller: _txnHScroll,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(_navyDark),
                      headingTextStyle: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold,
                          fontSize: 13, letterSpacing: 0.4),
                      headingRowHeight: 52,
                      dataRowMinHeight: 52,
                      dataRowMaxHeight: 64,
                      dataTextStyle: const TextStyle(fontSize: 13),
                      dataRowColor: WidgetStateProperty.resolveWith((s) {
                        if (s.contains(WidgetState.hovered)) {
                          return _navyDark.withOpacity(0.04);
                        }
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
                      ],
                      rows: _transactions.asMap().entries.map((entry) {
                        final i = entry.key;
                        final t = entry.value;
                        return DataRow(
                          color: WidgetStateProperty.resolveWith((s) {
                            if (s.contains(WidgetState.hovered)) {
                              return _navyDark.withOpacity(0.04);
                            }
                            return i.isOdd
                                ? const Color(0xFFF7F9FC)
                                : Colors.white;
                          }),
                          cells: [
                            DataCell(Text(
                              DateFormat('dd/MM/yyyy').format(t.date),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[700]),
                            )),
                            DataCell(Text(t.number,
                                style: const TextStyle(fontSize: 12,
                                    color: _navyAccent,
                                    fontWeight: FontWeight.w600))),
                            DataCell(_txnTypeBadge(t.type)),
                            DataCell(_txnStatusBadge(t.status)),
                            DataCell(Text(
                              '₹${_fmt.format(t.amount)}',
                              style: const TextStyle(fontSize: 12,
                                  fontWeight: FontWeight.w600, color: _navyDark),
                            )),
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

  // ── Type & Status badges — colours UNCHANGED from original ─────────────────

  Widget _txnTypeBadge(String type) {
    final map = <String, List<dynamic>>{
      'Bill'          : [const Color(0xFFFEE2E2), _red,    'Bill'],
      'PurchaseOrder' : [const Color(0xFFFEF3C7), _orange, 'PO'],
      'PaymentMade'   : [const Color(0xFFDCFCE7), _green,  'Payment'],
      'VendorCredit'  : [const Color(0xFFEDE9FE), _purple, 'Credit'],
    };
    final c = map[type] ?? [const Color(0xFFF1F5F9), Colors.grey, type];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: c[0] as Color, borderRadius: BorderRadius.circular(12)),
      child: Text(c[2] as String,
          style: TextStyle(color: c[1] as Color,
              fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _txnStatusBadge(String status) {
    Color bg = const Color(0xFFF1F5F9);
    Color fg = Colors.grey;
    if (['PAID', 'RECEIVED', 'APPLIED', 'CLOSED'].contains(status)) {
      bg = const Color(0xFFDCFCE7); fg = _green;
    } else if (['OPEN', 'ISSUED', 'RECORDED'].contains(status)) {
      bg = const Color(0xFFDCEFFE); fg = _navy;
    } else if (['OVERDUE'].contains(status)) {
      bg = const Color(0xFFFEE2E2); fg = _red;
    } else if (['PARTIALLY_PAID', 'PARTIALLY_APPLIED'].contains(status)) {
      bg = const Color(0xFFFEF3C7); fg = _orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis),
    );
  }

  // =========================================================================
  //  TAB 4 — MAILS
  // =========================================================================

  Widget _buildMailsTab() {
    if (_loadingMails) {
      return const Center(child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_navyAccent)));
    }
    if (_mails.isEmpty) {
      return Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.mail_outline, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text('No emails sent yet',
            style: TextStyle(color: Colors.grey[500], fontSize: 15)),
      ]));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _mails.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final m = _mails[i];
        return _card(child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
                color: _navy.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.email_outlined, color: _navy, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.subject,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text('To: ${m.sentTo}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            Text('${m.source} · ${m.documentNumber}',
                style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          ])),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(DateFormat('dd MMM yyyy').format(m.sentAt),
                style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            const SizedBox(height: 4),
            Text(DateFormat('hh:mm a').format(m.sentAt),
                style: TextStyle(color: Colors.grey[400], fontSize: 11)),
          ]),
        ]));
      },
    );
  }

  // =========================================================================
  //  TAB 5 — STATEMENT  (horizontal-scrollable DataTable)
  // =========================================================================

  Widget _buildStatementTab() {
    return Column(children: [
      // Date range picker bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: Colors.white,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            const Text('Period:', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _navyDark)),
            const SizedBox(width: 10),
            _datePicker('From', _stmtFrom,
                (d) => setState(() => _stmtFrom = d)),
            const SizedBox(width: 10),
            _datePicker('To', _stmtTo,
                (d) => setState(() => _stmtTo = d)),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _loadStatement,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent, foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Run',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
      const Divider(height: 1),

      if (_loadingStatement)
        const Expanded(child: Center(child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_navyAccent))))
      else if (_stmtErr != null)
        Expanded(child: Center(child: Text('Error: $_stmtErr',
            style: const TextStyle(color: _red))))
      else if (_statement == null)
        Expanded(child: Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.description_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Select a date range and tap Run',
              style: TextStyle(color: Colors.grey[500], fontSize: 15)),
        ])))
      else ...[
        // Opening / Closing balance summary cards
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: _statCard(
              'Opening Balance',
              '₹${_fmt.format((_statement!['openingBalance'] ?? 0).toDouble())}',
              _navyLight,
            )),
            const SizedBox(width: 10),
            Expanded(child: _statCard(
              'Closing Balance',
              '₹${_fmt.format((_statement!['closingBalance'] ?? 0).toDouble())}',
              ((_statement!['closingBalance'] ?? 0).toDouble()) >= 0
                  ? _red
                  : _green,
            )),
          ]),
        ),

        // DataTable
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
                  blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: _buildStatementTable(),
          ),
        ),
      ],
    ]);
  }

  Widget _buildStatementTable() {
    final entries = (_statement!['statement'] as List? ?? [])
        .map((e) => VendorStatementEntry.fromJson(e))
        .toList();

    if (entries.isEmpty) {
      return Center(child: Text('No transactions in this period',
          style: TextStyle(color: Colors.grey[500])));
    }

    return LayoutBuilder(builder: (context, constraints) {
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
                PointerDeviceKind.trackpad,
              }),
          child: SingleChildScrollView(
            controller: _stmHScroll,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(_navyDark),
                headingTextStyle: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold,
                    fontSize: 13, letterSpacing: 0.4),
                headingRowHeight: 52,
                dataRowMinHeight: 52,
                dataRowMaxHeight: 68,
                dataTextStyle: const TextStyle(fontSize: 13),
                dataRowColor: WidgetStateProperty.resolveWith((s) {
                  if (s.contains(WidgetState.hovered)) {
                    return _navyDark.withOpacity(0.04);
                  }
                  return null;
                }),
                dividerThickness: 1,
                columnSpacing: 16,
                horizontalMargin: 14,
                columns: const [
                  DataColumn(label: Text('DATE')),
                  DataColumn(label: Text('DESCRIPTION')),
                  DataColumn(label: Text('DEBIT'),   numeric: true),
                  DataColumn(label: Text('CREDIT'),  numeric: true),
                  DataColumn(label: Text('BALANCE'), numeric: true),
                ],
                rows: entries.asMap().entries.map((entry) {
                  final i = entry.key;
                  final e = entry.value;
                  return DataRow(
                    color: WidgetStateProperty.resolveWith((s) {
                      if (s.contains(WidgetState.hovered)) {
                        return _navyDark.withOpacity(0.04);
                      }
                      return i.isOdd
                          ? const Color(0xFFF7F9FC)
                          : Colors.white;
                    }),
                    cells: [
                      DataCell(Text(
                        DateFormat('dd/MM/yyyy').format(e.date),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[700]),
                      )),
                      DataCell(Text(e.description,
                          style: const TextStyle(fontSize: 12))),
                      // DEBIT — red when present, grey dash otherwise
                      DataCell(Text(
                        e.debit > 0 ? '₹${_fmt.format(e.debit)}' : '—',
                        style: TextStyle(fontSize: 12,
                            color:
                                e.debit > 0 ? _red : Colors.grey[400],
                            fontWeight: FontWeight.w500),
                      )),
                      // CREDIT — green when present, grey dash otherwise
                      DataCell(Text(
                        e.credit > 0 ? '₹${_fmt.format(e.credit)}' : '—',
                        style: TextStyle(fontSize: 12,
                            color: e.credit > 0 ? _green : Colors.grey[400],
                            fontWeight: FontWeight.w500),
                      )),
                      // BALANCE — red if positive (payable), green if negative
                      DataCell(Text(
                        '₹${_fmt.format(e.balance)}',
                        style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: e.balance >= 0 ? _red : _green),
                      )),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      );
    });
  }

  // =========================================================================
  //  SHARED HELPERS
  // =========================================================================

  /// Standard white card with subtle shadow
  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
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
        Text(value, style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _datePicker(String label, DateTime value,
      ValueChanged<DateTime> onPick) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context, initialDate: value,
          firstDate: DateTime(2000), lastDate: DateTime(2100),
        );
        if (picked != null) onPick(picked);
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

  Widget _statusChip(String status) {
    const map = <String, List<Color>>{
      'Active'          : [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'Inactive'        : [Color(0xFFF1F5F9), Color(0xFF64748B)],
      'Blocked'         : [Color(0xFFFEE2E2), Color(0xFFDC2626)],
      'Pending Approval': [Color(0xFFFEF3C7), Color(0xFFB45309)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c[0], borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c[1].withOpacity(0.3)),
      ),
      child: Text(status,
          style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
  );

  Widget _buildErrorState() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.error_outline, size: 64, color: _red),
      const SizedBox(height: 16),
      const Text('Failed to load vendor',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: _loadVendor,
        style: ElevatedButton.styleFrom(
            backgroundColor: _navy, foregroundColor: Colors.white),
        child: const Text('Retry'),
      ),
    ],
  ));

  // =========================================================================
  //  TAB 6 — ADVANCES
  // =========================================================================

  Future<void> _loadAdvances() async {
    setState(() => _advancesLoading = true);
    try {
      final res = await PaymentMadeService.getVendorAdvances(widget.vendorId);
      if (res['success'] == true) {
        setState(() {
          _advances     = List<Map<String, dynamic>>.from(res['data'] ?? []);
          _totalAdvance = (res['totalAdvance'] ?? 0).toDouble();
          _totalUnused  = (res['totalUnused']  ?? 0).toDouble();
        });
      }
    } catch (e) {
      debugPrint('Advances load error: $e');
    } finally {
      setState(() => _advancesLoading = false);
    }
  }

  Widget _buildAdvancesTab() {
    if (_advancesLoading) {
      return const Center(child: CircularProgressIndicator(color: _navy));
    }

    return Column(children: [
      // ── Summary cards ──────────────────────────────────────────────────
      Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(child: _advSummaryCard(
            label: 'Total Advance Paid',
            amount: _totalAdvance,
            icon: Icons.arrow_upward_rounded,
            color: _orange,
          )),
          const SizedBox(width: 12),
          Expanded(child: _advSummaryCard(
            label: 'Total Unused',
            amount: _totalUnused,
            icon: Icons.account_balance_wallet_outlined,
            color: _totalUnused > 0 ? _green : Colors.grey,
          )),
          const SizedBox(width: 12),
          Expanded(child: _advSummaryCard(
            label: 'Total Applied',
            amount: _totalAdvance - _totalUnused,
            icon: Icons.check_circle_outline,
            color: _navy,
          )),
        ]),
      ),

      const Divider(height: 1),

      // ── Table header ───────────────────────────────────────────────────
      Container(
        color: const Color(0xFF0D1B3E),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          _advCol('PAYMENT #',  120, Colors.white),
          _advCol('DATE',        90, Colors.white),
          _advCol('MODE',        90, Colors.white),
          _advCol('AMOUNT',     100, Colors.white, align: TextAlign.right),
          _advCol('USED',       100, Colors.white, align: TextAlign.right),
          _advCol('UNUSED',     100, Colors.white, align: TextAlign.right),
          _advCol('STATUS',     100, Colors.white, align: TextAlign.center),
        ]),
      ),

      // ── Table rows ─────────────────────────────────────────────────────
      if (_advances.isEmpty)
        Expanded(child: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No advance payments found',
                style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ],
        )))
      else
        Expanded(child: ListView.separated(
          itemCount: _advances.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
          itemBuilder: (_, i) {
            final a       = _advances[i];
            final amount  = (a['amount']        ?? 0).toDouble();
            final applied = (a['amountApplied'] ?? 0).toDouble();
            final unused  = (a['amountUnused']  ?? 0).toDouble();
            final status  = a['status']?.toString() ?? '';
            final date    = DateTime.tryParse(a['paymentDate']?.toString() ?? '') ?? DateTime.now();

            Color sc; String sl;
            switch (status) {
              case 'RECORDED':
              case 'APPLIED':
                sc = unused > 0 ? _orange : _green;
                sl = unused > 0 ? 'Open' : 'Closed';
                break;
              case 'PARTIALLY_APPLIED': sc = _orange; sl = 'Partial'; break;
              case 'VOIDED':            sc = _red;    sl = 'Voided';  break;
              default:                  sc = Colors.grey; sl = status;
            }

            return Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                SizedBox(width: 120, child: Text(
                  a['paymentNumber']?.toString() ?? '-',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
                )),
                SizedBox(width: 90, child: Text(
                  DateFormat('dd/MM/yyyy').format(date),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                )),
                SizedBox(width: 90, child: Text(
                  a['paymentMode']?.toString() ?? '-',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                )),
                SizedBox(width: 100, child: Text(
                  '₹${_fmt.format(amount)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50)),
                  textAlign: TextAlign.right,
                )),
                SizedBox(width: 100, child: Text(
                  '₹${_fmt.format(applied)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: applied > 0 ? _navy : Colors.grey[400]!),
                  textAlign: TextAlign.right,
                )),
                SizedBox(width: 100, child: Text(
                  '₹${_fmt.format(unused)}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                      color: unused > 0 ? _green : Colors.grey[400]!),
                  textAlign: TextAlign.right,
                )),
                SizedBox(width: 100, child: Center(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: sc.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: sc.withOpacity(0.4)),
                  ),
                  child: Text(sl, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sc)),
                ))),
              ]),
            );
          },
        )),
    ]);
  }

  Widget _advSummaryCard({
    required String label,
    required double amount,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
          const SizedBox(height: 2),
          Text('₹${_fmt.format(amount)}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ])),
      ]),
    );
  }

  Widget _advCol(String label, double width, Color color, {TextAlign align = TextAlign.left}) =>
      SizedBox(
        width: width,
        child: Text(label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                color: color, letterSpacing: 0.4),
            textAlign: align),
      );
}