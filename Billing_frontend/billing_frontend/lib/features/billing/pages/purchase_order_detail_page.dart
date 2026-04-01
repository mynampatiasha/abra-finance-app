// ============================================================================
// PURCHASE ORDER DETAIL PAGE
// ============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/purchase_order_service.dart';
import '../../../../core/utils/detail_page_actions.dart';
import 'new_purchase_order.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class PurchaseOrderDetailPage extends StatefulWidget {
  final String purchaseOrderId;
  const PurchaseOrderDetailPage({Key? key, required this.purchaseOrderId}) : super(key: key);

  @override
  State<PurchaseOrderDetailPage> createState() => _PurchaseOrderDetailPageState();
}

class _PurchaseOrderDetailPageState extends State<PurchaseOrderDetailPage> {
  PurchaseOrder? _po;
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
      final po = await PurchaseOrderService.getPurchaseOrder(widget.purchaseOrderId);
      setState(() { _po = po; _isLoading = false; });
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
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(_po?.purchaseOrderNumber ?? 'Purchase Order Detail',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            if (_po != null) ...[
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                tooltip: 'Download PDF',
                onPressed: () async {
                  final url = await PurchaseOrderService.downloadPDF(widget.purchaseOrderId);
                  if (mounted) await fetchAndHandleFile(context, url, '${_po!.purchaseOrderNumber}.pdf', download: true);
                },
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: 'Share',
                onPressed: () {
                  final po = _po!;
                  final text = 'Purchase Order: ${po.purchaseOrderNumber}\n'
                      'Vendor: ${po.vendorName}\n'
                      'Amount: ₹${po.totalAmount.toStringAsFixed(2)}\n'
                      'Status: ${po.status}\n'
                      'Date: ${DateFormat('dd MMM yyyy').format(po.purchaseOrderDate)}';
                  shareText(context, text, 'PO: ${po.purchaseOrderNumber}');
                },
              ),
            ],
            if (_po != null && _po!.status != 'CLOSED' && _po!.status != 'CANCELLED')
              TextButton.icon(
                onPressed: () async {
                  final r = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => NewPurchaseOrderScreen(purchaseOrderId: widget.purchaseOrderId)));
                  if (r == true) { setState(() => _changed = true); _load(); }
                },
                icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
                label: const Text('Edit', style: TextStyle(color: Colors.white70)),
              ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _load),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final po = _po!;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _buildMainScroll(po)),
            SizedBox(
              width: 320,
              child: Container(
                color: Colors.white,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildSidebar(po),
                ),
              ),
            ),
          ],
        );
      } else {
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildMainScroll(po, isScrollable: false),
              Container(color: Colors.white, padding: const EdgeInsets.all(20), child: _buildSidebar(po)),
            ],
          ),
        );
      }
    });
  }

  Widget _buildMainScroll(PurchaseOrder po, {bool isScrollable = true}) {
    final fmt = DateFormat('dd MMM yyyy');
    final content = Column(
      children: [
        // Header card
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_navyDark, _navyMid],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: _navyDark.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(po.purchaseOrderNumber,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(po.vendorName, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                        if ((po.vendorEmail ?? '').isNotEmpty)
                          Text(po.vendorEmail!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  _glowBadge(po.status),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _headerInfo('PO Date', fmt.format(po.purchaseOrderDate)),
                  if (po.expectedDeliveryDate != null)
                    _headerInfo('Expected Delivery', fmt.format(po.expectedDeliveryDate!)),
                  _headerInfo('Payment Terms', po.paymentTerms),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Line items
        _detailCard(
          title: 'Line Items',
          icon: Icons.list_alt,
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
              rows: po.items.map((item) => DataRow(cells: [
                DataCell(SizedBox(width: 200, child: Text(item.itemDetails, overflow: TextOverflow.ellipsis))),
                DataCell(Text(item.quantity.toStringAsFixed(0))),
                DataCell(Text('₹${item.rate.toStringAsFixed(2)}')),
                DataCell(Text(item.discount > 0
                    ? '${item.discount}${item.discountType == "percentage" ? "%" : "₹"}'
                    : '—')),
                DataCell(Text('₹${item.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600))),
              ])).toList(),
            ),
          ),
        ),

        if (po.receives.isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailCard(
            title: 'Receive History',
            icon: Icons.inventory,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: po.receives.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (_, i) {
                final r = po.receives[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.local_shipping, color: _navyAccent, size: 20),
                  ),
                  title: Text('Received on ${fmt.format(r.receiveDate)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${r.items.length} item(s)',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                );
              },
            ),
          ),
        ],

        if ((po.vendorNotes ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailCard(
            title: 'Notes',
            icon: Icons.note,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(po.vendorNotes!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
    return isScrollable ? SingleChildScrollView(child: content) : content;
  }

  Widget _buildSidebar(PurchaseOrder po) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          const Text('PO Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
        ]),
        const SizedBox(height: 16),
        _amtRow('Sub Total', po.subTotal),
        if (po.tdsAmount > 0) _amtRow('TDS', -po.tdsAmount, color: Colors.red[700]),
        if (po.tcsAmount > 0) _amtRow('TCS', po.tcsAmount),
        if (po.cgst > 0) _amtRow('CGST', po.cgst),
        if (po.sgst > 0) _amtRow('SGST', po.sgst),
        if (po.igst > 0) _amtRow('IGST', po.igst),
        const Divider(thickness: 2),
        _amtRow('Total', po.totalAmount, isBold: true, isTotal: true),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_navyDark.withOpacity(0.06), _navyLight.withOpacity(0.08)]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _navyAccent.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              _balanceRow('Status', po.status, _navyAccent),
              if (po.receiveStatus != null) ...[
                const SizedBox(height: 8),
                _balanceRow('Receive Status', po.receiveStatus!, Colors.blue),
              ],
              if (po.billingStatus != null) ...[
                const SizedBox(height: 8),
                _balanceRow('Billing Status', po.billingStatus!, Colors.green),
              ],
            ],
          ),
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
      ],
    );
  }

  Widget _detailCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      ),
    );
  }

  Widget _headerInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  Widget _amtRow(String label, double amount, {Color? color, bool isBold = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            fontSize: isTotal ? 14 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? (isTotal ? _navyDark : Colors.grey[700]),
          )),
          Text('${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}', style: TextStyle(
            fontSize: isTotal ? 16 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: color ?? (isTotal ? _navyAccent : _navyDark),
          )),
        ],
      ),
    );
  }

  Widget _balanceRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal, color: Colors.grey[700])),
        Text(value, style: TextStyle(fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: color)),
      ],
    );
  }

  Widget _glowBadge(String status) {
    Color bg;
    switch (status.toUpperCase()) {
      case 'OPEN': case 'ISSUED': bg = Colors.orange; break;
      case 'CLOSED': case 'RECEIVED': bg = Colors.green; break;
      case 'VOID': case 'CANCELLED': bg = Colors.grey; break;
      case 'DRAFT': bg = Colors.grey; break;
      case 'OVERDUE': bg = Colors.red; break;
      default: bg = _navyAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg, width: 1.5),
      ),
      child: Text(status, style: TextStyle(color: bg, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text('Error Loading Purchase Order',
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
        ],
      ),
    );
  }
}
