// ============================================================================
// EXPENSE DETAIL PAGE — with PDF/Image download, Share, Proof viewer
// ============================================================================
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import '../../../../core/services/expenses_service.dart';
import '../../../../core/services/api_service.dart';
import 'new_expenses.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);

class ExpenseDetailPage extends StatefulWidget {
  final String expenseId;
  const ExpenseDetailPage({Key? key, required this.expenseId}) : super(key: key);

  @override
  State<ExpenseDetailPage> createState() => _ExpenseDetailPageState();
}

class _ExpenseDetailPageState extends State<ExpenseDetailPage> {
  Expense? _expense;
  bool _isLoading = true;
  String? _error;
  bool _changed = false;
  final ExpenseService _service = ExpenseService();
  final ApiService _api = ApiService();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final resp = await _service.getExpenseById(widget.expenseId);
      setState(() { _expense = Expense.fromJson(resp['data']); _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  // ── Auth-header blob fetch ─────────────────────────────────────────────────
  Future<void> _fetchAndOpen(String url, String filename, {bool download = false}) async {
    try {
      _snack('Preparing file…', Colors.blue);
      final headers = await _api.getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) throw Exception('Server returned ${response.statusCode}');

      final bytes = response.bodyBytes;
      final ct = response.headers['content-type'] ?? 'application/octet-stream';
      final mimeType = ct.split(';').first.trim();

      if (kIsWeb) {
        final blob = html.Blob([bytes], mimeType);
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        if (download) {
          html.AnchorElement(href: blobUrl)
            ..setAttribute('download', filename)
            ..click();
        } else {
          html.window.open(blobUrl, '_blank');
        }
        Future.delayed(const Duration(seconds: 5), () => html.Url.revokeObjectUrl(blobUrl));
        _snack(download ? '✅ Download started' : '✅ File opened', Colors.green);
      } else {
        // Mobile — save to temp directory and open with system viewer
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(bytes);
        final result = await OpenFile.open(file.path);
        if (result.type == ResultType.done) {
          _snack('✅ File opened', Colors.green);
        } else {
          _snack('No app found to open this file', Colors.orange);
        }
      }
    } catch (e) {
      _snack('Failed: $e', Colors.red);
    }
  }

  // ── Download expense PDF ───────────────────────────────────────────────────
  Future<void> _downloadPDF() async {
    if (_expense == null) return;
    final url = '${_api.baseUrl}/api/finance/expenses/${widget.expenseId}/pdf';
    await _fetchAndOpen(url, '${_expense!.expenseNumber ?? 'expense'}.pdf', download: true);
  }

  // ── View proof/receipt ─────────────────────────────────────────────────────
  Future<void> _viewAttachment(String url, String filename, {bool download = false}) async {
    await _fetchAndOpen(url, filename, download: download);
  }

  // ── Share ──────────────────────────────────────────────────────────────────
  Future<void> _share() async {
    if (_expense == null) return;
    String date = _expense!.date;
    try { date = DateFormat('dd MMM yyyy').format(DateTime.parse(_expense!.date)); } catch (_) {}
    final text = 'Expense Details\n'
        '─────────────────────────\n'
        'Expense # : ${_expense!.expenseNumber ?? '-'}\n'
        'Date      : $date\n'
        'Account   : ${_expense!.expenseAccount}\n'
        'Vendor    : ${_expense!.vendor ?? '-'}\n'
        'Amount    : ₹${_expense!.amount.toStringAsFixed(2)}\n'
        'Tax       : ₹${_expense!.tax.toStringAsFixed(2)}\n'
        'Total     : ₹${_expense!.total.toStringAsFixed(2)}\n'
        'Paid Via  : ${_expense!.paidThrough}';
    try {
      await Share.share(text, subject: 'Expense: ${_expense!.expenseNumber ?? ''}');
    } catch (e) {
      _snack('Share failed: $e', Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
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
          title: Text(_expense?.expenseNumber ?? 'Expense Detail',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            if (_expense != null) ...[
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                onPressed: _downloadPDF,
                tooltip: 'Download PDF',
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white),
                onPressed: _share,
                tooltip: 'Share',
              ),
            ],
            TextButton.icon(
              onPressed: () async {
                final r = await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => NewExpensePage(expenseId: widget.expenseId)));
                if (r == true) { setState(() => _changed = true); _load(); }
              },
              icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
              label: const Text('Edit', style: TextStyle(color: Colors.white70)),
            ),
            IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _load),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final e = _expense!;
    return LayoutBuilder(builder: (context, constraints) {
      final isWide = constraints.maxWidth > 900;
      if (isWide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _buildMainScroll(e)),
          SizedBox(width: 320, child: Container(
            color: Colors.white,
            child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: _buildSidebar(e)),
          )),
        ]);
      } else {
        return SingleChildScrollView(child: Column(children: [
          _buildMainScroll(e, isScrollable: false),
          Container(color: Colors.white, padding: const EdgeInsets.all(20), child: _buildSidebar(e)),
        ]));
      }
    });
  }

  Widget _buildMainScroll(Expense e, {bool isScrollable = true}) {
    String formattedDate = e.date;
    try { formattedDate = DateFormat('dd MMM yyyy').format(DateTime.parse(e.date)); } catch (_) {}

    final content = Column(children: [
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.expenseNumber ?? 'Expense',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if ((e.vendor ?? '').isNotEmpty)
                Text(e.vendor!, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              Text(formattedDate, style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
            _glowBadge('RECORDED'),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 8, children: [
            _headerInfo('Account', e.expenseAccount),
            _headerInfo('Paid Through', e.paidThrough),
            if ((e.invoiceNumber ?? '').isNotEmpty) _headerInfo('Invoice #', e.invoiceNumber!),
          ]),
        ]),
      ),

      const SizedBox(height: 16),

      // Details card
      _detailCard(
        title: 'Expense Details', icon: Icons.receipt_long,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _infoRow('Date', formattedDate),
            _infoRow('Expense Account', e.expenseAccount),
            _infoRow('Paid Through', e.paidThrough),
            if ((e.vendor ?? '').isNotEmpty) _infoRow('Vendor', e.vendor!),
            if ((e.customerName ?? '').isNotEmpty) _infoRow('Customer', e.customerName!),
            if ((e.invoiceNumber ?? '').isNotEmpty) _infoRow('Invoice #', e.invoiceNumber!),
            _infoRow('Billable', e.isBillable ? 'Yes' : 'No'),
          ]),
        ),
      ),

      if (e.isItemized && e.itemizedExpenses.isNotEmpty) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Itemized Expenses', icon: Icons.list_alt,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(_navyDark.withOpacity(0.9)),
              headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              columns: const [
                DataColumn(label: Text('ACCOUNT')),
                DataColumn(label: Text('DESCRIPTION')),
                DataColumn(label: Text('AMOUNT')),
              ],
              rows: e.itemizedExpenses.map((item) => DataRow(cells: [
                DataCell(Text(item.expenseAccount ?? '—')),
                DataCell(SizedBox(width: 200, child: Text(item.description ?? '—', overflow: TextOverflow.ellipsis))),
                DataCell(Text('₹${item.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600))),
              ])).toList(),
            ),
          ),
        ),
      ],

      // Proof / Receipt attachments
      if (e.proofFile != null || e.receiptFile != null) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Attachments', icon: Icons.attach_file,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              if (e.proofFile != null)
                _attachmentRow(
                  label: e.proofFile!.originalName,
                  url: '${_api.baseUrl}/api/finance/expenses/${widget.expenseId}/proof',
                  filename: e.proofFile!.originalName,
                  icon: _fileIcon(e.proofFile!.originalName),
                ),
              if (e.proofFile != null && e.receiptFile != null) const SizedBox(height: 10),
              if (e.receiptFile != null)
                _attachmentRow(
                  label: e.receiptFile!.originalName,
                  url: '${_api.baseUrl}/api/finance/expenses/${widget.expenseId}/receipt',
                  filename: e.receiptFile!.originalName,
                  icon: _fileIcon(e.receiptFile!.originalName),
                ),
            ]),
          ),
        ),
      ],

      if ((e.notes ?? '').isNotEmpty) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Notes', icon: Icons.note,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(e.notes!, style: TextStyle(color: Colors.grey[800], fontSize: 14)),
          ),
        ),
      ],

      const SizedBox(height: 24),
    ]);

    return isScrollable ? SingleChildScrollView(child: content) : content;
  }

  Widget _attachmentRow({
    required String label,
    required String url,
    required String filename,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _navyAccent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _navyAccent.withOpacity(0.2)),
      ),
      child: Row(children: [
        Icon(icon, color: _navyAccent, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => _viewAttachment(url, filename, download: false),
          icon: const Icon(Icons.visibility, size: 15),
          label: const Text('View', style: TextStyle(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navyAccent,
            side: BorderSide(color: _navyAccent),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 6),
        ElevatedButton.icon(
          onPressed: () => _viewAttachment(url, filename, download: true),
          icon: const Icon(Icons.download, size: 15),
          label: const Text('Download', style: TextStyle(fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _navyAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ]),
    );
  }

  IconData _fileIcon(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    if (ext == 'pdf') return Icons.picture_as_pdf;
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return Icons.image;
    return Icons.insert_drive_file;
  }

  Widget _buildSidebar(Expense e) {
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
        const Text('Amount Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      ]),
      const SizedBox(height: 16),
      _amtRow('Amount', e.amount),
      if (e.tax > 0) _amtRow('Tax', e.tax),
      const Divider(thickness: 2),
      _amtRow('Total', e.total, isBold: true, isTotal: true),
      const SizedBox(height: 16),
      // Quick action buttons
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: _downloadPDF,
          icon: const Icon(Icons.download, size: 16),
          label: const Text('PDF'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navyMid, side: BorderSide(color: _navyMid),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        )),
        const SizedBox(width: 8),
        Expanded(child: OutlinedButton.icon(
          onPressed: _share,
          icon: const Icon(Icons.share, size: 16),
          label: const Text('Share'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navyMid, side: BorderSide(color: _navyMid),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        )),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, _changed),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back to List'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _navyMid, side: BorderSide(color: _navyMid),
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

  Widget _headerInfo(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
    ],
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 140, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13))),
      Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
    ]),
  );

  Widget _amtRow(String label, double amount, {Color? color, bool isBold = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(
          fontSize: isTotal ? 14 : 13,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color ?? (isTotal ? _navyDark : Colors.grey[700]),
        )),
        Text('₹${amount.toStringAsFixed(2)}', style: TextStyle(
          fontSize: isTotal ? 16 : 13,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          color: color ?? (isTotal ? _navyAccent : _navyDark),
        )),
      ]),
    );
  }

  Widget _glowBadge(String status) {
    Color bg;
    switch (status.toUpperCase()) {
      case 'OPEN': bg = Colors.orange; break;
      case 'PAID': bg = Colors.green; break;
      case 'VOID': case 'CANCELLED': bg = Colors.grey; break;
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

  Widget _buildError() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
    const SizedBox(height: 16),
    Text('Error Loading Expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
    const SizedBox(height: 8),
    Text(_error ?? '', style: TextStyle(color: Colors.grey[600])),
    const SizedBox(height: 24),
    ElevatedButton.icon(
      onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry'),
      style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white),
    ),
  ]));
}
