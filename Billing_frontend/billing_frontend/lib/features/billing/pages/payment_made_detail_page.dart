// ============================================================================
// PAYMENT MADE DETAIL PAGE
// ============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/payment_made_service.dart';
import '../../../../core/utils/detail_page_actions.dart';
import 'new_payment_made.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class PaymentMadeDetailPage extends StatefulWidget {
  final PaymentMade payment;
  const PaymentMadeDetailPage({Key? key, required this.payment}) : super(key: key);

  @override
  State<PaymentMadeDetailPage> createState() => _PaymentMadeDetailPageState();
}

class _PaymentMadeDetailPageState extends State<PaymentMadeDetailPage> {
  late PaymentMade _payment;

  @override
  void initState() {
    super.initState();
    _payment = widget.payment;
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
          title: Text(_payment.paymentNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              tooltip: 'Download PDF',
              onPressed: () async {
                try {
                  final url = await PaymentMadeService.downloadPDF(_payment.id);
                  if (mounted) await fetchAndHandleFile(context, url, '${_payment.paymentNumber}.pdf', download: true);
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.share, color: Colors.white),
              tooltip: 'Share',
              onPressed: () {
                final p = _payment;
                final fmt = DateFormat('dd MMM yyyy');
                final text = 'Payment: ${p.paymentNumber}\n'
                    'Vendor: ${p.vendorName}\n'
                    'Amount: ₹${p.totalAmount.toStringAsFixed(2)}\n'
                    'Mode: ${p.paymentMode}\n'
                    'Status: ${p.status}\n'
                    'Date: ${fmt.format(p.paymentDate)}';
                shareText(context, text, 'Payment: ${p.paymentNumber}');
              },
            ),
            TextButton.icon(
              onPressed: () async {
                final r = await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => NewPaymentMadeScreen(paymentId: _payment.id)));
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
    final p = _payment;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _buildMainScroll(p)),
            SizedBox(
              width: 320,
              child: Container(
                color: Colors.white,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildSidebar(p),
                ),
              ),
            ),
          ],
        );
      } else {
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildMainScroll(p, isScrollable: false),
              Container(color: Colors.white, padding: const EdgeInsets.all(20), child: _buildSidebar(p)),
            ],
          ),
        );
      }
    });
  }

  Widget _buildMainScroll(PaymentMade p, {bool isScrollable = true}) {
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
                        Text(p.paymentNumber,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(p.vendorName, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                        if ((p.vendorEmail ?? '').isNotEmpty)
                          Text(p.vendorEmail!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  _glowBadge(p.paymentMode),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _headerInfo('Payment Date', fmt.format(p.paymentDate)),
                  _headerInfo('Mode', p.paymentMode),
                  if ((p.referenceNumber ?? '').isNotEmpty) _headerInfo('Reference', p.referenceNumber!),
                  if ((p.paidFromAccountName ?? '').isNotEmpty) _headerInfo('Paid From', p.paidFromAccountName!),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Bills applied
        if (p.billsApplied.isNotEmpty)
          _detailCard(
            title: 'Bills Applied',
            icon: Icons.receipt,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: p.billsApplied.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (_, i) {
                final b = p.billsApplied[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  ),
                  title: Text(b.billNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(fmt.format(b.appliedDate),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  trailing: Text('₹${b.amountApplied.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
                );
              },
            ),
          ),

        if ((p.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailCard(
            title: 'Notes',
            icon: Icons.note,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(p.notes!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
    return isScrollable ? SingleChildScrollView(child: content) : content;
  }

  Widget _buildSidebar(PaymentMade p) {
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
          const Text('Payment Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
        ]),
        const SizedBox(height: 16),
        _amtRow('Sub Total', p.subTotal),
        if (p.tdsAmount > 0) _amtRow('TDS', -p.tdsAmount, color: Colors.red[700]),
        if (p.tcsAmount > 0) _amtRow('TCS', p.tcsAmount),
        if (p.cgst > 0) _amtRow('CGST', p.cgst),
        if (p.sgst > 0) _amtRow('SGST', p.sgst),
        if (p.igst > 0) _amtRow('IGST', p.igst),
        const Divider(thickness: 2),
        _amtRow('Total', p.totalAmount, isBold: true, isTotal: true),
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
              _balanceRow('Total Amount', '₹${p.totalAmount.toStringAsFixed(2)}', Colors.blue),
              const SizedBox(height: 8),
              _balanceRow('Applied', '₹${p.amountApplied.toStringAsFixed(2)}', Colors.green),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _balanceRow('Unused', '₹${p.amountUnused.toStringAsFixed(2)}',
                  p.amountUnused > 0 ? _navyAccent : Colors.grey, isBold: true),
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
      case 'OPEN': bg = Colors.orange; break;
      case 'PAID': case 'CLOSED': bg = Colors.green; break;
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
}
