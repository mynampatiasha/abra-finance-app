// ============================================================================
// PAYMENT RECEIVED DETAIL PAGE — Fixed keys + inline proof images + upload
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import '../../../../core/services/api_service.dart';
import '../../../../core/services/payment_service.dart';
import 'new_payment_page.dart';

const Color _navyDark   = Color(0xFF0D1B3E);
const Color _navyMid    = Color(0xFF1A3A6B);
const Color _navyLight  = Color(0xFF2463AE);
const Color _navyAccent = Color(0xFF3D8EFF);
const Color _orange     = Color(0xFFF59E0B);
const Color _green      = Color(0xFF27AE60);
const Color _red        = Color(0xFFE74C3C);
const Color _teal       = Color(0xFF16A085);
const Color _purple     = Color(0xFF9B59B6);

class PaymentReceivedDetailPage extends StatefulWidget {
  final Map<String, dynamic> payment;
  const PaymentReceivedDetailPage({Key? key, required this.payment}) : super(key: key);

  @override
  State<PaymentReceivedDetailPage> createState() => _PaymentReceivedDetailPageState();
}

class _PaymentReceivedDetailPageState extends State<PaymentReceivedDetailPage> {
  // Full payment data — loaded fresh from API so all keys are correct
  Map<String, dynamic> _payment = {};
  List<PaymentProof> _proofs = [];
  bool _loadingPayment = true;
  bool _loadingProofs  = false;
  bool _uploadingProof = false;
  bool _marking        = false;
  String? _loadError;

  final ApiService _api = ApiService();

  // ── helpers to safely read fields from the raw MongoDB document ───────────
  String _str(String key, [String fallback = '—']) {
    final v = _payment[key];
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }
  double _dbl(String key) => double.tryParse(_payment[key]?.toString() ?? '') ?? 0.0;

