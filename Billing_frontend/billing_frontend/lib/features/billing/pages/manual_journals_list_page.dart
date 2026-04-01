// ============================================================================
// MANUAL JOURNALS LIST PAGE
// - Recurring Invoices UI pattern (3-breakpoint top bar, gradient stat cards,
//   dark navy #0D1B3E table, drag-to-scroll, ellipsis pagination)
// - Share    → share_plus with journal details (web + mobile)
// - WhatsApp → wa.me/?text=<details> (no phone — user picks contact in WhatsApp)
// - Raise Ticket → _RaiseTicketOverlay (employee search + assign + auto message)
// - Import   → 2-step dialog (download CSV template + upload via importJournals)
// - Export   → CSV download of all journals
// ============================================================================
// File: lib/screens/billing/pages/manual_journals_list_page.dart
// ============================================================================

import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/manual_journal_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_manual_journal.dart';
import 'manual_journal_detail.dart';

// ─── colour palette ───────────────────────────────────────────────────────────
const Color _navy   = Color(0xFF1e3a8a);
const Color _purple = Color(0xFF9B59B6);
const Color _green  = Color(0xFF27AE60);
const Color _blue   = Color(0xFF2980B9);
const Color _orange = Color(0xFFE67E22);
const Color _red    = Color(0xFFE74C3C);
const Color _teal   = Color(0xFF16A085);

// ─── stat card data ───────────────────────────────────────────────────────────
class _StatCardData {
  final String label, value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;
  const _StatCardData({
    required this.label, required this.value,
    required this.icon,  required this.color,
    required this.gradientColors,
  });
}

// =============================================================================
//  MAIN PAGE
// =============================================================================

class ManualJournalsListPage extends StatefulWidget {
  const ManualJournalsListPage({Key? key}) : super(key: key);
  @override
  State<ManualJournalsListPage> createState() => _ManualJournalsListPageState();
}

class _ManualJournalsListPageState extends State<ManualJournalsListPage> {

  // ── data ──────────────────────────────────────────────────────────────────
  List<ManualJournal> _journals = [];
  JournalStats?       _stats;
  bool    _isLoading = true;
  String? _error;

  // ── filters ───────────────────────────────────────────────────────────────
  String    _statusFilter = 'All';
  DateTime? _fromDate;
  DateTime? _toDate;
  final _searchCtrl = TextEditingController();
  final _statusOptions = ['All', 'Draft', 'Published', 'Void'];

  // ── pagination ────────────────────────────────────────────────────────────
  int _page       = 1;
  int _totalPages = 1;
  int _total      = 0;

  // ── scroll ────────────────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => _load(resetPage: true));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ── loaders ───────────────────────────────────────────────────────────────

