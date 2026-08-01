import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// PL EXPENSE DRILLDOWN PAGE
// Shows bank transactions categorized under a specific expense account
// File: lib/features/billing/pages/pl_expense_drilldown_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/bank_transaction_service.dart';
import '../../../../core/utils/export_helper.dart';
import '../app_top_bar.dart';
import 'account_detail_page.dart';
import 'new_expenses.dart';
import 'new_invoice.dart';
import 'new_bill.dart';
import 'new_credit_note.dart';
import 'new_payment_page.dart';
import 'new_payment_made.dart';
import 'new_manual_journal.dart';

const _navy = Color(0xFF1E3A8A);
const _green = Color(0xFF27AE60);
const _red = Color(0xFFE74C3C);
const _orange = Color(0xFFE67E22);

class _AllDeviceScroll extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class PlExpenseDrilldownPage extends StatefulWidget {
  final String accountName; // e.g. "Rent expenses"
  final String orgName;
  final String? startDate; // ISO string
  final String? endDate;

  const PlExpenseDrilldownPage({
    Key? key,
    required this.accountName,
    required this.orgName,
    this.startDate,
    this.endDate,
  }) : super(key: key);

  @override
  State<PlExpenseDrilldownPage> createState() => _PlExpenseDrilldownPageState();
}

class _PlExpenseDrilldownPageState extends State<PlExpenseDrilldownPage> {
  final BankTransactionService _svc = BankTransactionService();

  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String _search = '';
  bool _exporting = false;
  double _totalAmount = 0;

