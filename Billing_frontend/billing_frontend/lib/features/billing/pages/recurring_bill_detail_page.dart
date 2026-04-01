// ============================================================================
// RECURRING BILL DETAIL PAGE
// ============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/recurring_bill_service.dart';
import 'new_recurring_bill.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class RecurringBillDetailPage extends StatefulWidget {
  final RecurringBill bill;
  const RecurringBillDetailPage({Key? key, required this.bill}) : super(key: key);

  @override
  State<RecurringBillDetailPage> createState() => _RecurringBillDetailPageState();
}

class _RecurringBillDetailPageState extends State<RecurringBillDetailPage> {
  late RecurringBill _bill;

  @override
  void initState() {
    super.initState();
    _bill = widget.bill;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _buildBody(),
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
          title: Text(_bill.profileName, style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final r = await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => NewRecurringBillScreen(recurringBillId: _bill.id)));
                if (r == true) Navigator.pop(context, true);
              },
              icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
              label: const Text('Edit', style: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final b = _bill;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _buildMainScroll(b)),
            SizedBox(
              width: 320,
              child: Container(
                color: Colors.white,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildSidebar(b),
                ),
              ),
            ),
          ],
        );
      } else {
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildMainScroll(b, isScrollable: false),
              Container(color: Colors.white, padding: const EdgeInsets.all(20), child: _buildSidebar(b)),
            ],
          ),
        );
      }
    });
  }

  Widget _buildMainScroll(RecurringBill b, {bool isScrollable = true}) {
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
                        Text(b.profileName,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(b.vendorName, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                        if (b.vendorEmail.isNotEmpty)
                          Text(b.vendorEmail, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  _glowBadge(b.status),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _headerInfo('Repeat', 'Every ${b.repeatEvery} ${b.repeatUnit}'),
                  _headerInfo('Next Bill', fmt.format(b.nextBillDate)),
                  if (b.paymentTerms != null) _headerInfo('Payment Terms', b.paymentTerms!),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Line items
        if (b.items.isNotEmpty)
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
                  DataColumn(label: Text('AMOUNT')),
                ],
                rows: b.items.map((item) => DataRow(cells: [
                  DataCell(SizedBox(width: 200, child: Text(item.itemDetails, overflow: TextOverflow.ellipsis))),
                  DataCell(Text(item.quantity.toStringAsFixed(0))),
                  DataCell(Text('₹${item.rate.toStringAsFixed(2)}')),
                  DataCell(Text('₹${item.amount.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w600))),
                ])).toList(),
              ),
            ),
          ),

        const SizedBox(height: 16),

        // Schedule card
        _detailCard(
          title: 'Schedule',
          icon: Icons.schedule,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _infoRow('Repeat Every', '${b.repeatEvery} ${b.repeatUnit}'),
                _infoRow('Start Date', fmt.format(b.startDate)),
                if (b.endDate != null) _infoRow('End Date', fmt.format(b.endDate!)),
                _infoRow('Next Bill Date', fmt.format(b.nextBillDate)),
                _infoRow('Creation Mode', b.billCreationMode),
                _infoRow('Status', b.status),
              ],
            ),
          ),
        ),

        if ((b.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailCard(
            title: 'Notes',
            icon: Icons.note,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(b.notes!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
    return isScrollable ? SingleChildScrollView(child: content) : content;
  }

  Widget _buildSidebar(RecurringBill b) {
    final fmt = DateFormat('dd MMM yyyy');
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
          const Text('Bill Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
        ]),
        const SizedBox(height: 16),
        _amtRow('Sub Total', b.subTotal),
        if (b.tdsRate > 0) _amtRow('TDS Rate', b.tdsRate, suffix: '%'),
        if (b.tcsRate > 0) _amtRow('TCS Rate', b.tcsRate, suffix: '%'),
        if (b.gstRate > 0) _amtRow('GST Rate', b.gstRate, suffix: '%'),
        const Divider(thickness: 2),
        _amtRow('Total Amount', b.totalAmount, isBold: true, isTotal: true),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_navyDark.withOpacity(0.06), _navyLight.withOpacity(0.08)]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _navyAccent.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Schedule Info', style: TextStyle(fontWeight: FontWeight.bold, color: _navyDark, fontSize: 13)),
              const SizedBox(height: 8),
              _balanceRow('Bills Generated', '${b.totalBillsGenerated}', _navyAccent),
              if (b.lastGeneratedDate != null) ...[
                const SizedBox(height: 6),
                _balanceRow('Last Generated', fmt.format(b.lastGeneratedDate!), Colors.grey[700]!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(context),
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _amtRow(String label, double amount, {Color? color, bool isBold = false, bool isTotal = false, String suffix = ''}) {
    final display = suffix.isNotEmpty ? '${amount.toStringAsFixed(1)}$suffix' : '₹${amount.toStringAsFixed(2)}';
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
          Text(display, style: TextStyle(
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
      case 'ACTIVE': bg = Colors.orange; break;
      case 'CLOSED': case 'STOPPED': bg = Colors.green; break;
      case 'PAUSED': bg = Colors.grey; break;
      case 'DRAFT': bg = Colors.grey; break;
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
}