  Future<void> _load({bool resetPage = false}) async {
    if (resetPage) _page = 1;
    setState(() { _isLoading = true; _error = null; });
    try {
      final results = await Future.wait([
        ManualJournalService.getJournals(
          status:   _statusFilter == 'All' ? null : _statusFilter,
          fromDate: _fromDate,
          toDate:   _toDate,
          search:   _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
          page:     _page,
        ),
        ManualJournalService.getStats(),
      ]);
      final list  = results[0] as JournalListResult;
      final stats = results[1] as JournalStats;
      setState(() {
        _journals   = list.journals;
        _stats      = stats;
        _totalPages = list.pages;
        _total      = list.total;
        _isLoading  = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _refresh() async {
    await _load();
    _showSuccess('Data refreshed');
  }

  // ── actions ───────────────────────────────────────────────────────────────

  void _openNew() async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => const NewManualJournalPage()));
    if (ok == true && mounted) _load(resetPage: true);
  }

  void _openEdit(ManualJournal j) async {
    final ok = await Navigator.push(context, MaterialPageRoute(builder: (_) => NewManualJournalPage(journalId: j.id)));
    if (ok == true && mounted) _load();
  }

  void _openDetail(ManualJournal j) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ManualJournalDetailPage(journalId: j.id)))
        .then((_) => _load());
  }

  Future<void> _quickPublish(ManualJournal j) async {
    final ok = await _confirmDialog(
      title: 'Publish Journal',
      message: 'Publish ${j.journalNumber}? This will post all entries to Chart of Accounts.',
      confirmLabel: 'Publish', confirmColor: _green,
    );
    if (ok != true) return;
    try {
      await ManualJournalService.publishJournal(j.id);
      _showSuccess('${j.journalNumber} published and posted to COA');
      _load();
    } catch (e) { _showError(e.toString()); }
  }

  Future<void> _clone(ManualJournal j) async {
    try {
      final cloned = await ManualJournalService.cloneJournal(j.id);
      _showSuccess('Cloned as ${cloned.journalNumber}');
      _load();
    } catch (e) { _showError(e.toString()); }
  }

  Future<void> _void(ManualJournal j) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Void Journal', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Void ${j.journalNumber}? This will reverse all COA entries.'),
          const SizedBox(height: 14),
          TextField(controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason for voiding (optional)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
              child: const Text('Void')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ManualJournalService.voidJournal(j.id, reason: reasonCtrl.text);
      _showSuccess('${j.journalNumber} voided and COA reversed');
      _load();
    } catch (e) { _showError(e.toString()); }
  }

  Future<void> _delete(ManualJournal j) async {
    final ok = await _confirmDialog(
      title: 'Delete Journal',
      message: 'Delete ${j.journalNumber}? This cannot be undone.',
      confirmLabel: 'Delete', confirmColor: _red,
    );
    if (ok != true) return;
    try {
      await ManualJournalService.deleteJournal(j.id);
      _showSuccess('${j.journalNumber} deleted');
      _load();
    } catch (e) { _showError(e.toString()); }
  }

  Future<void> _downloadPDF(ManualJournal j) async {
    try {
      _showSuccess('Preparing PDF download…');
      final pdfUrl = await ManualJournalService.getPdfUrl(j.id);
      if (kIsWeb) {
        html.AnchorElement(href: pdfUrl)
          ..setAttribute('download', '${j.journalNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
        _showSuccess('✅ PDF download started for ${j.journalNumber}');
      } else {
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch PDF viewer';
        }
      }
    } catch (e) {
      _showError('Failed to download PDF: $e');
    }
  }

  // ── share ─────────────────────────────────────────────────────────────────

  Future<void> _share(ManualJournal j) async {
    final text = 'Manual Journal\n'
        '─────────────────────────\n'
        'Journal # : ${j.journalNumber}\n'
        'Date      : ${DateFormat('dd MMM yyyy').format(j.date)}\n'
        '${j.referenceNumber.isNotEmpty ? 'Reference : ${j.referenceNumber}\n' : ''}'
        '${j.notes.isNotEmpty ? 'Notes     : ${j.notes}\n' : ''}'
        'Status    : ${j.status}\n'
        'Debit     : ₹${j.totalDebit.toStringAsFixed(2)}\n'
        'Credit    : ₹${j.totalCredit.toStringAsFixed(2)}\n'
        'Difference: ₹${j.difference.toStringAsFixed(2)}\n'
        'Method    : ${j.reportingMethod}\n'
        'Currency  : ${j.currency}';
    try {
      await Share.share(text, subject: 'Journal: ${j.journalNumber}');
    } catch (e) { _showError('Share failed: $e'); }
  }

  // ── whatsapp ──────────────────────────────────────────────────────────────
  // No phone number — user selects contact in WhatsApp themselves

  Future<void> _whatsApp(ManualJournal j) async {
    final msg = Uri.encodeComponent(
      'Manual Journal: ${j.journalNumber}\n\n'
      'Date      : ${DateFormat('dd MMM yyyy').format(j.date)}\n'
      '${j.referenceNumber.isNotEmpty ? 'Reference : ${j.referenceNumber}\n' : ''}'
      '${j.notes.isNotEmpty ? 'Notes     : ${j.notes}\n' : ''}'
      'Status    : ${j.status}\n'
      'Debit     : ₹${j.totalDebit.toStringAsFixed(2)}\n'
      'Credit    : ₹${j.totalCredit.toStringAsFixed(2)}\n'
      'Difference: ₹${j.difference.toStringAsFixed(2)}\n\n'
      'Please review and revert.',
    );
    // No phone number in URL → WhatsApp opens and user picks the contact
    final url = Uri.parse('https://wa.me/?text=$msg');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open WhatsApp');
    }
  }

  // ── raise ticket ──────────────────────────────────────────────────────────

  void _raiseTicket([ManualJournal? j]) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _RaiseTicketOverlay(
        journal: j,
        onTicketRaised: (msg) => _showSuccess(msg),
        onError:        (msg) => _showError(msg),
      ),
    );
  }

  // ── export ────────────────────────────────────────────────────────────────

  Future<void> _export() async {
    try {
      _showSuccess('Preparing export…');
      final all = await ManualJournalService.getJournals(limit: 10000);
      final rows = <List<dynamic>>[
        ['Journal #','Date','Reference #','Notes','Reporting Method','Currency','Status','Total Debit','Total Credit','Difference'],
        ...all.journals.map((j) => [
          j.journalNumber,
          DateFormat('dd/MM/yyyy').format(j.date),
          j.referenceNumber,
          j.notes,
          j.reportingMethod,
          j.currency,
          j.status,
          j.totalDebit.toStringAsFixed(2),
          j.totalCredit.toStringAsFixed(2),
          j.difference.toStringAsFixed(2),
        ]),
      ];
      await ExportHelper.exportToExcel(data: rows, filename: 'manual_journals_${DateFormat('yyyyMMdd').format(DateTime.now())}');
      _showSuccess('✅ Exported ${all.journals.length} journals');
    } catch (e) { _showError('Export failed: $e'); }
  }

  // ── import ────────────────────────────────────────────────────────────────

  void _handleImport() {
    showDialog(context: context, builder: (_) => _ImportDialog(onImported: () => _load(resetPage: true)));
  }

  // ── process flow dialog ───────────────────────────────────────────────────

  void _showViewProcess() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(children: [
          Center(child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85, maxHeight: MediaQuery.of(context).size.height * 0.85),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(color: _navy,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12))),
                  child: const Text('Journal Process Flow',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ),
                Expanded(child: Container(
                  width: double.infinity, padding: const EdgeInsets.all(16),
                  child: InteractiveViewer(
                    panEnabled: true, minScale: 0.5, maxScale: 4.0,
                    child: Center(child: Image.asset('assets/manual_journals.png', fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => _buildProcessFallback())),
                  ),
                )),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.grey[100],
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
                  child: Text('Tip: Pinch to zoom, drag to pan', style: TextStyle(color: Colors.grey[600], fontSize: 13), textAlign: TextAlign.center),
                ),
              ]),
            ),
          )),
          Positioned(top: 40, right: 40, child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 32),
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(backgroundColor: Colors.black.withOpacity(0.6), padding: const EdgeInsets.all(14)),
          )),
        ]),
      ),
    );
  }

  Widget _buildProcessFallback() {
    final steps = [
      ('Create Journal', 'Fill journal number, date, reference & line items', Icons.create, _blue),
      ('Add Line Items', 'Debit = Credit (Difference must be ₹0.00)', Icons.list_alt, _orange),
      ('Save as Draft', 'Review and edit anytime while in Draft', Icons.save_outlined, _purple),
      ('Publish', 'Posts all entries to Chart of Accounts', Icons.publish, _green),
      ('COA Updated', 'Account balances reflect in General Ledger', Icons.account_balance, _teal),
      ('Void / Clone / PDF', 'Reverse entries, clone or download PDF', Icons.more_horiz, _red),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(children: steps.asMap().entries.map((e) {
        final idx = e.key; final s = e.value;
        return Column(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: s.$4.withOpacity(0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: s.$4.withOpacity(0.3))),
            child: Row(children: [
              CircleAvatar(backgroundColor: s.$4, radius: 20, child: Icon(s.$3, color: Colors.white, size: 18)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.$1, style: TextStyle(fontWeight: FontWeight.bold, color: s.$4, fontSize: 14)),
                const SizedBox(height: 3),
                Text(s.$2, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
              ])),
            ]),
          ),
          if (idx < steps.length - 1)
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Icon(Icons.arrow_downward, color: Colors.grey[400])),
        ]);
      }).toList()),
    );
  }

  // ── date pickers ──────────────────────────────────────────────────────────

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? now) : (_toDate ?? now),
      firstDate: DateTime(2020), lastDate: DateTime(2030),
      builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: _navy)), child: child!),
    );
    if (picked != null) {
      setState(() { isFrom ? _fromDate = picked : _toDate = picked; });
      _load(resetPage: true);
    }
  }

  // ── snackbars ─────────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.check_circle, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _green, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [const Icon(Icons.error_outline, color: Colors.white, size: 18), const SizedBox(width: 8), Expanded(child: Text(msg))]),
      backgroundColor: _red, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<bool?> _confirmDialog({required String title, required String message, required String confirmLabel, Color confirmColor = _navy}) =>
      showDialog<bool>(context: context, builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: confirmColor, foregroundColor: Colors.white),
              child: Text(confirmLabel)),
        ],
      ));

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Manual Journals'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(children: [
          _buildTopBar(),
          _buildStatsCards(),
          _isLoading
              ? const SizedBox(height: 400, child: Center(child: CircularProgressIndicator(color: _navy)))
              : _error != null
                  ? SizedBox(height: 400, child: _buildErrorState())
                  : _journals.isEmpty
                      ? SizedBox(height: 400, child: _buildEmptyState())
                      : _buildTable(),
          if (!_isLoading && _journals.isNotEmpty) _buildPagination(),
        ]),
      ),
    );
  }

  // ── top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white,
          border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))]),
      child: LayoutBuilder(builder: (_, c) {
        if (c.maxWidth >= 1100) return _topBarDesktop();
        if (c.maxWidth >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  Widget _topBarDesktop() => Row(children: [
    _statusDropdown(),
    const SizedBox(width: 12),
    _searchField(width: 220),
    const SizedBox(width: 10),
    _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: () => _pickDate(true)),
    const SizedBox(width: 8),
    _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: () => _pickDate(false)),
    if (_fromDate != null || _toDate != null) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _load(resetPage: true); }, tooltip: 'Clear Dates', color: _red, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
    const SizedBox(width: 6),
    _iconBtn(Icons.account_tree, _showViewProcess, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
    const Spacer(),
    _actionBtn('New Journal', Icons.add_rounded, _navy, _openNew),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _green, _journals.isEmpty ? null : _export),
    const SizedBox(width: 8),
    _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange, () => _raiseTicket()),
  ]);

  Widget _topBarTablet() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 10),
      _searchField(width: 190),
      const SizedBox(width: 8),
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From', isActive: _fromDate != null, onTap: () => _pickDate(true)),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To', isActive: _toDate != null, onTap: () => _pickDate(false)),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _load(resetPage: true); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree, _showViewProcess, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      _actionBtn('New Journal', Icons.add_rounded, _navy, _openNew),
      const SizedBox(width: 8),
      _actionBtn('Import', Icons.upload_file_rounded, _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 8),
      _actionBtn('Export', Icons.download_rounded, _green, _journals.isEmpty ? null : _export),
      const SizedBox(width: 8),
      _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange, () => _raiseTicket()),
    ]),
  ]);

  Widget _topBarMobile() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _statusDropdown(),
      const SizedBox(width: 8),
      Expanded(child: _searchField(width: double.infinity)),
      const SizedBox(width: 8),
      _actionBtn('New', Icons.add_rounded, _navy, _openNew),
    ]),
    const SizedBox(height: 10),
    SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _dateChip(label: _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date', isActive: _fromDate != null, onTap: () => _pickDate(true)),
      const SizedBox(width: 6),
      _dateChip(label: _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date', isActive: _toDate != null, onTap: () => _pickDate(false)),
      if (_fromDate != null || _toDate != null) ...[
        const SizedBox(width: 6),
        _iconBtn(Icons.close, () { setState(() { _fromDate = null; _toDate = null; }); _load(resetPage: true); }, color: _red, bg: Colors.red[50]!),
      ],
      const SizedBox(width: 6),
      _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refresh, tooltip: 'Refresh'),
      const SizedBox(width: 6),
      _iconBtn(Icons.account_tree, _showViewProcess, tooltip: 'View Process', color: _navy, bg: _navy.withOpacity(0.08)),
      const SizedBox(width: 6),
      _compactBtn('Import', _purple, _isLoading ? null : _handleImport),
      const SizedBox(width: 6),
      _compactBtn('Export', _green, _journals.isEmpty ? null : _export),
      const SizedBox(width: 6),
      _compactBtn('Ticket', _orange, () => _raiseTicket()),
    ])),
  ]);

  // ── reusable widgets ──────────────────────────────────────────────────────

  Widget _statusDropdown() => Container(
    height: 44, padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF7F9FC), border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _statusFilter,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
        items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s == 'All' ? 'All Journals' : s))).toList(),
        onChanged: (v) { if (v != null) { setState(() => _statusFilter = v); _load(resetPage: true); } },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchCtrl,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search journal #, notes, reference…',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () { _searchCtrl.clear(); })
            : null,
        filled: true, fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 0), isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
    );
    if (width == double.infinity) return field;
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _dateChip({required String label, required bool isActive, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 42, padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? _navy.withOpacity(0.08) : const Color(0xFFF7F9FC),
          border: Border.all(color: isActive ? _navy : const Color(0xFFDDE3EE)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today, size: 15, color: isActive ? _navy : Colors.grey[500]),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal, color: isActive ? _navy : Colors.grey[600])),
        ]),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {String tooltip = '', Color color = const Color(0xFF7F8C8D), Color bg = const Color(0xFFF1F1F1)}) {
    return Tooltip(message: tooltip, child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Container(width: 42, height: 42,
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.25))),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.grey[300] : color)),
    ));
  }

  Widget _actionBtn(String label, IconData icon, Color bg, VoidCallback? onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0, minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _compactBtn(String label, Color bg, VoidCallback? onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg, foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0, minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }

  // ── stats cards ───────────────────────────────────────────────────────────

  Widget _buildStatsCards() {
    final cards = [
      _StatCardData(label: 'Total',        value: (_stats?.total     ?? 0).toString(),              icon: Icons.book_outlined,             color: _navy,   gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)]),
      _StatCardData(label: 'Draft',        value: (_stats?.draft     ?? 0).toString(),              icon: Icons.edit_note,                 color: _orange, gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)]),
      _StatCardData(label: 'Published',    value: (_stats?.published ?? 0).toString(),              icon: Icons.publish,                   color: _green,  gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)]),
      _StatCardData(label: 'Void',         value: (_stats?.voided    ?? 0).toString(),              icon: Icons.cancel_outlined,           color: _red,    gradientColors: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)]),
      _StatCardData(label: 'Total Debit',  value: '₹${_fmtAmt(_stats?.totalDebit  ?? 0)}',         icon: Icons.arrow_upward,              color: const Color(0xFFC0392B), gradientColors: const [Color(0xFFE74C3C), Color(0xFFC0392B)]),
      _StatCardData(label: 'Total Credit', value: '₹${_fmtAmt(_stats?.totalCredit ?? 0)}',         icon: Icons.arrow_downward,            color: _teal,   gradientColors: const [Color(0xFF1ABC9C), Color(0xFF16A085)]),
    ];

    return Container(
      width: double.infinity, color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, c) {
        final isMobile = c.maxWidth < 700;
        if (isMobile) {
          return SingleChildScrollView(
            controller: _statsHScrollCtrl, scrollDirection: Axis.horizontal,
            child: Row(children: cards.asMap().entries.map((e) => Container(
              width: 160, margin: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0),
              child: _buildStatCard(e.value, compact: true),
            )).toList()),
          );
        }
        return Row(children: cards.asMap().entries.map((e) => Expanded(
          child: Padding(padding: EdgeInsets.only(right: e.key < cards.length - 1 ? 10 : 0), child: _buildStatCard(e.value, compact: false)),
        )).toList());
      }),
    );
  }

  String _fmtAmt(double v) {
    if (v >= 10000000) return '${(v / 10000000).toStringAsFixed(1)}Cr';
    if (v >= 100000)   return '${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000)     return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  Widget _buildStatCard(_StatCardData d, {required bool compact}) {
    return Container(
      padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [d.gradientColors[0].withOpacity(0.15), d.gradientColors[1].withOpacity(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withOpacity(0.22)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: compact
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(10)),
                  child: Icon(d.icon, color: Colors.white, size: 20)),
              const SizedBox(height: 10),
              Text(d.label, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(d.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: d.color)),
            ])
          : Row(children: [
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: d.gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: d.color.withOpacity(0.30), blurRadius: 8, offset: const Offset(0, 3))]),
                  child: Icon(d.icon, color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.label, style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 5),
                Text(d.value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: d.color)),
              ])),
            ]),
    );
  }

  // ── table ─────────────────────────────────────────────────────────────────

  Widget _buildTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))]),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScrollCtrl, thumbVisibility: true, trackVisibility: true, thickness: 8, radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.trackpad}),
            child: SingleChildScrollView(
              controller: _tableHScrollCtrl, scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.4),
                  headingRowHeight: 52, dataRowMinHeight: 60, dataRowMaxHeight: 76,
                  dataTextStyle: const TextStyle(fontSize: 13),
                  dataRowColor: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1, columnSpacing: 16, horizontalMargin: 14,
                  columns: const [
                    DataColumn(label: SizedBox(width: 130, child: Text('JOURNAL #'))),
                    DataColumn(label: SizedBox(width: 100, child: Text('DATE'))),
                    DataColumn(label: SizedBox(width: 110, child: Text('REFERENCE #'))),
                    DataColumn(label: SizedBox(width: 180, child: Text('NOTES'))),
                    DataColumn(label: SizedBox(width: 100, child: Text('STATUS'))),
                    DataColumn(label: SizedBox(width: 110, child: Text('DEBIT (₹)')),  numeric: true),
                    DataColumn(label: SizedBox(width: 110, child: Text('CREDIT (₹)')), numeric: true),
                    DataColumn(label: SizedBox(width: 180, child: Text('ACTIONS'))),
                  ],
                  rows: _journals.asMap().entries.map((e) => _buildRow(e.key, e.value)).toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildRow(int idx, ManualJournal j) {
    return DataRow(
      color: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.hovered)) return _navy.withOpacity(0.04);
        return idx % 2 == 0 ? Colors.white : Colors.grey[50];
      }),
      cells: [
        // Journal #
        DataCell(SizedBox(width: 130, child: InkWell(
          onTap: () => _openDetail(j),
          child: Text(j.journalNumber, style: const TextStyle(color: _navy, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.underline)),
        ))),

        // Date
        DataCell(SizedBox(width: 100, child: Text(DateFormat('dd MMM yyyy').format(j.date), style: const TextStyle(fontSize: 12)))),

        // Reference #
        DataCell(SizedBox(width: 110, child: Text(j.referenceNumber.isEmpty ? '-' : j.referenceNumber, style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis))),

        // Notes
        DataCell(SizedBox(width: 180, child: Text(j.notes.isEmpty ? '-' : j.notes, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)))),

        // Status
        DataCell(SizedBox(width: 100, child: _statusBadge(j.status))),

        // Debit
        DataCell(SizedBox(width: 110, child: Text('₹${j.totalDebit.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red[700]), textAlign: TextAlign.right))),

        // Credit
        DataCell(SizedBox(width: 110, child: Text('₹${j.totalCredit.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green[700]), textAlign: TextAlign.right))),

        // Actions
        DataCell(SizedBox(width: 180, child: Row(children: [
          // Share
          Tooltip(message: 'Share', child: InkWell(
            onTap: () => _share(j),
            child: Container(width: 30, height: 30, decoration: BoxDecoration(color: _blue.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.share, size: 15, color: _blue)),
          )),
          const SizedBox(width: 4),
          // WhatsApp
          Tooltip(message: 'WhatsApp', child: InkWell(
            onTap: () => _whatsApp(j),
            child: Container(width: 30, height: 30, decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.chat, size: 15, color: Color(0xFF25D366))),
          )),
          const SizedBox(width: 4),
          // View
          Tooltip(message: 'View', child: InkWell(
            onTap: () => _openDetail(j),
            child: Container(width: 30, height: 30, decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(7)),
                child: const Icon(Icons.visibility_outlined, size: 15, color: _navy)),
          )),
          if (j.status == 'Draft') ...[
            const SizedBox(width: 4),
            // Edit
            Tooltip(message: 'Edit', child: InkWell(
              onTap: () => _openEdit(j),
              child: Container(width: 30, height: 30, decoration: BoxDecoration(color: _orange.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                  child: const Icon(Icons.edit_outlined, size: 15, color: _orange)),
            )),
            const SizedBox(width: 4),
            // Publish
            Tooltip(message: 'Publish', child: InkWell(
              onTap: () => _quickPublish(j),
              child: Container(width: 30, height: 30, decoration: BoxDecoration(color: _green.withOpacity(0.10), borderRadius: BorderRadius.circular(7)),
                  child: const Icon(Icons.publish, size: 15, color: _green)),
            )),
          ],
          const SizedBox(width: 4),
          // More
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            itemBuilder: (_) => [
              _menuItem('clone',  Icons.copy_outlined,                 _blue,   'Clone'),
              _menuItem('pdf',    Icons.download_outlined,             _navy,   'Download PDF'),
              if (j.status != 'Void')
                _menuItem('void',   Icons.block_outlined,             _orange, 'Void', textColor: _orange),
              _menuItem('ticket', Icons.confirmation_number_outlined,  _orange, 'Raise Ticket'),
              if (j.status == 'Draft')
                _menuItem('delete', Icons.delete_outline,             _red,    'Delete', textColor: _red),
            ],
            onSelected: (v) {
              switch (v) {
                case 'clone':  _clone(j);         break;
                case 'pdf':    _downloadPDF(j);   break;
                case 'void':   _void(j);          break;
                case 'ticket': _raiseTicket(j);   break;
                case 'delete': _delete(j);        break;
              }
            },
          ),
        ]))),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, Color iconColor, String label, {Color? textColor}) {
    return PopupMenuItem(value: value, child: ListTile(
      leading: Icon(icon, size: 17, color: iconColor),
      title: Text(label, style: TextStyle(color: textColor, fontSize: 13)),
      contentPadding: EdgeInsets.zero, dense: true,
    ));
  }

  Widget _statusBadge(String status) {
    const map = <String, List<Color>>{
      'Draft':     [Color(0xFFFEF3C7), Color(0xFFB45309)],
      'Published': [Color(0xFFDCFCE7), Color(0xFF15803D)],
      'Void':      [Color(0xFFFEE2E2), Color(0xFFDC2626)],
    };
    final c = map[status] ?? [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c[0], borderRadius: BorderRadius.circular(20), border: Border.all(color: c[1].withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status, style: TextStyle(color: c[1], fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }

  // ── pagination ────────────────────────────────────────────────────────────

  Widget _buildPagination() {
    List<int> pages;
    if (_totalPages <= 5) {
      pages = List.generate(_totalPages, (i) => i + 1);
    } else {
      final start = (_page - 2).clamp(1, _totalPages - 4);
      pages = List.generate(5, (i) => start + i);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 8,
        children: [
          Text('Showing ${(_page - 1) * 50 + 1}–${(_page * 50).clamp(0, _total)} of $_total journals',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _pageNavBtn(icon: Icons.chevron_left,  enabled: _page > 1,           onTap: () { setState(() => _page--); _load(); }),
            const SizedBox(width: 4),
            if (pages.first > 1) ...[_pageNumBtn(1), if (pages.first > 2) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400])))],
            ...pages.map((p) => _pageNumBtn(p)),
            if (pages.last < _totalPages) ...[if (pages.last < _totalPages - 1) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text('…', style: TextStyle(color: Colors.grey[400]))), _pageNumBtn(_totalPages)],
            const SizedBox(width: 4),
            _pageNavBtn(icon: Icons.chevron_right, enabled: _page < _totalPages, onTap: () { setState(() => _page++); _load(); }),
          ]),
        ],
      ),
    );
  }

  Widget _pageNumBtn(int page) {
    final isActive = _page == page;
    return GestureDetector(
      onTap: () { if (!isActive) { setState(() => _page = page); _load(); } },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2), width: 34, height: 34,
        decoration: BoxDecoration(color: isActive ? _navy : Colors.transparent, borderRadius: BorderRadius.circular(8), border: Border.all(color: isActive ? _navy : Colors.grey[300]!)),
        child: Center(child: Text('$page', style: TextStyle(fontSize: 13, fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.white : Colors.grey[700]))),
      ),
    );
  }

  Widget _pageNavBtn({required IconData icon, required bool enabled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(width: 34, height: 34,
          decoration: BoxDecoration(color: enabled ? Colors.white : Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[300]!)),
          child: Icon(icon, size: 18, color: enabled ? _navy : Colors.grey[300])),
    );
  }

  // ── empty / error ─────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: _navy.withOpacity(0.06), shape: BoxShape.circle),
          child: Icon(Icons.book_outlined, size: 64, color: _navy.withOpacity(0.4))),
      const SizedBox(height: 20),
      const Text('No Journals Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A202C))),
      const SizedBox(height: 8),
      Text('Create your first manual journal to get started', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
      const SizedBox(height: 28),
      ElevatedButton.icon(onPressed: _openNew, icon: const Icon(Icons.add),
          label: const Text('New Journal', style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ])));
  }

  Widget _buildErrorState() {
    return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
          child: Icon(Icons.error_outline, size: 56, color: Colors.red[400])),
      const SizedBox(height: 20),
      const Text('Failed to Load Journals', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_error ?? 'Unknown error', style: TextStyle(color: Colors.grey[500]), textAlign: TextAlign.center)),
      const SizedBox(height: 28),
      ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh),
          label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
    ])));
  }
}

