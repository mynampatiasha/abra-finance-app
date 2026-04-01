// ============================================================================
// PAYMENT RECEIVED DETAIL PAGE
// ============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/payment_service.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class PaymentReceivedDetailPage extends StatefulWidget {
  final Map<String, dynamic> payment;
  const PaymentReceivedDetailPage({Key? key, required this.payment}) : super(key: key);

  @override
  State<PaymentReceivedDetailPage> createState() => _PaymentReceivedDetailPageState();
}

class _PaymentReceivedDetailPageState extends State<PaymentReceivedDetailPage> {
  late Map<String, dynamic> _payment;
  List<PaymentProof> _proofs = [];
  bool _loadingProofs = false;

  @override
  void initState() {
    super.initState();
    _payment = widget.payment;
    _loadProofs();
  }

  Future<void> _loadProofs() async {
    final id = _payment['id']?.toString() ?? _payment['_id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _loadingProofs = true);
    try {
      final proofs = await PaymentService.getPaymentProofs(id);
      setState(() { _proofs = proofs; _loadingProofs = false; });
    } catch (_) {
      setState(() => _loadingProofs = false);
    }
  }

  String _str(String key, [String fallback = '—']) =>
      _payment[key]?.toString().isNotEmpty == true ? _payment[key].toString() : fallback;

  double _dbl(String key) => double.tryParse(_payment[key]?.toString() ?? '') ?? 0.0;

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
            begin: Alignment.centerLeft, end: Alignment.centerRight,
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Text(_str('paymentNumber', 'Payment Detail'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadProofs, tooltip: 'Refresh',
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _buildMainScroll()),
          SizedBox(
            width: 320,
            child: Container(
              color: Colors.white,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildSidebar(),
              ),
            ),
          ),
        ]);
      } else {
        return SingleChildScrollView(child: Column(children: [
          _buildMainScroll(isScrollable: false),
          Container(color: Colors.white, padding: const EdgeInsets.all(20),
              child: _buildSidebar()),
        ]));
      }
    });
  }

  Widget _buildMainScroll({bool isScrollable = true}) {
    final paymentDate = _payment['paymentDate'] != null
        ? DateFormat('dd MMM yyyy').format(DateTime.parse(_payment['paymentDate']))
        : '—';
    final invoicePayments = _payment['invoicePayments'] as Map<String, dynamic>? ?? {};

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
              Text(_str('paymentNumber', 'Payment'),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_str('customerName'), style: const TextStyle(color: Colors.white70, fontSize: 15)),
              if (_payment['customerEmail'] != null)
                Text(_str('customerEmail'), style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
            _glowBadge(_str('paymentMode', 'Payment')),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 8, children: [
            _headerInfo('Payment Date', paymentDate),
            _headerInfo('Mode', _str('paymentMode')),
            _headerInfo('Amount', '₹${_dbl('amountReceived').toStringAsFixed(2)}'),
            if (_payment['referenceNumber'] != null)
              _headerInfo('Reference', _str('referenceNumber')),
          ]),
        ]),
      ),

      const SizedBox(height: 16),

      // Invoice Allocations
      if (invoicePayments.isNotEmpty)
        _detailCard(
          title: 'Applied to Invoices', icon: Icons.receipt_long,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: invoicePayments.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
            itemBuilder: (_, i) {
              final entry = invoicePayments.entries.elementAt(i);
              final amt = double.tryParse(entry.value.toString()) ?? 0;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.receipt, color: Colors.green, size: 20),
                ),
                title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: Text('₹${amt.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
              );
            },
          ),
        ),

      if (invoicePayments.isNotEmpty) const SizedBox(height: 16),

      // Payment Proofs
      _detailCard(
        title: 'Payment Proofs', icon: Icons.attach_file,
        child: _loadingProofs
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()))
            : _proofs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No proofs attached',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14)))
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _proofs.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                    itemBuilder: (_, i) {
                      final proof = _proofs[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: _navyAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: Icon(
                            proof.fileType.contains('pdf') ? Icons.picture_as_pdf : Icons.image,
                            color: _navyAccent, size: 20),
                        ),
                        title: Text(proof.filename,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${(proof.fileSize / 1024).toStringAsFixed(1)} KB • ${DateFormat('dd MMM yyyy').format(proof.uploadedAt)}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      );
                    },
                  ),
      ),

      if (_payment['notes'] != null && _payment['notes'].toString().isNotEmpty) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Notes', icon: Icons.note,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_str('notes'), style: TextStyle(color: Colors.grey[800], fontSize: 14)),
          ),
        ),
      ],

      const SizedBox(height: 24),
    ]);

    if (isScrollable) return SingleChildScrollView(child: content);
    return content;
  }

  Widget _buildSidebar() {
    final unusedAmount = _dbl('unusedAmount');
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
        const Text('Payment Summary',
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
          _balanceRow('Amount Received', '₹${_dbl('amountReceived').toStringAsFixed(2)}', Colors.blue),
          const SizedBox(height: 8),
          _balanceRow('Amount Used', '₹${(_dbl('amountReceived') - unusedAmount).toStringAsFixed(2)}', Colors.green),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _balanceRow('Unused Amount', '₹${unusedAmount.toStringAsFixed(2)}',
              unusedAmount > 0 ? _navyAccent : Colors.grey, isBold: true),
        ]),
      ),

      const SizedBox(height: 16),

      // Payment mode info
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.payment, color: Colors.green[700], size: 18),
            const SizedBox(width: 8),
            Text('Payment Mode', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[800])),
          ]),
          const SizedBox(height: 8),
          Text(_str('paymentMode'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[700])),
          if (_payment['referenceNumber'] != null) ...[
            const SizedBox(height: 4),
            Text('Ref: ${_str('referenceNumber')}',
                style: TextStyle(fontSize: 12, color: Colors.green[600])),
          ],
        ]),
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

  Widget _glowBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green, width: 1.5),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
}