  final _searchCtrl = TextEditingController();
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
        () => setState(() => _search = _searchCtrl.text.toLowerCase()));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final params = <String, String>{
        'categoryLabel': widget.accountName,
        if (widget.startDate != null) 'startDate': widget.startDate!,
        if (widget.endDate != null) 'endDate': widget.endDate!,
      };
      final res = await _svc.publicGet(
        '/api/finance/banking/transactions/by-category-label',
        params: params,
      );
      if (res['success'] == true) {
        _rows = List<Map<String, dynamic>>.from(res['data'] ?? []);
        _totalAmount = (res['totalAmount'] ?? 0).toDouble();
      }
    } catch (e) {
      debugPrint('DrillDown load error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _rows;
    return _rows
        .where((r) =>
            r.values.any((v) => v.toString().toLowerCase().contains(_search)))
        .toList();
  }

  String _fmt(dynamic v, String key) {
    if (v == null) return '—';
    final s = v.toString();
    if (s == 'null' || s.isEmpty) return '—';
    // Date
    if (key == 'date') {
      try {
        return DateFormat('dd MMM yyyy').format(DateTime.parse(s));
      } catch (_) {}
    }
    // Amount
    if (key == 'amount') {
      final n = double.tryParse(s);
      if (n != null) return '₹${NumberFormat('#,##,##0.00').format(n)}';
    }
    return s;
  }

  // The pdf package's base font has no glyph for ₹ (U+20B9) or the em dash
  // (—), so they render as broken boxes in exported PDFs. Use ASCII-only
  // equivalents here; the on-screen UI keeps ₹/— via _fmt().
  String _fmtPdf(dynamic v, String key) {
    if (v == null) return '-';
    final s = v.toString();
    if (s == 'null' || s.isEmpty) return '-';
    if (key == 'date') {
      try {
        return DateFormat('dd MMM yyyy').format(DateTime.parse(s));
      } catch (_) {}
    }
    if (key == 'amount') {
      final n = double.tryParse(s);
      if (n != null) return 'Rs.${NumberFormat('#,##,##0.00').format(n)}';
    }
    return s;
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final List<List<dynamic>> excelData = [
        [
          'Date',
          'Bank Account',
          'Description',
          'Payee',
          'Ref No.',
          'Type',
          'Amount'
        ],
        ..._rows.map((r) => [
              _fmt(r['date'], 'date'),
              r['bankAccount']?.toString() ?? '—',
              r['description']?.toString() ?? '—',
              r['payee']?.toString() ?? '—',
              r['referenceNumber']?.toString() ?? '—',
              r['type']?.toString() ?? '—',
              _fmt(r['amount'], 'amount'),
            ])
      ];
      await ExportHelper.exportToExcel(
        data: excelData,
        filename: '${widget.accountName.replaceAll(' ', '_')}_transactions',
      );
      _snack('Excel downloaded', _green);
    } catch (e) {
      _snack('Export failed: $e', _red);
    } finally {
      setState(() => _exporting = false);
    }
  }

  Future<void> _exportPDF() async {
    if (_rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      await ExportHelper.exportToPDF(
        title: '${widget.orgName}\n${widget.accountName} - Bank Transactions',
        headers: [
          'Date',
          'Bank Account',
          'Description',
          'Payee',
          'Ref No.',
          'Amount'
        ],
        data: _rows
            .map((r) => [
                  _fmtPdf(r['date'], 'date'),
                  r['bankAccount']?.toString() ?? '-',
                  r['description']?.toString() ?? '-',
                  r['payee']?.toString() ?? '-',
                  r['referenceNumber']?.toString() ?? '-',
                  _fmtPdf(r['amount'], 'amount'),
                ])
            .toList(),
        filename: '${widget.accountName.replaceAll(' ', '_')}_transactions',
      );
      _snack('PDF downloaded', _green);
    } catch (e) {
      _snack('PDF failed: $e', _red);
    } finally {
      setState(() => _exporting = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppTopBar(title: 'Account Transactions — ${widget.accountName}'),
      body: Column(children: [
        _buildTopBar(),
        if (_loading)
          const Expanded(
              child: Center(child: CircularProgressIndicator(color: _navy)))
        else
          Expanded(child: _buildBody()),
      ]),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.white,
      child: Row(children: [
        // Account badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: _navy.withOpacity(0.07),
              borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.account_balance_outlined, size: 13, color: _navy),
            const SizedBox(width: 5),
            Text(widget.accountName,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: _navy)),
          ]),
        ),
        if (widget.startDate != null && widget.endDate != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFDDE3EE))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.calendar_today, size: 11, color: _navy),
              const SizedBox(width: 5),
              Text(
                  '${DateFormat('dd/MM/yy').format(DateTime.parse(widget.startDate!))} - ${DateFormat('dd/MM/yy').format(DateTime.parse(widget.endDate!))}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: _navy)),
            ]),
          ),
        ],
        const SizedBox(width: 12),
        // Search
        Expanded(
            child: SizedBox(
          height: 38,
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search transactions…',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
              prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey[400]),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 14),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      })
                  : null,
              filled: true,
              fillColor: const Color(0xFFF7F9FC),
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: _navy, width: 1.5)),
            ),
          ),
        )),
        const SizedBox(width: 8),
        // Refresh
        InkWell(
            onTap: _loading ? null : _load,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFDDE3EE)),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white),
              child: const Icon(Icons.refresh_rounded, size: 16, color: _navy),
            )),
        const SizedBox(width: 6),
        // PDF
        _btn('PDF', Icons.picture_as_pdf_rounded, _red,
            _exporting ? null : _exportPDF),
        const SizedBox(width: 6),
        // Excel
        _btn('Excel', Icons.table_chart_rounded, _green,
            _exporting ? null : _exportExcel),
      ]),
    );
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ]),
      ),
    );
  }

  Widget _buildBody() {
    final rows = _filtered;

    return Column(children: [
      // Summary cards
      _buildSummaryCards(rows),
      // Table
      Expanded(child: _buildTable(rows)),
    ]);
  }

  Widget _buildSummaryCards(List<Map<String, dynamic>> rows) {
    final count = rows.length;
    // Sum all amounts positively — matches Zoho Books behaviour.
    // Individual rows already show green (Deposit) / red (Withdrawal) to indicate direction.
    final total = rows.fold(
        0.0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));
    // Use green for income (all deposits) and red when mixed/withdrawals dominate
    final hasWithdrawal = rows.any((r) => r['type']?.toString() == 'Withdrawal');
    final totalColor = hasWithdrawal ? _red : _green;
    return Container(
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(children: [
        _summaryCard('Total Transactions', count.toString(), _navy,
            Icons.receipt_long_outlined),
        const SizedBox(width: 12),
        _summaryCard(
            'Total Amount',
            '₹${NumberFormat('#,##,##0.00').format(total)}',
            totalColor,
            Icons.currency_rupee),
        if (widget.startDate != null) ...[
          const SizedBox(width: 12),
          _summaryCard(
              'Period',
              '${_fmtDateStr(widget.startDate!)} – ${_fmtDateStr(widget.endDate ?? '')}',
              const Color(0xFF5D6D7E),
              Icons.date_range_outlined),
        ],
      ]),
    );
  }

  String _fmtDateStr(String iso) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ]),
      ]),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Icon(Icons.inbox_outlined, size: 52, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            _search.isNotEmpty
                ? 'No results match "$_search"'
                : 'No bank transactions found for "${widget.accountName}"',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }

    const headers = [
      'date',
      'bankAccount',
      'description',
      'payee',
      'referenceNumber',
      'type',
      'actions',
      'amount'
    ];
    const labels = [
      'Date',
      'Bank Account',
      'Description',
      'Payee',
      'Ref No.',
      'Type',
      'Links',
      'Amount'
    ];
    const colW = 145.0;

    void _onRowTapped(Map<String, dynamic> row) {
      final type = row['referenceType']?.toString();
      final refId = row['referenceId']?.toString();
      final bankAccountId = row['bankAccountId']?.toString();
      final bankAccountName = row['bankAccount']?.toString();

      if (refId == null || refId.isEmpty) return;

      if (type == 'ProviderTransaction' && bankAccountId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AccountDetailPage(
              accountId: bankAccountId,
              accountName: bankAccountName ?? 'Bank Account',
              accountType: 'bank',
            ),
          ),
        );
      } else if (type == 'Expense') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => NewExpensePage(
              expenseId: refId,
              showAppBar: true,
            ),
          ),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(children: [
        // Count bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Text(
                '${rows.length} record${rows.length != 1 ? 's' : ''}${_search.isNotEmpty ? ' (filtered)' : ''}',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500)),
            if (_exporting) ...[
              const SizedBox(width: 8),
              const SizedBox(
                  width: 14,
                  height: 14,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: _navy)),
            ],
          ]),
        ),
        const Divider(height: 1),
        // Scrollable table
        Expanded(
          child: ScrollConfiguration(
            behavior: _AllDeviceScroll(),
            child: Scrollbar(
              controller: _hScroll,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: headers.length * colW + 28,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // Header
                    Container(
                      color: const Color(0xFF0D1B3E),
                      height: 44,
                      child: Row(children: [
                        const SizedBox(width: 14),
                        ...labels.map((lbl) => SizedBox(
                            width: colW,
                            child: Text(lbl.toUpperCase(),
                                textAlign: lbl == 'Amount'
                                    ? TextAlign.right
                                    : TextAlign.left,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    letterSpacing: 0.3)))),
                        const SizedBox(width: 14),
                      ]),
                    ),
                    // Data rows
                    Expanded(
                        child: ScrollConfiguration(
                      behavior: _AllDeviceScroll(),
                      child: Scrollbar(
                        controller: _vScroll,
                        child: ListView.builder(
                          controller: _vScroll,
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            final isDebit =
                                r['type']?.toString() == 'Withdrawal';
                            return Container(
                              height: 52,
                              color: i % 2 == 0
                                  ? Colors.white
                                  : const Color(0xFFF8FAFC),
                              child: Row(children: [
                                const SizedBox(width: 14),
                                ...headers.map((h) {
                                  final v = r[h];
                                  final isAmt = h == 'amount';
                                  final isType = h == 'type';
                                  Widget cell;
                                  if (isType) {
                                    cell = Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDebit
                                              ? _red.withOpacity(0.1)
                                              : _green.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(v?.toString() ?? '—',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    isDebit ? _red : _green)),
                                      ),
                                    );
                                  } else if (h == 'actions') {
                                    final btId = r['btId']?.toString();
                                    final atId = r['atId']?.toString();
                                    final bAcctId = r['bankAccountId']?.toString();
                                    final bAcctName = r['bankAccount']?.toString();
                                    
                                    cell = Row(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      children: [
                                        if (btId != null && bAcctId != null)
                                          InkWell(
                                            onTap: () {
                                              Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailPage(
                                                accountId: bAcctId,
                                                accountName: bAcctName ?? 'Bank Account',
                                                accountType: 'bank',
                                                highlightTransactionId: btId,
                                              )));
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                              decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF90CAF9))),
                                              child: const Text('BT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
                                            ),
                                          ),
                                        if (btId != null && atId != null) const SizedBox(width: 6),
                                        if (atId != null)
                                          InkWell(
                                            onTap: () {
                                              final type = r['atType']?.toString() ?? 'Expense';
                                              Widget? page;
                                              switch (type) {
                                                case 'Expense':
                                                  page = NewExpensePage(expenseId: atId, showAppBar: true);
                                                  break;
                                                case 'Invoice':
                                                  page = NewInvoiceScreen(invoiceId: atId);
                                                  break;
                                                case 'Bill':
                                                  page = NewBillScreen(billId: atId);
                                                  break;
                                                case 'CreditNote':
                                                  page = NewCreditNoteScreen(creditNoteId: atId);
                                                  break;
                                                case 'PaymentReceived':
                                                  page = NewPaymentPage(paymentId: atId, showAppBar: true);
                                                  break;
                                                case 'PaymentMade':
                                                  page = NewPaymentMadeScreen(paymentId: atId);
                                                  break;
                                                case 'JournalEntry':
                                                  page = NewManualJournalPage(journalId: atId);
                                                  break;
                                              }
                                              if (page != null) {
                                                Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                              decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFFFCC80))),
                                              child: const Text('AT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
                                            ),
                                          ),
                                        if (btId == null && atId == null)
                                          const Text('—', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    );
                                  } else {
                                    cell = Text(
                                      _fmt(v, h),
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: isAmt
                                          ? TextAlign.right
                                          : TextAlign.left,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isAmt
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: isAmt
                                            ? (isDebit ? _red : _green)
                                            : const Color(0xFF374151),
                                      ),
                                    );
                                  }
                                  return SizedBox(width: colW, child: cell);
                                }),
                                const SizedBox(width: 14),
                              ]),
                            );
                          },
                        ),
                      ),
                    )),
                    // Totals row
                    Container(
                      height: 44,
                      decoration: const BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: Color(0xFF1E3A8A), width: 1.5)),
                        color: Color(0xFFF0F4F8),
                      ),
                      child: Row(children: [
                        const SizedBox(width: 14),
                        SizedBox(
                            width: colW,
                            child: const Text('TOTAL',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _navy))),
                        SizedBox(
                            width: colW * (headers.length - 2),
                            child: const SizedBox()),
                        Builder(builder: (_) {
                          final footerTotal = rows.fold(
                              0.0,
                              (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0.0));
                          final hasWd = rows.any((r) => r['type']?.toString() == 'Withdrawal');
                          return SizedBox(
                              width: colW,
                              child: Text(
                                '₹${NumberFormat('#,##,##0.00').format(footerTotal)}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: hasWd ? _red : _green),
                              ));
                        }),
                        const SizedBox(width: 14),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
