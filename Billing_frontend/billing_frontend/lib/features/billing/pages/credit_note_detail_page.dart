// ============================================================================
// CREDIT NOTE DETAIL PAGE
// ============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/credit_note_service.dart';
import '../../../../core/utils/detail_page_actions.dart';
import 'new_credit_note.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class CreditNoteDetailPage extends StatefulWidget {
  final String creditNoteId;
  const CreditNoteDetailPage({Key? key, required this.creditNoteId}) : super(key: key);

  @override
  State<CreditNoteDetailPage> createState() => _CreditNoteDetailPageState();
}

class _CreditNoteDetailPageState extends State<CreditNoteDetailPage> {
  CreditNote? _creditNote;
  bool _isLoading = true;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final cn = await CreditNoteService.getCreditNote(widget.creditNoteId);
      setState(() { _creditNote = cn; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async { Navigator.pop(context, _changed); return false; },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: _buildAppBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null ? _buildError() : _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_navyDark, _navyMid, _navyLight],
            begin: Alignment.centerLeft, end: Alignment.centerRight,
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(_creditNote?.creditNoteNumber ?? 'Credit Note Detail',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            if (_creditNote != null) ...[
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                tooltip: 'Download PDF',
                onPressed: () async {
                  try {
                    final url = await CreditNoteService.downloadPDF(widget.creditNoteId);
                    if (mounted) await fetchAndHandleFile(context, url, '${_creditNote!.creditNoteNumber}.pdf', download: true);
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: 'Share',
                onPressed: () {
                  final cn = _creditNote!;
                  final text = 'Credit Note: ${cn.creditNoteNumber}\n'
                      'Customer: ${cn.customerName}\n'
                      'Amount: ₹${cn.totalAmount.toStringAsFixed(2)}\n'
                      'Balance: ₹${cn.creditBalance.toStringAsFixed(2)}\n'
                      'Status: ${cn.status}\n'
                      'Date: ${DateFormat('dd MMM yyyy').format(cn.creditNoteDate)}\n'
                      'Reason: ${cn.reason}';
                  shareText(context, text, 'Credit Note: ${cn.creditNoteNumber}');
                },
              ),
            ],
            if (_creditNote != null && _creditNote!.status == 'DRAFT')
              TextButton.icon(
                onPressed: () async {
                  final r = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => NewCreditNoteScreen(creditNoteId: widget.creditNoteId)));
                  if (r == true) { setState(() => _changed = true); _load(); }
                },
                icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
                label: const Text('Edit', style: TextStyle(color: Colors.white70)),
              ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _load, tooltip: 'Refresh',
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final cn = _creditNote!;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _buildMainScroll(cn)),
          SizedBox(
            width: 320,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildAmountSidebar(cn),
              ),
            ),
          ),
        ]);
      } else {
        return SingleChildScrollView(child: Column(children: [
          _buildMainScroll(cn, isScrollable: false),
          Container(color: Colors.white, padding: const EdgeInsets.all(20),
              child: _buildAmountSidebar(cn)),
        ]));
      }
    });
  }

  Widget _buildMainScroll(CreditNote cn, {bool isScrollable = true}) {
    final content = Column(children: [
      // Header card
      Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_navyDark, _navyMid],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: _navyDark.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cn.creditNoteNumber,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(cn.customerName, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              if (cn.customerEmail != null)
                Text(cn.customerEmail!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
            _glowBadge(cn.status),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 8, children: [
            _headerInfo('Date', DateFormat('dd MMM yyyy').format(cn.creditNoteDate)),
            _headerInfo('Reason', cn.reason),
            if (cn.invoiceNumber != null) _headerInfo('Invoice Ref', cn.invoiceNumber!),
            if (cn.referenceNumber != null) _headerInfo('Reference', cn.referenceNumber!),
          ]),
        ]),
      ),

      const SizedBox(height: 16),

      // Line Items
      _detailCard(
        title: 'Line Items', icon: Icons.list_alt,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_navyDark.withOpacity(0.9)),
            headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            columns: const [
              DataColumn(label: Text('ITEM')),
              DataColumn(label: Text('QTY')),
              DataColumn(label: Text('RATE')),
              DataColumn(label: Text('DISCOUNT')),
              DataColumn(label: Text('AMOUNT')),
            ],
            rows: cn.items.map((item) => DataRow(cells: [
              DataCell(SizedBox(width: 220, child: Text(item.itemDetails, overflow: TextOverflow.ellipsis))),
              DataCell(Text(item.quantity.toStringAsFixed(0))),
              DataCell(Text('₹${item.rate.toStringAsFixed(2)}')),
              DataCell(Text(item.discount > 0
                  ? '${item.discount}${item.discountType == "percentage" ? "%" : "₹"}' : '—')),
              DataCell(Text('₹${item.amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
            ])).toList(),
          ),
        ),
      ),

      const SizedBox(height: 16),

      // Credit Applications
      if (cn.creditApplications.isNotEmpty)
        _detailCard(
          title: 'Applied to Invoices', icon: Icons.check_circle,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cn.creditApplications.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
            itemBuilder: (_, i) {
              final a = cn.creditApplications[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.receipt, color: Colors.green, size: 20),
                ),
                title: Text('Applied to ${a.invoiceNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(DateFormat('dd MMM yyyy').format(a.appliedDate),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                trailing: Text('₹${a.amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
              );
            },
          ),
        ),

      if (cn.creditApplications.isNotEmpty) const SizedBox(height: 16),

      // Refund History
      if (cn.refunds.isNotEmpty)
        _detailCard(
          title: 'Refund History', icon: Icons.currency_rupee,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cn.refunds.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
            itemBuilder: (_, i) {
              final r = cn.refunds[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.currency_rupee, color: _navyAccent, size: 20),
                ),
                title: Text(r.refundMethod, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(DateFormat('dd MMM yyyy').format(r.refundDate),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  if (r.referenceNumber != null)
                    Text('Ref: ${r.referenceNumber}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                ]),
                isThreeLine: r.referenceNumber != null,
                trailing: Text('₹${r.amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: _navyAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              );
            },
          ),
        ),

      if (cn.refunds.isNotEmpty) const SizedBox(height: 16),

      if (cn.customerNotes != null && cn.customerNotes!.isNotEmpty)
        _detailCard(
          title: 'Customer Notes', icon: Icons.note,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(cn.customerNotes!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
          ),
        ),

      const SizedBox(height: 24),
    ]);

    if (isScrollable) return SingleChildScrollView(child: content);
    return content;
  }

  Widget _buildAmountSidebar(CreditNote cn) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_navyDark, _navyLight]),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(Icons.summarize, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 8),
        const Text('Credit Summary',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      ]),
      const SizedBox(height: 16),
      _amtRow('Sub Total', cn.subTotal),
      if (cn.tdsAmount > 0) _amtRow('TDS', -cn.tdsAmount, color: Colors.red[700]),
      if (cn.tcsAmount > 0) _amtRow('TCS', cn.tcsAmount),
      if (cn.cgst > 0) _amtRow('CGST', cn.cgst),
      if (cn.sgst > 0) _amtRow('SGST', cn.sgst),
      if (cn.igst > 0) _amtRow('IGST', cn.igst),
      const Divider(thickness: 2),
      _amtRow('Total Credit', cn.totalAmount, isBold: true, isTotal: true),
      const SizedBox(height: 16),

      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_navyDark.withOpacity(0.06), _navyLight.withOpacity(0.08)]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _navyAccent.withOpacity(0.2)),
        ),
        child: Column(children: [
          _balanceRow('Total Amount', '₹${cn.totalAmount.toStringAsFixed(2)}', Colors.blue),
          const SizedBox(height: 8),
          _balanceRow('Credit Used', '₹${cn.creditUsed.toStringAsFixed(2)}', Colors.green),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _balanceRow('Balance', '₹${cn.creditBalance.toStringAsFixed(2)}',
              cn.creditBalance > 0 ? _navyAccent : Colors.grey, isBold: true),
        ]),
      ),

      const SizedBox(height: 16),

      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, _changed),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to List'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navyMid,
            side: BorderSide(color: _navyMid),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    ]);
  }

  Widget _detailCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_navyDark, _navyLight]),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
          ]),
        ),
        const Divider(height: 1),
        child,
      ]),
    );
  }

  Widget _headerInfo(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
    ]);
  }

  Widget _glowBadge(String status) {
    Color bg;
    switch (status) {
      case 'DRAFT':    bg = Colors.grey;   break;
      case 'OPEN':     bg = Colors.blue;   break;
      case 'CLOSED':   bg = Colors.green;  break;
      case 'VOID':     bg = Colors.red;    break;
      default:         bg = _navyAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg, width: 1.5),
      ),
      child: Text(status, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _amtRow(String label, double amount, {Color? color, bool isBold = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(
          fontSize: isTotal ? 14 : 13,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color ?? (isTotal ? _navyDark : Colors.grey[700]),
        )),
        Text('${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 16 : 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? (isTotal ? _navyAccent : _navyDark),
            )),
      ]),
    );
  }

  Widget _balanceRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal, color: Colors.grey[700])),
      Text(value, style: TextStyle(fontSize: 13,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: color)),
    ]);
  }

  Widget _buildError() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
      const SizedBox(height: 16),
      Text('Error Loading Credit Note',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
      const SizedBox(height: 8),
      Text(_error ?? '', style: TextStyle(color: Colors.grey[600])),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
        style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white),
      ),
    ]));
  }
}
