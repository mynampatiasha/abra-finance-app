// ============================================================================
// VENDOR CREDIT DETAIL PAGE
// ============================================================================
// File: lib/screens/billing/pages/vendor_credit_detail.dart
// View credit + Apply to Bill + Refund + Full history
// Navy blue gradient theme | Fully responsive
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/vendor_credit_service.dart';
import 'new_vendor_credit.dart';

const Color _navyDark = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A3A6B);
const Color _navyLight = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class VendorCreditDetailPage extends StatefulWidget {
  final String creditId;

  const VendorCreditDetailPage({Key? key, required this.creditId}) : super(key: key);

  @override
  State<VendorCreditDetailPage> createState() => _VendorCreditDetailPageState();
}

class _VendorCreditDetailPageState extends State<VendorCreditDetailPage> {
  VendorCredit? _credit;
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
      final c = await VendorCreditService.getVendorCredit(widget.creditId);
      setState(() { _credit = c; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  // -----------------------------------------------------------------------
  // APPLY TO BILL DIALOG
  // -----------------------------------------------------------------------

  void _showApplyDialog() {
    if (_credit == null || _credit!.balanceAmount <= 0) {
      _showError('No balance available to apply');
      return;
    }

    final amountCtrl = TextEditingController(text: _credit!.balanceAmount.toStringAsFixed(2));
    final billNumCtrl = TextEditingController();
    String? selectedBillId;
    bool isLoading = false;
    bool loadingBills = true;
    List<Map<String, dynamic>> openBills = [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          // Load open bills for this vendor
          if (loadingBills && openBills.isEmpty) {
            VendorCreditService.getOpenBillsForVendor(_credit!.vendorId).then((bills) {
              setS(() { openBills = bills; loadingBills = false; });
            }).catchError((_) => setS(() => loadingBills = false));
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_navyDark, _navyLight]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Apply Credit to Bill',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text('Available: ₹${_credit!.balanceAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 13, color: _navyAccent)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Credit info banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _navyAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _navyAccent.withOpacity(0.25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _infoCol('Credit #', _credit!.creditNumber),
                          _infoCol('Total', '₹${_credit!.totalAmount.toStringAsFixed(2)}'),
                          _infoCol('Applied', '₹${_credit!.appliedAmount.toStringAsFixed(2)}'),
                          _infoCol('Balance', '₹${_credit!.balanceAmount.toStringAsFixed(2)}',
                              valueColor: _navyAccent),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Select Bill
                    const Text('Select Bill to Apply Against *',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    if (loadingBills)
                      const Center(child: Padding(
                          padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                    else if (openBills.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          const Icon(Icons.info_outline, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('No open bills found for ${_credit!.vendorName}',
                                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                              const SizedBox(height: 4),
                              const Text('Enter bill number manually below:',
                                  style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          )),
                        ]),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButton<String>(
                          hint: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text('Select an open bill')),
                          value: selectedBillId,
                          isExpanded: true,
                          underline: const SizedBox(),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          items: openBills.map((b) => DropdownMenuItem<String>(
                            value: b['_id']?.toString() ?? b['id']?.toString() ?? '',
                            child: Text('${b['billNumber']} — ₹${(b['amountDue'] ?? 0).toStringAsFixed(2)} due'),
                          )).toList(),
                          onChanged: (v) {
                            setS(() {
                              selectedBillId = v;
                              final bill = openBills.firstWhere(
                                (b) => (b['_id'] ?? b['id']).toString() == v, orElse: () => {});
                              if (bill.isNotEmpty) {
                                billNumCtrl.text = bill['billNumber']?.toString() ?? '';
                                final amtDue = double.tryParse(bill['amountDue']?.toString() ?? '') ?? 0;
                                amountCtrl.text = amtDue.clamp(0, _credit!.balanceAmount).toStringAsFixed(2);
                              }
                            });
                          },
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Manual bill number if needed
                    TextFormField(
                      controller: billNumCtrl,
                      decoration: InputDecoration(
                        labelText: 'Bill Number *',
                        hintText: 'e.g., BILL-2024-001',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.receipt),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Amount
                    TextFormField(
                      controller: amountCtrl,
                      decoration: InputDecoration(
                        labelText: 'Amount to Apply *',
                        prefixText: '₹ ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        helperText: 'Max: ₹${_credit!.balanceAmount.toStringAsFixed(2)}',
                        suffixIcon: TextButton(
                          onPressed: () => setS(() =>
                              amountCtrl.text = _credit!.balanceAmount.toStringAsFixed(2)),
                          child: const Text('Full'),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: isLoading ? null : () async {
                  final billNum = billNumCtrl.text.trim();
                  if (billNum.isEmpty) { _showError('Please enter a bill number'); return; }
                  final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                  if (amount <= 0) { _showError('Please enter a valid amount'); return; }
                  if (amount > _credit!.balanceAmount + 0.01) {
                    _showError('Amount exceeds available balance'); return;
                  }

                  setS(() => isLoading = true);
                  try {
                    await VendorCreditService.applyToBill(_credit!.id, {
                      'billId': selectedBillId ?? '',
                      'billNumber': billNum,
                      'amount': amount,
                      'appliedDate': DateTime.now().toIso8601String(),
                    });
                    Navigator.pop(ctx);
                    _showSuccess('₹${amount.toStringAsFixed(2)} applied to bill $billNum');
                    setState(() => _changed = true);
                    _load();
                  } catch (e) {
                    setS(() => isLoading = false);
                    _showError('Failed to apply credit: $e');
                  }
                },
                icon: isLoading
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(isLoading ? 'Applying...' : 'Apply Credit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navyAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // -----------------------------------------------------------------------
  // REFUND DIALOG
  // -----------------------------------------------------------------------

  void _showRefundDialog() {
    if (_credit == null || _credit!.balanceAmount <= 0) {
      _showError('No balance available to refund');
      return;
    }

    final amountCtrl = TextEditingController(text: _credit!.balanceAmount.toStringAsFixed(2));
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime refundDate = DateTime.now();
    String paymentMode = 'Bank Transfer';
    bool isLoading = false;

    final modes = ['Cash', 'Cheque', 'Bank Transfer', 'UPI', 'NEFT', 'RTGS', 'IMPS', 'Online'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Colors.green, Color(0xFF1B5E20)]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.currency_rupee, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Refund from Vendor',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    Text('Available: ₹${_credit!.balanceAmount.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, color: Colors.green[700])),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline, color: Colors.green[700], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'A refund means the vendor will pay back ₹${_credit!.balanceAmount.toStringAsFixed(2)} to you. '
                          'This will be recorded as income to your bank account.',
                          style: TextStyle(fontSize: 12, color: Colors.green[800]),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Amount
                  TextFormField(
                    controller: amountCtrl,
                    decoration: InputDecoration(
                      labelText: 'Refund Amount *',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      helperText: 'Max: ₹${_credit!.balanceAmount.toStringAsFixed(2)}',
                      suffixIcon: TextButton(
                        onPressed: () => setS(() =>
                            amountCtrl.text = _credit!.balanceAmount.toStringAsFixed(2)),
                        child: const Text('Full'),
                      ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),

                  // Refund Date
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: refundDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (d != null) setS(() => refundDate = d);
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Refund Date *',
                        prefixIcon: const Icon(Icons.calendar_today),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(DateFormat('dd MMM yyyy').format(refundDate)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Payment Mode
                  DropdownButtonFormField<String>(
                    value: paymentMode,
                    decoration: InputDecoration(
                      labelText: 'Refund Mode *',
                      prefixIcon: const Icon(Icons.account_balance),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: modes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (v) { if (v != null) setS(() => paymentMode = v); },
                  ),
                  const SizedBox(height: 16),

                  // Reference
                  TextFormField(
                    controller: refCtrl,
                    decoration: InputDecoration(
                      labelText: 'Reference / Transaction Number',
                      prefixIcon: const Icon(Icons.receipt),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  TextFormField(
                    controller: notesCtrl,
                    decoration: InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: isLoading ? null : () async {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                if (amount <= 0) { _showError('Enter valid amount'); return; }
                if (amount > _credit!.balanceAmount + 0.01) {
                  _showError('Amount exceeds balance'); return;
                }

                setS(() => isLoading = true);
                try {
                  await VendorCreditService.refundCredit(_credit!.id, {
                    'amount': amount,
                    'refundDate': refundDate.toIso8601String(),
                    'paymentMode': paymentMode,
                    'referenceNumber': refCtrl.text.trim(),
                    'notes': notesCtrl.text.trim(),
                  });
                  Navigator.pop(ctx);
                  _showSuccess('Refund of ₹${amount.toStringAsFixed(2)} recorded successfully');
                  setState(() => _changed = true);
                  _load();
                } catch (e) {
                  setS(() => isLoading = false);
                  _showError('Failed: $e');
                }
              },
              icon: isLoading
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.currency_rupee),
              label: Text(isLoading ? 'Processing...' : 'Record Refund'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // HELPERS
  // -----------------------------------------------------------------------

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));

  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

  Widget _infoCol(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
            color: valueColor ?? _navyDark)),
      ],
    );
  }

  // -----------------------------------------------------------------------
  // BUILD
  // -----------------------------------------------------------------------

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
          title: Text(
            _credit?.creditNumber ?? 'Vendor Credit Detail',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            if (_credit != null && (_credit!.status == 'OPEN' || _credit!.status == 'PARTIALLY_APPLIED')) ...[
              TextButton.icon(
                onPressed: _showApplyDialog,
                icon: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 18),
                label: const Text('Apply to Bill', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _showRefundDialog,
                icon: const Icon(Icons.currency_rupee, color: Colors.greenAccent, size: 18),
                label: const Text('Refund', style: TextStyle(color: Colors.greenAccent)),
              ),
              const SizedBox(width: 8),
            ],
            if (_credit != null && _credit!.status != 'CLOSED' && _credit!.status != 'VOID')
              TextButton.icon(
                onPressed: () async {
                  final r = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => NewVendorCreditScreen(creditId: widget.creditId)));
                  if (r == true) { setState(() => _changed = true); _load(); }
                },
                icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
                label: const Text('Edit', style: TextStyle(color: Colors.white70)),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _load,
              tooltip: 'Refresh',
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final c = _credit!;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _buildMainScroll(c)),
            SizedBox(
              width: 320,
              child: Container(
                color: Colors.white,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _buildAmountSidebar(c),
                ),
              ),
            ),
          ],
        );
      } else {
        return SingleChildScrollView(
          child: Column(
            children: [
              _buildMainScroll(c, isScrollable: false),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: _buildAmountSidebar(c),
              ),
            ],
          ),
        );
      }
    });
  }

  Widget _buildMainScroll(VendorCredit c, {bool isScrollable = true}) {
    final content = Column(
      children: [
        // Header card with gradient
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_navyDark, _navyMid],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
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
                        Text(c.creditNumber,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(c.vendorName,
                            style: const TextStyle(color: Colors.white70, fontSize: 15)),
                        if (c.vendorEmail != null)
                          Text(c.vendorEmail!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  _glowBadge(c.status),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _headerInfo('Credit Date', DateFormat('dd MMM yyyy').format(c.creditDate)),
                  const SizedBox(width: 24),
                  if (c.billNumber != null) _headerInfo('Bill Reference', c.billNumber!),
                  const SizedBox(width: 24),
                  _headerInfo('Reason', c.reason),
                ],
              ),
            ],
          ),
        ),

        // Action buttons (mobile)
        if (c.status == 'OPEN' || c.status == 'PARTIALLY_APPLIED')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(builder: (context, constraints) {
              return Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    onPressed: _showApplyDialog,
                    icon: const Icon(Icons.account_balance_wallet, size: 18),
                    label: const Text('Apply to Bill'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navyAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showRefundDialog,
                    icon: const Icon(Icons.currency_rupee, size: 18),
                    label: const Text('Request Refund'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              );
            }),
          ),

        const SizedBox(height: 16),

        // Line Items
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
                DataColumn(label: Text('ACCOUNT')),
                DataColumn(label: Text('QTY')),
                DataColumn(label: Text('RATE')),
                DataColumn(label: Text('DISCOUNT')),
                DataColumn(label: Text('AMOUNT')),
              ],
              rows: c.items.map((item) => DataRow(cells: [
                DataCell(SizedBox(width: 200, child: Text(item.itemDetails, overflow: TextOverflow.ellipsis))),
                DataCell(Text(item.account ?? '—')),
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

        const SizedBox(height: 16),

        // Applications History
        if (c.applications.isNotEmpty)
          _detailCard(
            title: 'Applied to Bills',
            icon: Icons.check_circle,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: c.applications.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (_, i) {
                final a = c.applications[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt, color: Colors.green, size: 20),
                  ),
                  title: Text('Applied to ${a.billNumber}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(DateFormat('dd MMM yyyy').format(a.appliedDate),
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  trailing: Text('₹${a.amount.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
                );
              },
            ),
          ),

        if (c.applications.isNotEmpty) const SizedBox(height: 16),

        // Refunds History
        if (c.refunds.isNotEmpty)
          _detailCard(
            title: 'Refund History',
            icon: Icons.currency_rupee,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: c.refunds.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
              itemBuilder: (_, i) {
                final r = c.refunds[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.currency_rupee, color: _navyAccent, size: 20),
                  ),
                  title: Text('${r.paymentMode} Refund',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('dd MMM yyyy').format(r.refundDate),
                          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      if (r.referenceNumber != null)
                        Text('Ref: ${r.referenceNumber}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                    ],
                  ),
                  isThreeLine: r.referenceNumber != null,
                  trailing: Text('₹${r.amount.toStringAsFixed(2)}',
                      style: const TextStyle(color: _navyAccent, fontWeight: FontWeight.bold, fontSize: 15)),
                );
              },
            ),
          ),

        if (c.notes != null && c.notes!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _detailCard(
            title: 'Notes',
            icon: Icons.note,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(c.notes!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );

    if (isScrollable) {
      return SingleChildScrollView(child: content);
    }
    return content;
  }

  Widget _buildAmountSidebar(VendorCredit c) {
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
          const Text('Credit Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
        ]),
        const SizedBox(height: 16),
        _amtRow('Sub Total', c.subTotal),
        if (c.tdsAmount > 0) _amtRow('TDS', -c.tdsAmount, color: Colors.red[700]),
        if (c.tcsAmount > 0) _amtRow('TCS', c.tcsAmount),
        if (c.cgst > 0) _amtRow('CGST', c.cgst),
        if (c.sgst > 0) _amtRow('SGST', c.sgst),
        const Divider(thickness: 2),
        _amtRow('Total Credit', c.totalAmount, isBold: true, isTotal: true),
        const SizedBox(height: 16),

        // Status breakdown
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_navyDark.withOpacity(0.06), _navyLight.withOpacity(0.08)],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _navyAccent.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              _balanceRow('Total Amount', '₹${c.totalAmount.toStringAsFixed(2)}', Colors.blue),
              const SizedBox(height: 8),
              _balanceRow('Applied', '₹${c.appliedAmount.toStringAsFixed(2)}', Colors.green),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _balanceRow('Balance Remaining', '₹${c.balanceAmount.toStringAsFixed(2)}',
                  c.balanceAmount > 0 ? _navyAccent : Colors.grey,
                  isBold: true),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Action buttons in sidebar
        if (c.status == 'OPEN' || c.status == 'PARTIALLY_APPLIED') ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showApplyDialog,
              icon: const Icon(Icons.account_balance_wallet, size: 18),
              label: const Text('Apply to Bill'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navyAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showRefundDialog,
              icon: const Icon(Icons.currency_rupee, size: 18),
              label: const Text('Request Refund'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

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

  Widget _glowBadge(String status) {
    Color bg, fg;
    switch (status) {
      case 'OPEN': bg = Colors.orange; fg = Colors.white; break;
      case 'PARTIALLY_APPLIED': bg = Colors.purple; fg = Colors.white; break;
      case 'CLOSED': bg = Colors.green; fg = Colors.white; break;
      case 'VOID': bg = Colors.grey; fg = Colors.white; break;
      default: bg = _navyAccent; fg = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg, width: 1.5),
      ),
      child: Text(status.replaceAll('_', ' '),
          style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
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
          Text(
            '${amount < 0 ? '-' : ''}₹${amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 16 : 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? (isTotal ? _navyAccent : _navyDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13,
            fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
            color: Colors.grey[700])),
        Text(value, style: TextStyle(fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: color)),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text('Error Loading Credit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
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