  String get _paymentId =>
      _payment['_id']?.toString() ?? _payment['id']?.toString() ??
      widget.payment['_id']?.toString() ?? widget.payment['id']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    // Seed with the slim list-page map so the appbar title shows immediately
    _payment = Map<String, dynamic>.from(widget.payment);
    _loadFull();
  }

  // ── Load full payment from API ─────────────────────────────────────────────
  Future<void> _loadFull() async {
    setState(() { _loadingPayment = true; _loadError = null; });
    try {
      final id = _paymentId;
      if (id.isEmpty) throw Exception('Payment ID not available');
      final fresh = await PaymentService.getPayment(id);
      setState(() { _payment = fresh; _loadingPayment = false; });
      _loadProofs();
    } catch (e) {
      setState(() { _loadingPayment = false; _loadError = e.toString(); });
    }
  }

  Future<void> _markAsSent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark as Sent?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'The email will NOT be sent to the customer.\n\nDo you want to mark this payment as Sent anyway?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _navyDark, foregroundColor: Colors.white),
            child: const Text('Mark as Sent'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _marking = true);
    try {
      await PaymentService.markPaymentAsSent(_paymentId);
      setState(() { _payment = {..._payment, 'status': 'sent'}; });
      _snack('Payment marked as sent', _green);
    } catch (e) {
      _snack('Failed: $e', _red);
    } finally {
      setState(() => _marking = false);
    }
  }

  Future<void> _loadProofs() async {
    if (_paymentId.isEmpty) return;
    setState(() => _loadingProofs = true);
    try {
      final proofs = await PaymentService.getPaymentProofs(_paymentId);
      setState(() { _proofs = proofs; _loadingProofs = false; });
    } catch (_) {
      setState(() => _loadingProofs = false);
    }
  }

  // ── Fetch image bytes with auth headers ────────────────────────────────────
  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      final headers = await _api.getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  // ── Download / view a proof file ───────────────────────────────────────────
  Future<void> _downloadProof(int index) async {
    try {
      _snack('Preparing download…', Colors.blue);
      final url = '${_api.baseUrl}/api/finance/payments-received/$_paymentId/proofs/$index/download';
      final headers = await _api.getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) throw Exception('Server returned ${response.statusCode}');
      final bytes    = response.bodyBytes;
      final ct       = response.headers['content-type'] ?? 'application/octet-stream';
      final mimeType = ct.split(';').first.trim();
      final filename = _proofs[index].filename;
      if (kIsWeb) {
        final blob    = html.Blob([bytes], mimeType);
        final blobUrl = html.Url.createObjectUrlFromBlob(blob);
        html.AnchorElement(href: blobUrl)
          ..setAttribute('download', filename)
          ..click();
        Future.delayed(const Duration(seconds: 5), () => html.Url.revokeObjectUrl(blobUrl));
        _snack('✅ Download started', _green);
      } else {
        final dir    = await getTemporaryDirectory();
        final file   = File('${dir.path}/$filename');
        await file.writeAsBytes(bytes);
        final result = await OpenFile.open(file.path);
        if (result.type != ResultType.done) _snack('No app found to open this file', Colors.orange);
        else _snack('✅ File opened', _green);
      }
    } catch (e) {
      _snack('Download failed: $e', _red);
    }
  }

  // ── Delete a proof ─────────────────────────────────────────────────────────
  Future<void> _deleteProof(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Proof?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Remove "${_proofs[index].filename}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PaymentService.deletePaymentProof(_paymentId, index);
      _snack('Proof deleted', _green);
      _loadProofs();
    } catch (e) {
      _snack('Delete failed: $e', _red);
    }
  }

  // ── Upload new proof(s) ────────────────────────────────────────────────────
  Future<void> _uploadProof() async {
    // Show source picker
    if (!mounted) return;
    final source = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: _PaymentProofSourceSheet(),
      ),
    );
    if (source == null) return;

    Uint8List? bytes;
    String?    fileName;
    String?    mimeType;

    if (source == 'camera') {
      if (kIsWeb) {
        final completer = Completer<void>();
        final input = html.FileUploadInputElement()
          ..accept = 'image/*'
          ..setAttribute('capture', 'environment');
        input.click();
        input.onChange.listen((e) {
          final file = input.files?.first;
          if (file == null) { completer.complete(); return; }
          final reader = html.FileReader();
          reader.readAsArrayBuffer(file);
          reader.onLoad.listen((_) {
            bytes    = Uint8List.fromList(reader.result as List<int>);
            fileName = file.name.isNotEmpty ? file.name : 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
            mimeType = file.type.isNotEmpty ? file.type : 'image/jpeg';
            completer.complete();
          });
          reader.onError.listen((_) => completer.complete());
        });
        await completer.future;
        if (bytes == null) return;
      } else {
        try {
          final picker = ImagePicker();
          final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2048, maxHeight: 2048);
          if (picked == null) return;
          bytes    = await picked.readAsBytes();
          fileName = picked.name.isNotEmpty ? picked.name : 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
          mimeType = 'image/jpeg';
        } catch (e) {
          _snack('Could not open camera: $e', _red);
          return;
        }
      }
    } else {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'pdf'],
          allowMultiple: false,
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.first;
        bytes    = file.bytes;
        fileName = file.name;
        final ext = (file.extension ?? '').toLowerCase();
        mimeType = ext == 'pdf' ? 'application/pdf' : 'image/$ext';
        if (bytes == null) { _snack('Could not read file', _red); return; }
      } catch (e) {
        _snack('File picker error: $e', _red);
        return;
      }
    }

    const maxBytes = 10 * 1024 * 1024;
    final nonNullBytes = bytes!;
    if (nonNullBytes.length > maxBytes) {
      _snack('File too large (${(nonNullBytes.length / 1024 / 1024).toStringAsFixed(1)} MB). Max 10 MB.', _red);
      return;
    }

    setState(() => _uploadingProof = true);
    try {
      final multipartFile = http.MultipartFile.fromBytes('paymentProofs', nonNullBytes, filename: fileName);
      await PaymentService.addPaymentProofs(_paymentId, [multipartFile]);
      _snack('✅ Proof uploaded: $fileName', _green);
      _loadProofs();
    } catch (e) {
      _snack('Upload error: $e', _red);
    } finally {
      setState(() => _uploadingProof = false);
    }
  }

  // ── Full-screen image viewer ───────────────────────────────────────────────
  void _showFullScreenImage(Uint8List bytes, String filename) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(children: [
          InteractiveViewer(
            panEnabled: true, minScale: 0.5, maxScale: 5.0,
            child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
          ),
          Positioned(
            top: 40, right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 26),
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.5), padding: const EdgeInsets.all(10)),
            ),
          ),
          Positioned(
            bottom: 20, left: 0, right: 0,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(20)),
              child: Text(filename, style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis),
            )),
          ),
        ]),
      ),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _loadingPayment
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
    const SizedBox(height: 16),
    Text('Failed to load payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[700])),
    const SizedBox(height: 8),
    Text(_loadError ?? '', style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
    const SizedBox(height: 24),
    ElevatedButton.icon(
      onPressed: _loadFull, icon: const Icon(Icons.refresh), label: const Text('Retry'),
      style: ElevatedButton.styleFrom(backgroundColor: _navyAccent, foregroundColor: Colors.white),
    ),
  ]));

  PreferredSizeWidget _buildAppBar() {
    final title = _payment['paymentNumber']?.toString() ??
        widget.payment['paymentNumber']?.toString() ?? 'Payment Detail';
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
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              tooltip: 'Edit Payment',
              onPressed: () async {
                if (_paymentId.isEmpty) return;
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => NewPaymentPage(paymentId: _paymentId)),
                );
                if (updated == true && mounted) _loadFull();
              },
            ),
            IconButton(
              icon: const Icon(Icons.mark_email_read_outlined, color: Colors.white),
              tooltip: 'Mark as Sent',
              onPressed: _marking ? null : _markAsSent,
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadFull, tooltip: 'Refresh',
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
    // The raw MongoDB doc uses: paymentDate, paymentNumber, customerName,
    // customerEmail, amountReceived, paymentMode, reference, invoicePayments,
    // unusedAmount, bankCharges, notes, status, paymentProofs
    final rawDate = _payment['paymentDate']?.toString() ?? '';
    String paymentDate = '—';
    try {
      if (rawDate.isNotEmpty) {
        paymentDate = DateFormat('dd MMM yyyy').format(DateTime.parse(rawDate));
      }
    } catch (_) {}

    final invoicePayments = (_payment['invoicePaymentsResolved'] as Map<String, dynamic>?) ??
        (_payment['invoicePayments'] as Map<String, dynamic>?) ?? {};

    final content = Column(children: [
      // ── Header card ────────────────────────────────────────────────────────
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
              Text(_str('paymentNumber', 'Payment'),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_str('customerName'), style: const TextStyle(color: Colors.white70, fontSize: 15)),
              if ((_payment['customerEmail'] ?? '').toString().isNotEmpty)
                Text(_str('customerEmail'), style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ])),
            _glowBadge(_str('paymentMode', 'Payment')),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 24, runSpacing: 8, children: [
            _headerInfo('Payment Date', paymentDate),
            _headerInfo('Mode', _str('paymentMode')),
            _headerInfo('Amount', '₹${_dbl('amountReceived').toStringAsFixed(2)}'),
            if ((_payment['reference'] ?? '').toString().isNotEmpty)
              _headerInfo('Reference', _str('reference')),
            if ((_payment['depositToName'] ?? _payment['depositTo'] ?? '').toString().isNotEmpty)
              _headerInfo('Deposit To', (_payment['depositToName'] ?? _payment['depositTo'] ?? '').toString()),
          ]),
        ]),
      ),

      const SizedBox(height: 16),

      // ── Payment Details card ───────────────────────────────────────────────
      _detailCard(
        title: 'Payment Details', icon: Icons.receipt_long,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _infoRow('Payment Date',   paymentDate),
            _infoRow('Payment Mode',   _str('paymentMode')),
            _infoRow('Amount Received','₹${_dbl('amountReceived').toStringAsFixed(2)}'),
            if (_dbl('bankCharges') > 0)
              _infoRow('Bank Charges', '₹${_dbl('bankCharges').toStringAsFixed(2)}'),
            if ((_payment['reference'] ?? '').toString().isNotEmpty)
              _infoRow('Reference #',  _str('reference')),
            if ((_payment['depositToName'] ?? _payment['depositTo'] ?? '').toString().isNotEmpty)
              _infoRow('Deposit To', (_payment['depositToName'] ?? _payment['depositTo'] ?? '').toString()),
            if ((_payment['taxDeduction'] ?? '').toString().isNotEmpty)
              _infoRow('Tax Deduction',_str('taxDeduction')),
            _infoRow('Status', _str('status', 'paid').toUpperCase()),
          ]),
        ),
      ),

      // ── Invoice Allocations ────────────────────────────────────────────────
      if (invoicePayments.isNotEmpty) ...[
        const SizedBox(height: 16),
        _detailCard(
          title: 'Applied to Invoices', icon: Icons.receipt_long,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(children: [
              // Table header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B3E),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  const Expanded(child: Text('Invoice #', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                  Text('Amount Applied', style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.bold, fontSize: 12)),
                ]),
              ),
              ...invoicePayments.entries.map((entry) {
                final amt = double.tryParse(entry.value.toString()) ?? 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
                  ),
                  child: Row(children: [
                    Expanded(child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.receipt, color: Colors.green, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ])),
                    Text('₹${amt.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14)),
                  ]),
                );
              }).toList(),
              // Total row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  const Expanded(child: Text('Total Applied', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  Text(
                    '₹${invoicePayments.values.fold(0.0, (s, v) => s + (double.tryParse(v.toString()) ?? 0)).toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ],

      // ── Payment Proofs ─────────────────────────────────────────────────────
      const SizedBox(height: 16),
      _detailCard(
        title: 'Payment Proofs', icon: Icons.attach_file,
        headerAction: _uploadingProof
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _navyAccent))
            : ElevatedButton.icon(
                onPressed: _uploadProof,
                icon: const Icon(Icons.upload, size: 15),
                label: const Text('Add Proof', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal, foregroundColor: Colors.white, elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
        child: _loadingProofs
            ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
            : _proofs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withOpacity(0.25)),
                      ),
                      child: Row(children: [
                        Icon(Icons.upload_file_outlined, color: Colors.orange.shade700, size: 28),
                        const SizedBox(width: 14),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('No proofs attached', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.orange.shade800)),
                          const SizedBox(height: 3),
                          Text('Tap "Add Proof" to upload a photo or file', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        ])),
                      ]),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _proofs.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[200]),
                    itemBuilder: (_, i) => _buildProofTile(i),
                  ),
      ),

      if ((_payment['notes'] ?? '').toString().isNotEmpty) ...[
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

  // ── Proof tile — image inline, PDF with buttons ────────────────────────────
  Widget _buildProofTile(int index) {
    final proof   = _proofs[index];
    final isImage = _isImageFile(proof.filename);
    final proofUrl = '${_api.baseUrl}/api/finance/payments-received/$_paymentId/proofs/$index/download';

    if (isImage) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Label row
          Row(children: [
            Icon(Icons.image_outlined, color: _navyAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(proof.filename, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
              Text('${(proof.fileSize / 1024).toStringAsFixed(1)} KB • ${DateFormat('dd MMM yyyy').format(proof.uploadedAt)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ])),
            IconButton(
              icon: const Icon(Icons.download, size: 18, color: _navyAccent),
              tooltip: 'Download',
              onPressed: () => _downloadProof(index),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: Colors.red[400]),
              tooltip: 'Delete',
              onPressed: () => _deleteProof(index),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
            ),
          ]),
          const SizedBox(height: 10),
          // Inline image
          FutureBuilder<Uint8List?>(
            future: _fetchImageBytes(proofUrl),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Container(
                  height: 160,
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.data == null) {
                return Container(
                  height: 80,
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                  child: Center(child: Text('Could not load image', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
                );
              }
              final imgBytes = snap.data!;
              return GestureDetector(
                onTap: () => _showFullScreenImage(imgBytes, proof.filename),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    width: double.infinity,
                    decoration: BoxDecoration(border: Border.all(color: _navyAccent.withOpacity(0.2)), borderRadius: BorderRadius.circular(10)),
                    child: Stack(children: [
                      Image.memory(imgBytes, fit: BoxFit.contain, width: double.infinity),
                      Positioned(
                        bottom: 8, right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(6)),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.zoom_in, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text('Tap to expand', style: TextStyle(color: Colors.white, fontSize: 11)),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ]),
      );
    }

    // PDF / other
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: _navyAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(proof.fileType.contains('pdf') ? Icons.picture_as_pdf : Icons.insert_drive_file, color: _navyAccent, size: 20),
      ),
      title: Text(proof.filename, style: const TextStyle(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${(proof.fileSize / 1024).toStringAsFixed(1)} KB • ${DateFormat('dd MMM yyyy').format(proof.uploadedAt)}',
        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.download_rounded, color: _navyAccent), onPressed: () => _downloadProof(index), tooltip: 'Download'),
        IconButton(icon: Icon(Icons.delete_outline, color: Colors.red[400]), onPressed: () => _deleteProof(index), tooltip: 'Delete'),
      ]),
    );
  }

  bool _isImageFile(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
  }

  Widget _buildSidebar() {
    final unusedAmount = _dbl('unusedAmount');
    final amountReceived = _dbl('amountReceived');
    final bankCharges = _dbl('bankCharges');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [_navyDark, _navyLight]), borderRadius: BorderRadius.circular(6)),
          child: const Icon(Icons.summarize, color: Colors.white, size: 16),
        ),
        const SizedBox(width: 8),
        const Text('Payment Summary', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark)),
      ]),
      const SizedBox(height: 16),

      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [_navyDark.withOpacity(0.06), _navyLight.withOpacity(0.08)]),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _navyAccent.withOpacity(0.2)),
        ),
        child: Column(children: [
          _balanceRow('Amount Received', '₹${amountReceived.toStringAsFixed(2)}', Colors.blue),
          if (bankCharges > 0) ...[
            const SizedBox(height: 8),
            _balanceRow('Bank Charges', '₹${bankCharges.toStringAsFixed(2)}', Colors.red),
          ],
          const SizedBox(height: 8),
          _balanceRow('Amount Used', '₹${(amountReceived - unusedAmount).toStringAsFixed(2)}', _green),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          _balanceRow('Unused Amount', '₹${unusedAmount.toStringAsFixed(2)}',
              unusedAmount > 0 ? _navyAccent : Colors.grey, isBold: true),
        ]),
      ),

      const SizedBox(height: 16),

      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green[200]!)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.payment, color: Colors.green[700], size: 18),
            const SizedBox(width: 8),
            Text('Payment Mode', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[800])),
          ]),
          const SizedBox(height: 8),
          Text(_str('paymentMode'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[700])),
          if ((_payment['reference'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Ref: ${_str('reference')}', style: TextStyle(fontSize: 12, color: Colors.green[600])),
          ],
          if ((_payment['depositToName'] ?? _payment['depositTo'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Account: ${(_payment['depositToName'] ?? _payment['depositTo'] ?? '').toString()}',
                style: TextStyle(fontSize: 12, color: Colors.green[600])),
          ],
        ]),
      ),

      const SizedBox(height: 16),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _marking ? null : _markAsSent,
          icon: _marking
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.mark_email_read_outlined, size: 18),
          label: const Text('Mark as Sent'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _orange, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      const SizedBox(height: 10),

      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.pop(context),
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

  Widget _detailCard({required String title, required IconData icon, required Widget child, Widget? headerAction}) {
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
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [_navyDark, _navyLight]), borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _navyDark))),
            if (headerAction != null) headerAction,
          ]),
        ),
        const Divider(height: 1),
        child,
      ]),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 140, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13))),
      Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
    ]),
  );

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

// =============================================================================
//  PROOF SOURCE SHEET (for payment detail page)
// =============================================================================

class _PaymentProofSourceSheet extends StatelessWidget {
  const _PaymentProofSourceSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.attach_file, color: _teal, size: 22),
          const SizedBox(width: 10),
          const Text('Add Proof', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF1A202C))),
        ]),
        const SizedBox(height: 8),
        Text('Choose how to add your proof document', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 20),
        _PaymentSourceTile(
          icon: Icons.camera_alt_rounded,
          color: _navyDark,
          title: 'Take Photo',
          subtitle: 'Use camera to capture the receipt',
          onTap: () => Navigator.pop(context, 'camera'),
        ),
        const SizedBox(height: 10),
        _PaymentSourceTile(
          icon: Icons.folder_open_rounded,
          color: _purple,
          title: 'Choose File',
          subtitle: 'Images (JPG, PNG, WEBP) or PDF — max 10 MB',
          onTap: () => Navigator.pop(context, 'file'),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
        ]),
      ]),
    );
  }
}

class _PaymentSourceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _PaymentSourceTile({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withOpacity(0.8), color], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ])),
          Icon(Icons.chevron_right, color: Colors.grey[400]),
        ]),
      ),
    );
  }
}