// =============================================================================
//  RAISE TICKET OVERLAY
// =============================================================================

class _RaiseTicketOverlay extends StatefulWidget {
  final ManualJournal? journal;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;
  const _RaiseTicketOverlay({this.journal, required this.onTicketRaised, required this.onError});

  @override
  State<_RaiseTicketOverlay> createState() => _RaiseTicketOverlayState();
}

class _RaiseTicketOverlayState extends State<_RaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filtered  = [];
  Map<String, dynamic>?       _selectedEmp;
  bool _loading   = true;
  bool _assigning = false;
  String _priority = 'Medium';

  @override
  void initState() { super.initState(); _loadEmployees(); _searchCtrl.addListener(_filter); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _loadEmployees() async {
    final resp = await _tmsService.fetchEmployees();
    if (resp['success'] == true && resp['data'] != null) {
      setState(() { _employees = List<Map<String, dynamic>>.from(resp['data']); _filtered = _employees; _loading = false; });
    } else {
      setState(() => _loading = false);
      widget.onError('Failed to load employees');
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() { _filtered = q.isEmpty ? _employees : _employees.where((e) =>
        (e['name_parson'] ?? '').toLowerCase().contains(q) || (e['email'] ?? '').toLowerCase().contains(q) || (e['role'] ?? '').toLowerCase().contains(q)).toList(); });
  }

  String _buildMessage() {
    if (widget.journal == null) return 'A ticket has been raised regarding a manual journal and requires your attention.';
    final j = widget.journal!;
    return 'Manual Journal "${j.journalNumber}" requires attention.\n\n'
        'Journal Details:\n'
        '• Journal # : ${j.journalNumber}\n'
        '• Date      : ${DateFormat('dd MMM yyyy').format(j.date)}\n'
        '${j.referenceNumber.isNotEmpty ? '• Reference : ${j.referenceNumber}\n' : ''}'
        '${j.notes.isNotEmpty ? '• Notes     : ${j.notes}\n' : ''}'
        '• Status    : ${j.status}\n'
        '• Debit     : ₹${j.totalDebit.toStringAsFixed(2)}\n'
        '• Credit    : ₹${j.totalCredit.toStringAsFixed(2)}\n'
        '• Difference: ₹${j.difference.toStringAsFixed(2)}\n\n'
        'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject:    widget.journal != null ? 'Manual Journal: ${widget.journal!.journalNumber}' : 'Manual Journals — Action Required',
        message:    _buildMessage(),
        priority:   _priority,
        timeline:   1440,
        assignedTo: _selectedEmp!['_id'].toString(),
      );
      setState(() => _assigning = false);
      if (resp['success'] == true) {
        widget.onTicketRaised('Ticket assigned to ${_selectedEmp!['name_parson']}');
        if (mounted) Navigator.pop(context);
      } else { widget.onError(resp['message'] ?? 'Failed to create ticket'); }
    } catch (e) { setState(() => _assigning = false); widget.onError('Failed: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        width: 520,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.80),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.confirmation_number_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Raise a Ticket', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                if (widget.journal != null) Text('Journal: ${widget.journal!.journalNumber}',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12), overflow: TextOverflow.ellipsis),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          // Body
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.journal != null) ...[
              const Text('Auto-generated message', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
              const SizedBox(height: 8),
              Container(padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFF0F4F8), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDDE3EE))),
                  child: Text(_buildMessage(), style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5))),
              const SizedBox(height: 20),
            ],
            const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
            const SizedBox(height: 8),
            Row(children: ['Low','Medium','High'].map((pr) {
              final isSel = _priority == pr;
              final color = pr == 'High' ? _red : pr == 'Medium' ? _orange : _green;
              return Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: InkWell(
                onTap: () => setState(() => _priority = pr), borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: isSel ? color : Colors.white, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isSel ? color : Colors.grey[300]!),
                        boxShadow: isSel ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : []),
                    child: Center(child: Text(pr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSel ? Colors.white : Colors.grey[700])))),
              )));
            }).toList()),
            const SizedBox(height: 20),
            const Text('Assign To', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _navy)),
            const SizedBox(height: 8),
            TextField(controller: _searchCtrl, decoration: InputDecoration(
              hintText: 'Search employees…', prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
              filled: true, fillColor: const Color(0xFFF7F9FC), contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _navy, width: 1.5)),
            )),
            const SizedBox(height: 8),
            _loading
                ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _navy)))
                : _filtered.isEmpty
                    ? Container(height: 80, alignment: Alignment.center, child: Text('No employees found', style: TextStyle(color: Colors.grey[500])))
                    : Container(
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDE3EE)), borderRadius: BorderRadius.circular(10)),
                        child: ListView.separated(
                          shrinkWrap: true, itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEF2F7)),
                          itemBuilder: (_, i) {
                            final emp = _filtered[i]; final isSel = _selectedEmp?['_id'] == emp['_id'];
                            return InkWell(
                              onTap: () => setState(() => _selectedEmp = isSel ? null : emp),
                              child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  color: isSel ? _navy.withOpacity(0.06) : Colors.transparent,
                                  child: Row(children: [
                                    CircleAvatar(radius: 18, backgroundColor: isSel ? _navy : _navy.withOpacity(0.10),
                                        child: Text((emp['name_parson'] ?? 'U')[0].toUpperCase(), style: TextStyle(color: isSel ? Colors.white : _navy, fontWeight: FontWeight.bold, fontSize: 13))),
                                    const SizedBox(width: 12),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(emp['name_parson'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                      if (emp['email'] != null) Text(emp['email'], style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                                      if (emp['role'] != null) Container(margin: const EdgeInsets.only(top: 3), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
                                          child: Text(emp['role'].toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _navy))),
                                    ])),
                                    if (isSel) const Icon(Icons.check_circle, color: _navy, size: 20),
                                  ])),
                            );
                          },
                        )),
          ]))),
          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Color(0xFFF7F9FC), border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.grey[700], side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)))),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: (_selectedEmp == null || _assigning) ? null : _assign,
                style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, disabledBackgroundColor: _navy.withOpacity(0.4), elevation: 0, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: _assigning
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_selectedEmp != null ? 'Assign to ${_selectedEmp!['name_parson'] ?? ''}' : 'Select Employee', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              )),
            ]),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
