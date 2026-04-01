// ============================================================================
// DELIVERY CHALLAN DETAIL PAGE
// ============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/delivery_challan_service.dart';
import '../../../../core/utils/detail_page_actions.dart';
import 'new_delivery_challan.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class DeliveryChallanDetailPage extends StatefulWidget {
  final String challanId;
  const DeliveryChallanDetailPage({Key? key, required this.challanId}) : super(key: key);

  @override
  State<DeliveryChallanDetailPage> createState() => _DeliveryChallanDetailPageState();
}

class _DeliveryChallanDetailPageState extends State<DeliveryChallanDetailPage> {
  DeliveryChallan? _challan;
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
      final c = await DeliveryChallanService.getDeliveryChallan(widget.challanId);
      setState(() { _challan = c; _isLoading = false; });
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
          title: Text(_challan?.challanNumber ?? 'Challan Detail',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            if (_challan != null) ...[
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                tooltip: 'Download PDF',
                onPressed: () async {
                  try {
                    final url = await DeliveryChallanService.downloadPDF(widget.challanId);
                    if (mounted) await fetchAndHandleFile(context, url, '${_challan!.challanNumber}.pdf', download: true);
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: 'Share',
                onPressed: () {
                  final c = _challan!;
                  final text = 'Delivery Challan: ${c.challanNumber}\n'
                      'Customer: ${c.customerName}\n'
                      'Status: ${c.status}\n'
                      'Date: ${DateFormat('dd MMM yyyy').format(c.challanDate)}\n'
                      'Purpose: ${c.purpose}\n'
                      'Transport: ${c.transportMode}';
                  shareText(context, text, 'Challan: ${c.challanNumber}');
                },
              ),
            ],
            if (_challan != null && _challan!.status == 'DRAFT')
              TextButton.icon(
                onPressed: () async {
                  final r = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => NewDeliveryChallanScreen(challanId: widget.challanId)));
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
    final c = _challan!;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _buildMainScroll(c)),
          SizedBox(
            width: 320,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildSidebar(c),
              ),
            ),
          ),
        ]);
      } else {
        return SingleChildScrollView(child: Column(children: [
          _buildMainScroll(c, isScrollable: false),
          Container(color: Colors.white, padding: const EdgeInsets.all(20),
              child: _buildSidebar(c)),
        ]));
      }
    });
  }

  Widget _buildMainScroll(DeliveryChallan c, {bool isScrollable = true}) {
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
              Text(c.challanNumber,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(c.customerName, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              if (c.customerEmail != null)
                Text(c.customerEmail!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
            _glowBadge(c.status),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 8, children: [
            _headerInfo('Challan Date', DateFormat('dd MMM yyyy').format(c.challanDate)),
            if (c.expectedDeliveryDate != null)
              _headerInfo('Expected Delivery', DateFormat('dd MMM yyyy').format(c.expectedDeliveryDate!)),
            _headerInfo('Purpose', c.purpose),
            _headerInfo('Transport', c.transportMode),
            if (c.vehicleNumber != null) _headerInfo('Vehicle', c.vehicleNumber!),
            if (c.orderNumber != null) _headerInfo('Order #', c.orderNumber!),
          ]),
        ]),
      ),

      const SizedBox(height: 16),

      // Items
      _detailCard(
        title: 'Items', icon: Icons.inventory_2,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_navyDark.withOpacity(0.9)),
            headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
            columns: const [
              DataColumn(label: Text('ITEM')),
              DataColumn(label: Text('QTY')),
              DataColumn(label: Text('UNIT')),
              DataColumn(label: Text('HSN')),
              DataColumn(label: Text('DISPATCHED')),
              DataColumn(label: Text('DELIVERED')),
            ],
            rows: c.items.map((item) => DataRow(cells: [
              DataCell(SizedBox(width: 200, child: Text(item.itemDetails, overflow: TextOverflow.ellipsis))),
              DataCell(Text(item.quantity.toStringAsFixed(0))),
              DataCell(Text(item.unit)),
              DataCell(Text(item.hsnCode ?? '—')),
              DataCell(Text(item.quantityDispatched.toStringAsFixed(0))),
              DataCell(Text(item.quantityDelivered.toStringAsFixed(0))),
            ])).toList(),
          ),
        ),
      ),

      const SizedBox(height: 16),

      // Transport Details
      _detailCard(
        title: 'Transport Details', icon: Icons.local_shipping,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _infoRow(Icons.directions_car, 'Vehicle', c.vehicleNumber ?? '—'),
            const SizedBox(height: 10),
            _infoRow(Icons.person, 'Driver', c.driverName ?? '—'),
            if (c.driverPhone != null) ...[
              const SizedBox(height: 10),
              _infoRow(Icons.phone, 'Driver Phone', c.driverPhone!),
            ],
            if (c.transporterName != null) ...[
              const SizedBox(height: 10),
              _infoRow(Icons.business, 'Transporter', c.transporterName!),
            ],
            if (c.lrNumber != null) ...[
              const SizedBox(height: 10),
              _infoRow(Icons.receipt, 'LR Number', c.lrNumber!),
            ],
          ]),
        ),
      ),

      // Linked Invoices
      if (c.linkedInvoices.isNotEmpty) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Linked Invoices', icon: Icons.receipt_long,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: c.linkedInvoices.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
            itemBuilder: (_, i) {
              final inv = c.linkedInvoices[i];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.receipt, color: Colors.green, size: 20),
                ),
                title: Text(inv.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(DateFormat('dd MMM yyyy').format(inv.invoicedDate),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                trailing: Text('₹${inv.amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
              );
            },
          ),
        ),
      ],

      // Delivery Address
      if (c.deliveryAddress != null) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Delivery Address', icon: Icons.location_on,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_formatAddress(c.deliveryAddress!),
                style: TextStyle(color: Colors.grey[800], fontSize: 14)),
          ),
        ),
      ],

      if (c.customerNotes != null && c.customerNotes!.isNotEmpty) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Notes', icon: Icons.note,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(c.customerNotes!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
          ),
        ),
      ],

      const SizedBox(height: 24),
    ]);

    if (isScrollable) return SingleChildScrollView(child: content);
    return content;
  }

  String _formatAddress(Address addr) {
    final parts = [addr.street, addr.city, addr.state, addr.pincode, addr.country]
        .where((p) => p != null && p!.isNotEmpty).toList();
    return parts.join(', ');
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 18, color: _navyAccent),
      const SizedBox(width: 10),
      Text('$label: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis)),
    ]);
  }

  Widget _buildSidebar(DeliveryChallan c) {
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
        const Text('Challan Summary',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      ]),
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
          _sidebarRow('Total Items', '${c.items.length}', Colors.blue),
          const SizedBox(height: 8),
          _sidebarRow('Purpose', c.purpose, _navyDark),
          const SizedBox(height: 8),
          _sidebarRow('Transport', c.transportMode, _navyDark),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _sidebarRow('Linked Invoices', '${c.linkedInvoices.length}', _navyAccent, isBold: true),
        ]),
      ),

      const SizedBox(height: 16),

      // Delivery status
      if (c.actualDeliveryDate != null)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.check_circle, color: Colors.green[700], size: 16),
              const SizedBox(width: 6),
              Text('Delivered', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[800])),
            ]),
            const SizedBox(height: 6),
            Text(DateFormat('dd MMM yyyy').format(c.actualDeliveryDate!),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green[700])),
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

  Widget _sidebarRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal, color: Colors.grey[700])),
      Text(value, style: TextStyle(fontSize: 13,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: color)),
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
      case 'DISPATCHED': bg = Colors.orange; break;
      case 'DELIVERED': bg = Colors.green;  break;
      case 'RETURNED':  bg = Colors.red;    break;
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

  Widget _buildError() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
      const SizedBox(height: 16),
      Text('Error Loading Challan',
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
