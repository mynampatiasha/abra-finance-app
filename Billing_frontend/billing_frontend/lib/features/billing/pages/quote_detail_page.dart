// ============================================================================
// QUOTE DETAIL PAGE
// ============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/quote_service.dart';
import '../../../../core/utils/detail_page_actions.dart';
import 'new_quote.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class QuoteDetailPage extends StatefulWidget {
  final String quoteId;
  const QuoteDetailPage({Key? key, required this.quoteId}) : super(key: key);

  @override
  State<QuoteDetailPage> createState() => _QuoteDetailPageState();
}

class _QuoteDetailPageState extends State<QuoteDetailPage> {
  Quote? _quote;
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
      final q = await QuoteService.getQuote(widget.quoteId);
      setState(() { _quote = q; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

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
          title: Text(_quote?.quoteNumber ?? 'Quote Detail',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            if (_quote != null) ...[
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                tooltip: 'Download PDF',
                onPressed: () async {
                  final url = await QuoteService.downloadPDF(widget.quoteId);
                  if (mounted) await fetchAndHandleFile(context, url, '${_quote!.quoteNumber}.pdf', download: true);
                },
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: 'Share',
                onPressed: () {
                  final q = _quote!;
                  final text = 'Quote: ${q.quoteNumber}\n'
                      'Customer: ${q.customerName}\n'
                      'Amount: ₹${q.totalAmount.toStringAsFixed(2)}\n'
                      'Status: ${q.status}\n'
                      'Date: ${DateFormat('dd MMM yyyy').format(q.quoteDate)}\n'
                      'Expiry: ${DateFormat('dd MMM yyyy').format(q.expiryDate)}';
                  shareText(context, text, 'Quote: ${q.quoteNumber}');
                },
              ),
            ],
            if (_quote != null && (_quote!.status == 'DRAFT' || _quote!.status == 'SENT'))
              TextButton.icon(
                onPressed: () async {
                  final r = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => NewQuoteScreen(quoteId: widget.quoteId)));
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
    final q = _quote!;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _buildMainScroll(q)),
          SizedBox(
            width: 320,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildAmountSidebar(q),
              ),
            ),
          ),
        ]);
      } else {
        return SingleChildScrollView(child: Column(children: [
          _buildMainScroll(q, isScrollable: false),
          Container(color: Colors.white, padding: const EdgeInsets.all(20),
              child: _buildAmountSidebar(q)),
        ]));
      }
    });
  }

  Widget _buildMainScroll(Quote q, {bool isScrollable = true}) {
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
              Text(q.quoteNumber,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(q.customerName, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              if (q.customerEmail != null)
                Text(q.customerEmail!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
            _glowBadge(q.status),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 8, children: [
            _headerInfo('Quote Date', DateFormat('dd MMM yyyy').format(q.quoteDate)),
            _headerInfo('Expiry Date', DateFormat('dd MMM yyyy').format(q.expiryDate)),
            if (q.salesperson != null) _headerInfo('Salesperson', q.salesperson!),
            if (q.subject != null) _headerInfo('Subject', q.subject!),
            if (q.referenceNumber != null) _headerInfo('Reference', q.referenceNumber!),
          ]),
        ]),
      ),

      // Conversion info banner
      if (q.convertedToInvoice == true || q.convertedToSalesOrder == true)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Row(children: [
            Icon(Icons.check_circle, color: Colors.green[700], size: 18),
            const SizedBox(width: 8),
            Text(
              q.convertedToInvoice == true
                  ? 'Converted to Invoice${q.convertedDate != null ? ' on ${DateFormat('dd MMM yyyy').format(q.convertedDate!)}' : ''}'
                  : 'Converted to Sales Order',
              style: TextStyle(color: Colors.green[800], fontWeight: FontWeight.w600),
            ),
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
            rows: q.items.map((item) => DataRow(cells: [
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

      // Status Timeline
      _detailCard(
        title: 'Status Timeline', icon: Icons.timeline,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _timelineItem('Created', q.createdAt, Colors.blue, true),
            if (q.sentDate != null) _timelineItem('Sent to Customer', q.sentDate!, Colors.orange, true),
            if (q.acceptedDate != null) _timelineItem('Accepted', q.acceptedDate!, Colors.green, true),
            if (q.declinedDate != null) _timelineItem('Declined', q.declinedDate!, Colors.red, true),
            if (q.convertedDate != null) _timelineItem('Converted', q.convertedDate!, Colors.purple, true),
          ]),
        ),
      ),

      if (q.customerNotes != null && q.customerNotes!.isNotEmpty) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Customer Notes', icon: Icons.note,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(q.customerNotes!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
          ),
        ),
      ],

      if (q.termsAndConditions != null && q.termsAndConditions!.isNotEmpty) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Terms & Conditions', icon: Icons.description,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(q.termsAndConditions!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
          ),
        ),
      ],

      const SizedBox(height: 24),
    ]);

    if (isScrollable) return SingleChildScrollView(child: content);
    return content;
  }

  Widget _timelineItem(String label, DateTime date, Color color, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500))),
        Text(DateFormat('dd MMM yyyy').format(date),
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ]),
    );
  }

  Widget _buildAmountSidebar(Quote q) {
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
        const Text('Quote Summary',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      ]),
      const SizedBox(height: 16),
      _amtRow('Sub Total', q.subTotal),
      if (q.tdsAmount > 0) _amtRow('TDS', -q.tdsAmount, color: Colors.red[700]),
      if (q.tcsAmount > 0) _amtRow('TCS', q.tcsAmount),
      if (q.cgst > 0) _amtRow('CGST', q.cgst),
      if (q.sgst > 0) _amtRow('SGST', q.sgst),
      if (q.igst > 0) _amtRow('IGST', q.igst),
      const Divider(thickness: 2),
      _amtRow('Total Amount', q.totalAmount, isBold: true, isTotal: true),
      const SizedBox(height: 16),

      // Expiry info
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: q.expiryDate.isBefore(DateTime.now()) && q.status == 'SENT'
              ? Colors.red[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: q.expiryDate.isBefore(DateTime.now()) && q.status == 'SENT'
                ? Colors.red[200]! : Colors.grey[200]!),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.event, size: 16,
                color: q.expiryDate.isBefore(DateTime.now()) ? Colors.red : Colors.grey[600]),
            const SizedBox(width: 6),
            Text('Expiry Date',
                style: TextStyle(fontWeight: FontWeight.w600,
                    color: q.expiryDate.isBefore(DateTime.now()) ? Colors.red : Colors.grey[700])),
          ]),
          const SizedBox(height: 6),
          Text(DateFormat('dd MMM yyyy').format(q.expiryDate),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold,
                  color: q.expiryDate.isBefore(DateTime.now()) ? Colors.red : _navyDark)),
          if (q.expiryDate.isBefore(DateTime.now()) && q.status == 'SENT')
            Text('Expired', style: TextStyle(color: Colors.red[700], fontSize: 12)),
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
      case 'DRAFT':     bg = Colors.grey;   break;
      case 'SENT':      bg = Colors.blue;   break;
      case 'ACCEPTED':  bg = Colors.green;  break;
      case 'DECLINED':  bg = Colors.red;    break;
      case 'EXPIRED':   bg = Colors.orange; break;
      case 'CONVERTED': bg = Colors.purple; break;
      default:          bg = _navyAccent;
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

  Widget _buildError() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
      const SizedBox(height: 16),
      Text('Error Loading Quote',
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