//  IMPORT DIALOG — 2-step: download template + upload file
// =============================================================================

class _ImportDialog extends StatefulWidget {
  final VoidCallback onImported;
  const _ImportDialog({required this.onImported});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool _downloading = false;
  bool _uploading   = false;
  String? _fileName;
  Map<String, dynamic>? _results;

  Future<void> _downloadTemplate() async {
    setState(() => _downloading = true);
    try {
      final data = <List<dynamic>>[
        ['journalNumber','date (YYYY-MM-DD)','referenceNumber','notes','reportingMethod','currency','status',
         'lineItem_accountName','lineItem_description','lineItem_contactName','lineItem_debit','lineItem_credit'],
        ['JNL-2025-001','2025-01-15','REF-001','Opening entry','Accrual and Cash','INR','Draft',
         'Cash','Opening balance','','50000','0'],
        ['','','','','','','',
         'Opening Balance Offset','Opening balance offset','','0','50000'],
        ['INSTRUCTIONS:','1. One row per line item. Repeat journal fields only on first line item row.',
         '2. Debit must equal Credit per journal.','3. Date format: YYYY-MM-DD',
         '4. Status: Draft or Published','5. reportingMethod: Accrual and Cash / Cash / Accrual',
         '6. currency: INR','7. Delete this row before uploading'],
      ];
      await ExportHelper.exportToExcel(data: data, filename: 'manual_journals_import_template');
      setState(() => _downloading = false);
      _snack('Template downloaded!', _green);
    } catch (e) {
      setState(() => _downloading = false);
      _snack('Download failed: $e', _red);
    }
  }

