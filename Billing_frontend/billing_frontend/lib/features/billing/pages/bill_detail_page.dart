import 'package:abra_finance/core/utils/app_snackbar.dart';
import '../widgets/document_preview_buttons.dart';
// ============================================================================
// BILL DETAIL PAGE
// ============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/bill_service.dart';
import '../../../../core/utils/detail_page_actions.dart';
import 'new_bill.dart';

// ignore_for_file: use_build_context_synchronously

const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class BillDetailPage extends StatefulWidget {
  final String billId;
  const BillDetailPage({Key? key, required this.billId}) : super(key: key);

  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  Bill? _bill;
  bool _isLoading = true;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final b = await BillService.getBill(widget.billId);
      setState(() {
        _bill = b;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _changed);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: _buildAppBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : _buildBody(),
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
          title: Text(_bill?.billNumber ?? 'Bill Detail',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, color: Colors.white),
              tooltip: 'View PDF',
              onPressed: () async {
                await openDocumentPdf(
                  context: context,
                  docId: widget.billId,
                  pdfEndpoint: '/api/finance/bills',
                  docNumber: _bill?.billNumber ?? 'Bill',
                );
              },
            ),
            if (_bill != null) ...[
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                tooltip: 'Download PDF',
                onPressed: () async {
                  final url = await BillService.downloadPDF(widget.billId);
                  if (mounted)
                    await fetchAndHandleFile(
                        context, url, '${_bill!.billNumber}.pdf',
                        download: true);
                },
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: 'Share',
                onPressed: () {
                  final b = _bill!;
                  final text = 'Bill: ${b.billNumber}\n'
                      'Vendor: ${b.vendorName}\n'
                      'Amount: ₹${b.totalAmount.toStringAsFixed(2)}\n'
                      'Due: ₹${b.amountDue.toStringAsFixed(2)}\n'
                      'Status: ${b.status}\n'
                      'Date: ${DateFormat('dd MMM yyyy').format(b.billDate)}\n'
                      'Due Date: ${DateFormat('dd MMM yyyy').format(b.dueDate)}';
                  shareText(context, text, 'Bill: ${b.billNumber}');
                },
              ),
            ],
            if (_bill != null &&
                _bill!.status != 'PAID' &&
                _bill!.status != 'VOID')
              TextButton.icon(
                onPressed: () async {
                  final r = await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              NewBillScreen(billId: widget.billId)));
                  if (r == true) {
                    setState(() => _changed = true);
                    _load();
                  }
                },
                icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
                label:
                    const Text('Edit', style: TextStyle(color: Colors.white70)),
              ),
            // ── Apply Credits button ──────────────────────────────────────────
            if (_bill != null &&
                ['OPEN', 'PARTIALLY_PAID', 'OVERDUE'].contains(_bill!.status))
              TextButton.icon(
                onPressed: () async {
                  final changed = await showDialog<bool>(
                    context: context,
                    builder: (_) => _ApplyCreditsDialog(bill: _bill!),
                  );
                  if (changed == true) {
                    setState(() => _changed = true);
                    _load();
                  }
                },
                icon: const Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.white70, size: 18),
                label: const Text('Apply Credits',
                    style: TextStyle(color: Colors.white70)),
              ),
            const SizedBox(width: 8),
            IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _load),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final b = _bill!;
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
              Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(20),
                  child: _buildSidebar(b)),
            ],
          ),
        );
      }
    });
  }

  Widget _buildMainScroll(Bill b, {bool isScrollable = true}) {
    final fmt = DateFormat('dd MMM yyyy');
    final content = Column(
      children: [
        // Header card
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [_navyDark, _navyMid],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: _navyDark.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
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
                        Text(b.billNumber,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(b.vendorName,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 15)),
                        if ((b.vendorEmail ?? '').isNotEmpty)
                          Text(b.vendorEmail!,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 13)),
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
                  _headerInfo('Bill Date', fmt.format(b.billDate)),
                  _headerInfo('Due Date', fmt.format(b.dueDate)),
                  _headerInfo('Payment Terms', b.paymentTerms),
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
              headingRowColor:
                  WidgetStateProperty.all(_navyDark.withOpacity(0.9)),
              headingTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12),
              columns: const [
                DataColumn(label: Text('ITEM')),
                DataColumn(label: Text('QTY')),
                DataColumn(label: Text('RATE')),
                DataColumn(label: Text('DISCOUNT')),
                DataColumn(label: Text('AMOUNT')),
              ],
              rows: b.items
                  .map((item) => DataRow(cells: [
                        DataCell(SizedBox(
                            width: 200,
                            child: Text(item.itemDetails,
                                overflow: TextOverflow.ellipsis))),
                        DataCell(Text(item.quantity.toStringAsFixed(0))),
                        DataCell(Text('₹${item.rate.toStringAsFixed(2)}')),
                        DataCell(Text(item.discount > 0
                            ? '${item.discount}${item.discountType == "percentage" ? "%" : "₹"}'
                            : '—')),
                        DataCell(Text('₹${item.amount.toStringAsFixed(2)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w600))),
                      ]))
                  .toList(),
            ),
          ),
        ),

        if (b.payments.isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailCard(
            title: 'Payment History',
            icon: Icons.payment,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: b.payments.length,
              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (_, i) {
                final p = b.payments[i];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.check_circle,
                        color: Colors.green, size: 20),
                  ),
                  title: Text(p.paymentMode,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmt.format(p.paymentDate),
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12)),
                      if ((p.referenceNumber ?? '').isNotEmpty)
                        Text('Ref: ${p.referenceNumber}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 11)),
                    ],
                  ),
                  isThreeLine: (p.referenceNumber ?? '').isNotEmpty,
                  trailing: Text('₹${p.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                );
              },
            ),
          ),
        ],

        if ((b.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailCard(
            title: 'Notes',
            icon: Icons.note,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(b.notes!,
                  style: TextStyle(color: Colors.grey[800], fontSize: 14)),
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
    return isScrollable ? SingleChildScrollView(child: content) : content;
  }

  Widget _buildSidebar(Bill b) {
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
          const Text('Bill Summary',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
        ]),
        const SizedBox(height: 16),
        _amtRow('Sub Total', b.subTotal),
        if (b.tdsAmount > 0)
          _amtRow('TDS', -b.tdsAmount, color: Colors.red[700]),
        if (b.tcsAmount > 0) _amtRow('TCS', b.tcsAmount),
        if (b.cgst > 0) _amtRow('CGST', b.cgst),
        if (b.sgst > 0) _amtRow('SGST', b.sgst),
        if (b.igst > 0) _amtRow('IGST', b.igst),
        const Divider(thickness: 2),
        _amtRow('Total', b.totalAmount, isBold: true, isTotal: true),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              _navyDark.withOpacity(0.06),
              _navyLight.withOpacity(0.08)
            ]),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _navyAccent.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              _balanceRow('Total Amount',
                  '₹${b.totalAmount.toStringAsFixed(2)}', Colors.blue),
              const SizedBox(height: 8),
              _balanceRow('Amount Paid', '₹${b.amountPaid.toStringAsFixed(2)}',
                  Colors.green),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _balanceRow('Amount Due', '₹${b.amountDue.toStringAsFixed(2)}',
                  b.amountDue > 0 ? _navyAccent : Colors.grey,
                  isBold: true),
            ],
          ),
        ),

        // ── Applied Credits section ───────────────────────────────────────────
        if (b.vendorCreditsApplied.isNotEmpty) ...[
          const SizedBox(height: 20),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF0D7377), Color(0xFF14A085)]),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            const Text('Applied Credits',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _navyDark)),
          ]),
          const SizedBox(height: 10),
          ...b.vendorCreditsApplied.map((c) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.teal[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal[200]!),
                ),
                child: Row(children: [
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.paymentNumber ?? 'Advance',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _navyDark)),
                      Text(DateFormat('dd MMM yyyy').format(c.appliedDate),
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[600])),
                    ],
                  )),
                  Text('₹${c.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0D7377))),
                  const SizedBox(width: 6),
                  if (!['PAID', 'VOID'].contains(b.status))
                    InkWell(
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            title: const Text('Remove Credit?',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            content: Text(
                                'Remove ₹${c.amount.toStringAsFixed(2)} credit '
                                'from ${c.paymentNumber ?? "this advance"}?\n\n'
                                'The advance balance will be restored.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        try {
                          await BillService.removeCredit(widget.billId, c.id);
                          setState(() => _changed = true);
                          _load();
                        } catch (e) {
                          AppSnackbar.show(context,
                              message: 'Failed to remove credit: $e',
                              isError: true);
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child:
                            Icon(Icons.close, size: 14, color: Colors.red[700]),
                      ),
                    ),
                ]),
              )),
        ],

        const SizedBox(height: 16),

        // Apply Credits button
        if (['OPEN', 'PARTIALLY_PAID', 'OVERDUE'].contains(b.status))
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                final changed = await showDialog<bool>(
                  context: context,
                  builder: (_) => _ApplyCreditsDialog(bill: b),
                );
                if (changed == true) {
                  setState(() => _changed = true);
                  _load();
                }
              },
              icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: const Text('Apply Credits'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D7377),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),

        const SizedBox(height: 10),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailCard(
      {required String title, required IconData icon, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
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
                  gradient:
                      const LinearGradient(colors: [_navyDark, _navyLight]),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _navyDark)),
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
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ],
    );
  }

  Widget _amtRow(String label, double amount,
      {Color? color, bool isBold = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
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
        ],
      ),
    );
  }

  Widget _balanceRow(String label, String value, Color color,
      {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
                color: Colors.grey[700])),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: color)),
      ],
    );
  }

  Widget _glowBadge(String status) {
    Color bg;
    switch (status.toUpperCase()) {
      case 'OPEN':
        bg = Colors.orange;
        break;
      case 'PAID':
      case 'CLOSED':
        bg = Colors.green;
        break;
      case 'VOID':
      case 'CANCELLED':
        bg = Colors.grey;
        break;
      case 'DRAFT':
        bg = Colors.grey;
        break;
      case 'OVERDUE':
        bg = Colors.red;
        break;
      default:
        bg = _navyAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg, width: 1.5),
      ),
      child: Text(status,
          style:
              TextStyle(color: bg, fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text('Error Loading Bill',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700])),
          const SizedBox(height: 8),
          Text(_error ?? '', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// APPLY CREDITS DIALOG — Zoho Books style
// ============================================================================

class _ApplyCreditsDialog extends StatefulWidget {
  final Bill bill;
  const _ApplyCreditsDialog({required this.bill});

  @override
  State<_ApplyCreditsDialog> createState() => _ApplyCreditsDialogState();
}

class _ApplyCreditsDialogState extends State<_ApplyCreditsDialog> {
  bool _loading = true;
  bool _applying = false;
  String? _error;
  List<VendorAdvance> _advances = [];

  // Per-advance amount controllers
  final Map<String, TextEditingController> _amtCtrls = {};

  @override
  void initState() {
    super.initState();
    _loadAdvances();
  }

  @override
  void dispose() {
    for (final c in _amtCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAdvances() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await BillService.getAvailableCredits(widget.bill.id);
      setState(() {
        _advances = list;
        _loading = false;
        // Pre-fill each controller with min(unused, amountDue)
        for (final a in list) {
          final suggested = a.amountUnused < widget.bill.amountDue
              ? a.amountUnused
              : widget.bill.amountDue;
          _amtCtrls[a.id] =
              TextEditingController(text: suggested.toStringAsFixed(2));
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _apply(VendorAdvance advance) async {
    final ctrl = _amtCtrls[advance.id];
    final amt = double.tryParse(ctrl?.text.trim() ?? '');
    if (amt == null || amt <= 0) {
      AppSnackbar.show(context, message: 'Enter a valid amount', isError: true);
      return;
    }
    if (amt > advance.amountUnused + 0.001) {
      AppSnackbar.show(context,
          message: 'Amount exceeds available balance '
              '(₹${advance.amountUnused.toStringAsFixed(2)})',
          isError: true);
      return;
    }
    if (amt > widget.bill.amountDue + 0.001) {
      AppSnackbar.show(context,
          message: 'Amount exceeds bill due '
              '(₹${widget.bill.amountDue.toStringAsFixed(2)})',
          isError: true);
      return;
    }

    setState(() => _applying = true);
    try {
      await BillService.applyCredit(widget.bill.id, advance.id, amt);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _applying = false);
      AppSnackbar.show(context,
          message: 'Failed to apply credit: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0D7377), Color(0xFF14A085)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Apply Vendor Credits',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  Text(
                      'Bill: ${widget.bill.billNumber}  •  '
                      'Due: ₹${widget.bill.amountDue.toStringAsFixed(2)}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              )),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                onPressed: () => Navigator.pop(context, false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ),

          // ── Body ────────────────────────────────────────────────────────────
          Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                          padding: const EdgeInsets.all(20),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.error_outline,
                                size: 48, color: Colors.red[300]),
                            const SizedBox(height: 12),
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[700])),
                            const SizedBox(height: 16),
                            ElevatedButton(
                                onPressed: _loadAdvances,
                                child: const Text('Retry')),
                          ]),
                        ))
                      : _advances.isEmpty
                          ? Center(
                              child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.account_balance_wallet_outlined,
                                        size: 56, color: Colors.grey[300]),
                                    const SizedBox(height: 12),
                                    Text('No available vendor advances',
                                        style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 6),
                                    Text(
                                        'Record an advance payment for '
                                        '${widget.bill.vendorName} first.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[500])),
                                  ]),
                            ))
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _advances.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) {
                                final a = _advances[i];
                                final ctrl = _amtCtrls[a.id]!;
                                return Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.teal[50],
                                    borderRadius: BorderRadius.circular(10),
                                    border:
                                        Border.all(color: Colors.teal[200]!),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Expanded(
                                            child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(a.paymentNumber,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: _navyDark)),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${DateFormat('dd MMM yyyy').format(a.paymentDate)}'
                                              '  •  ${a.paymentMode}',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600]),
                                            ),
                                          ],
                                        )),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                                '₹${a.amount.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey)),
                                            Text(
                                              'Available: ₹${a.amountUnused.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF0D7377)),
                                            ),
                                          ],
                                        ),
                                      ]),
                                      const SizedBox(height: 12),
                                      Row(children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: ctrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                            decoration: InputDecoration(
                                              labelText: 'Amount to Apply (₹)',
                                              prefixText: '₹ ',
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                    color: Color(0xFF0D7377),
                                                    width: 2),
                                              ),
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 10),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        ElevatedButton(
                                          onPressed: _applying
                                              ? null
                                              : () => _apply(a),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF0D7377),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 20, vertical: 12),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8)),
                                          ),
                                          child: _applying
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                          color: Colors.white,
                                                          strokeWidth: 2))
                                              : const Text('Apply'),
                                        ),
                                      ]),
                                    ],
                                  ),
                                );
                              },
                            )),

          // ── Footer ──────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(14)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                'Applying credits reduces the bill balance and '
                'consumes the vendor advance.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              )),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Close'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
