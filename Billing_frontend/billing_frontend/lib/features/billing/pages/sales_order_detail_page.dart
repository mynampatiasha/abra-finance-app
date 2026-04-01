// ============================================================================
// SALES ORDER DETAIL PAGE
// ============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/sales_order_service.dart';
import '../../../../core/utils/detail_page_actions.dart';
import 'new_sales_order.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class SalesOrderDetailPage extends StatefulWidget {
  final String salesOrderId;
  const SalesOrderDetailPage({Key? key, required this.salesOrderId}) : super(key: key);

  @override
  State<SalesOrderDetailPage> createState() => _SalesOrderDetailPageState();
}

class _SalesOrderDetailPageState extends State<SalesOrderDetailPage> {
  SalesOrder? _order;
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
      final so = await SalesOrderService.getSalesOrder(widget.salesOrderId);
      setState(() { _order = so; _isLoading = false; });
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
          title: Text(_order?.salesOrderNumber ?? 'Sales Order Detail',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            if (_order != null) ...[
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                tooltip: 'Download PDF',
                onPressed: () async {
                  final url = await SalesOrderService.downloadPDF(widget.salesOrderId);
                  if (mounted) await fetchAndHandleFile(context, url, '${_order!.salesOrderNumber}.pdf', download: true);
                },
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: 'Share',
                onPressed: () {
                  final so = _order!;
                  final text = 'Sales Order: ${so.salesOrderNumber}\n'
                      'Customer: ${so.customerName}\n'
                      'Amount: ₹${so.totalAmount.toStringAsFixed(2)}\n'
                      'Status: ${so.status}\n'
                      'Date: ${DateFormat('dd MMM yyyy').format(so.salesOrderDate)}';
                  shareText(context, text, 'Sales Order: ${so.salesOrderNumber}');
                },
              ),
            ],
            if (_order != null && (_order!.status == 'DRAFT' || _order!.status == 'OPEN'))
              TextButton.icon(
                onPressed: () async {
                  final r = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => NewSalesOrderScreen(salesOrderId: widget.salesOrderId)));
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
    final so = _order!;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _buildMainScroll(so)),
          SizedBox(
            width: 320,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildAmountSidebar(so),
              ),
            ),
          ),
        ]);
      } else {
        return SingleChildScrollView(child: Column(children: [
          _buildMainScroll(so, isScrollable: false),
          Container(color: Colors.white, padding: const EdgeInsets.all(20),
              child: _buildAmountSidebar(so)),
        ]));
      }
    });
  }

  Widget _buildMainScroll(SalesOrder so, {bool isScrollable = true}) {
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
              Text(so.salesOrderNumber,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(so.customerName, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              if (so.customerEmail != null)
                Text(so.customerEmail!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
            _glowBadge(so.status),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 8, children: [
            _headerInfo('Order Date', DateFormat('dd MMM yyyy').format(so.salesOrderDate)),
            if (so.expectedShipmentDate != null)
              _headerInfo('Ship By', DateFormat('dd MMM yyyy').format(so.expectedShipmentDate!)),
            _headerInfo('Payment Terms', so.paymentTerms),
            if (so.deliveryMethod != null) _headerInfo('Delivery', so.deliveryMethod!),
            if (so.salesperson != null) _headerInfo('Salesperson', so.salesperson!),
            if (so.convertedFromQuoteNumber != null)
              _headerInfo('From Quote', so.convertedFromQuoteNumber!),
          ]),
        ]),
      ),

      // Converted to invoice banner
      if (so.convertedToInvoice)
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
              'Converted to Invoice${so.convertedToInvoiceNumber != null ? ': ${so.convertedToInvoiceNumber}' : ''}',
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
              DataColumn(label: Text('PACKED')),
              DataColumn(label: Text('SHIPPED')),
              DataColumn(label: Text('AMOUNT')),
            ],
            rows: so.items.map((item) => DataRow(cells: [
              DataCell(SizedBox(width: 180, child: Text(item.itemDetails, overflow: TextOverflow.ellipsis))),
              DataCell(Text(item.quantity.toStringAsFixed(0))),
              DataCell(Text('₹${item.rate.toStringAsFixed(2)}')),
              DataCell(Text(item.discount > 0
                  ? '${item.discount}${item.discountType == "percentage" ? "%" : "₹"}' : '—')),
              DataCell(Text(item.quantityPacked.toStringAsFixed(0))),
              DataCell(Text(item.quantityShipped.toStringAsFixed(0))),
              DataCell(Text('₹${item.amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.w600))),
            ])).toList(),
          ),
        ),
      ),

      if (so.customerNotes != null && so.customerNotes!.isNotEmpty) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Customer Notes', icon: Icons.note,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(so.customerNotes!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
          ),
        ),
      ],

      if (so.termsAndConditions != null && so.termsAndConditions!.isNotEmpty) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Terms & Conditions', icon: Icons.description,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(so.termsAndConditions!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
          ),
        ),
      ],

      const SizedBox(height: 24),
    ]);

    if (isScrollable) return SingleChildScrollView(child: content);
    return content;
  }

  Widget _buildAmountSidebar(SalesOrder so) {
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
        const Text('Order Summary',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      ]),
      const SizedBox(height: 16),
      _amtRow('Sub Total', so.subTotal),
      if (so.tdsAmount > 0) _amtRow('TDS', -so.tdsAmount, color: Colors.red[700]),
      if (so.tcsAmount > 0) _amtRow('TCS', so.tcsAmount),
      if (so.cgst > 0) _amtRow('CGST', so.cgst),
      if (so.sgst > 0) _amtRow('SGST', so.sgst),
      if (so.igst > 0) _amtRow('IGST', so.igst),
      const Divider(thickness: 2),
      _amtRow('Total Amount', so.totalAmount, isBold: true, isTotal: true),
      const SizedBox(height: 16),

      // Shipment info
      if (so.expectedShipmentDate != null)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _navyAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _navyAccent.withOpacity(0.25)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.local_shipping, color: _navyAccent, size: 16),
              const SizedBox(width: 6),
              const Text('Expected Shipment',
                  style: TextStyle(fontWeight: FontWeight.w600, color: _navyMid)),
            ]),
            const SizedBox(height: 6),
            Text(DateFormat('dd MMM yyyy').format(so.expectedShipmentDate!),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
            if (so.deliveryMethod != null) ...[
              const SizedBox(height: 4),
              Text(so.deliveryMethod!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            ],
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
      case 'OPEN':      bg = Colors.blue;   break;
      case 'CONFIRMED': bg = Colors.orange; break;
      case 'SHIPPED':   bg = Colors.purple; break;
      case 'INVOICED':  bg = Colors.green;  break;
      case 'CANCELLED': bg = Colors.red;    break;
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
      Text('Error Loading Sales Order',
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