  Future<void> _uploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      if (file.bytes == null) { _snack('Could not read file', _red); return; }
      setState(() { _fileName = file.name; _uploading = true; _results = null; });

      final resp = await ManualJournalService.importJournals(
        [],
        file.bytes!,
        file.name,
      );

      setState(() {
        _uploading = false;
        _results = {
          'imported': resp['data']?['imported'] ?? resp['data']?['successCount'] ?? 0,
          'failed':   resp['data']?['failed']   ?? resp['data']?['failedCount']  ?? 0,
          'total':    resp['data']?['total']     ?? resp['data']?['totalProcessed'] ?? 0,
          'errors':   resp['data']?['errors']    ?? [],
        };
      });
      _snack('✅ Import completed!', _green);
      widget.onImported();
    } catch (e) {
      setState(() { _uploading = false; _fileName = null; });
      _snack('Import failed: $e', _red);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width > 600
            ? 560
            : MediaQuery.of(context).size.width * 0.92, padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: _purple.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.upload_file_rounded, color: _purple, size: 24)),
            const SizedBox(width: 14),
            const Text('Import Manual Journals', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue[200]!)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.info_outline, color: Colors.blue[700], size: 18), const SizedBox(width: 8), Text('Import Format', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[700]))]),
              const SizedBox(height: 8),
              const Text('• One row per line item\n• Repeat journal fields only on the first line item row\n• Debit must equal Credit per journal\n• Date format: YYYY-MM-DD\n• Accepted: .xlsx, .xls, .csv', style: TextStyle(fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 20),
          _importStep(step: '1', color: _blue, icon: Icons.download_rounded, title: 'Download Template',
              subtitle: 'Get the Excel template with correct column headers and example rows.',
              buttonLabel: _downloading ? 'Downloading…' : 'Download Template',
              onPressed: _downloading || _uploading ? null : _downloadTemplate),
          const SizedBox(height: 14),
          _importStep(step: '2', color: _green, icon: Icons.upload_rounded, title: 'Upload Filled File',
              subtitle: 'Fill in the template and upload your file (XLSX / XLS / CSV).',
              buttonLabel: _uploading ? 'Processing…' : (_fileName != null ? 'Change File' : 'Select File'),
              onPressed: _downloading || _uploading ? null : _uploadFile),
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green[200]!)),
              child: Row(children: [Icon(Icons.check_circle, color: Colors.green[700], size: 18), const SizedBox(width: 8), Expanded(child: Text(_fileName!, style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)))]),
            ),
          ],
          if (_results != null) ...[
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey[200]!)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Import Results', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 10),
                _resultRow('Total Processed',      '${_results!['total']}',    _blue),
                const SizedBox(height: 6),
                _resultRow('Successfully Imported', '${_results!['imported']}', _green),
                const SizedBox(height: 6),
                _resultRow('Failed',                '${_results!['failed']}',   _red),
                if ((_results!['errors'] as List).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Errors:', style: TextStyle(fontWeight: FontWeight.w600, color: _red, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(constraints: const BoxConstraints(maxHeight: 100), child: SingleChildScrollView(
                      child: Text((_results!['errors'] as List).join('\n'), style: const TextStyle(fontSize: 11, color: _red)))),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _navy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.w600)),
            )),
          ],
        ]),
      ),
    );
  }

  Widget _importStep({required String step, required Color color, required IconData icon, required String title, required String subtitle, required String buttonLabel, required VoidCallback? onPressed}) {
    final circle = Container(width: 34, height: 34, decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Center(child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))));
    final textBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 3),
      Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]);
    final button = ElevatedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 15), label: Text(buttonLabel, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, disabledBackgroundColor: color.withOpacity(0.5), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.25))),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [circle, const SizedBox(width: 10), Expanded(child: textBlock)]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: button),
          ]);
        }
        return Row(children: [circle, const SizedBox(width: 14), Expanded(child: textBlock), const SizedBox(width: 10), button]);
      }),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
    ]);
  }
}