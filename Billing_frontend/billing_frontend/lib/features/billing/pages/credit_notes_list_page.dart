// ============================================================================
// CREDIT NOTES LIST PAGE - Fully Responsive UI
// ============================================================================
// File: lib/features/admin/Billing/pages/credit_notes_list_page.dart
// Features:
// ✅ 3-breakpoint responsive top bar (Mobile / Tablet / Desktop)
//    • Mobile  (<700px) : Row1: dropdown+search+New (single row) | Row2: scrollable btns
//    • Tablet  (700-1100px): Row1: dropdown+search+filter+refresh | Row2: action btns
//    • Desktop (≥1100px): single row, Spacer pushes actions to far right
// ✅ Stats cards: always 4 in ONE row
//    • Desktop: Expanded — fills full width
//    • Mobile : horizontally scrollable, each card fixed 160px min-width
// ✅ Gradient stat cards (navy → color per card)
// ✅ Table: horizontal drag-to-scroll, cursor scrollbar
// ✅ Import dialog (download template → upload CSV)
// ✅ Export to CSV
// ✅ Date range filters
// ✅ Refresh, View/Edit/Delete, PDF download, Email send
// ✅ Pagination with ellipsis
// ✅ Empty state & Error state
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:universal_html/html.dart' as html;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/services/credit_note_service.dart';
import '../../../../core/services/tms_service.dart';
import '../app_top_bar.dart';
import 'new_credit_note.dart';
import 'credit_note_detail_page.dart';

// ── Stat card data model ──────────────────────────────────────────────────────
class _StatCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final List<Color> gradientColors;

  const _StatCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.gradientColors,
  });
}

// =============================================================================
class CreditNotesListPage extends StatefulWidget {
  const CreditNotesListPage({Key? key}) : super(key: key);

  @override
  State<CreditNotesListPage> createState() => _CreditNotesListPageState();
}

class _CreditNotesListPageState extends State<CreditNotesListPage> {
  // ── Brand palette ──────────────────────────────────────────────────────────
  static const Color _navy    = Color(0xFF1e3a8a);
  static const Color _purple  = Color(0xFF9B59B6);
  static const Color _green   = Color(0xFF27AE60);
  static const Color _blue    = Color(0xFF2980B9);
  static const Color _orange  = Color(0xFFE67E22);

  // ── Data ───────────────────────────────────────────────────────────────────
  List<CreditNote> _creditNotes = [];
  CreditNoteStats? _stats;
  bool _isLoading = true;
  String? _errorMessage;

  // ── Filters ────────────────────────────────────────────────────────────────
  String _selectedStatus = 'All';
  final List<String> _statusFilters = [
    'All', 'DRAFT', 'OPEN', 'CLOSED', 'REFUNDED', 'VOID',
  ];
  DateTime? _fromDate;
  DateTime? _toDate;

  // ── Pagination ─────────────────────────────────────────────────────────────
  int _currentPage  = 1;
  int _totalPages   = 1;
  int _totalCreditNotes = 0;
  final int _itemsPerPage = 20;

  // ── Selection ──────────────────────────────────────────────────────────────
  final Set<String> _selectedCreditNotes = {};
  bool _selectAll = false;

  // ── Search ─────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Scroll ─────────────────────────────────────────────────────────────────
  final ScrollController _tableHScrollCtrl = ScrollController();
  final ScrollController _statsHScrollCtrl = ScrollController();

  // ==========================================================================
  @override
  void initState() {
    super.initState();
    _loadCreditNotes();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tableHScrollCtrl.dispose();
    _statsHScrollCtrl.dispose();
    super.dispose();
  }

  // ==========================================================================
  //  DATA
  // ==========================================================================

  Future<void> _loadCreditNotes() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final response = await CreditNoteService.getCreditNotes(
        status:   _selectedStatus == 'All' ? null : _selectedStatus,
        page:     _currentPage,
        limit:    _itemsPerPage,
        search:   _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate: _fromDate,
        toDate:   _toDate,
      );
      setState(() {
        _creditNotes      = response.creditNotes;
        _totalPages       = response.pagination.pages;
        _totalCreditNotes = response.pagination.total;
        _isLoading        = false;
      });
    } catch (e) {
      setState(() { _errorMessage = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await CreditNoteService.getStats();
      setState(() => _stats = stats);
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  Future<void> _refreshData() async {
    _currentPage = 1;
    await Future.wait([_loadCreditNotes(), _loadStats()]);
    _snackSuccess('Data refreshed successfully');
  }

  void _filterByStatus(String status) {
    setState(() { _selectedStatus = status; _currentPage = 1; });
    _loadCreditNotes();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedCreditNotes.contains(id)) {
        _selectedCreditNotes.remove(id);
      } else {
        _selectedCreditNotes.add(id);
      }
      _selectAll = _selectedCreditNotes.length == _creditNotes.length;
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedCreditNotes.addAll(_creditNotes.map((cn) => cn.id));
      } else {
        _selectedCreditNotes.clear();
      }
    });
  }

  // ==========================================================================
  //  NAVIGATION
  // ==========================================================================

  void _openNewCreditNote() async {
    final result = await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const NewCreditNoteScreen()));
    if (result == true) _refreshData();
  }

  void _openEditCreditNote(String creditNoteId) async {
    final result = await Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => NewCreditNoteScreen(creditNoteId: creditNoteId)));
    if (result == true) _refreshData();
  }

  // ==========================================================================
  //  ACTIONS
  // ==========================================================================

  Future<void> _deleteCreditNote(CreditNote cn) async {
    if (cn.status != 'DRAFT') {
      _snackError('Only draft credit notes can be deleted');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Credit Note',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            'Delete credit note ${cn.creditNoteNumber}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await CreditNoteService.deleteCreditNote(cn.id);
        _snackSuccess('Credit note deleted successfully');
        _refreshData();
      } catch (e) {
        _snackError('Failed to delete: $e');
      }
    }
  }

  Future<void> _sendCreditNote(CreditNote cn) async {
    try {
      await CreditNoteService.sendCreditNote(cn.id);
      _snackSuccess('Credit note sent to ${cn.customerEmail}');
      _refreshData();
    } catch (e) {
      _snackError('Failed to send credit note: $e');
    }
  }

  Future<void> _downloadCreditNotePDF(CreditNote cn) async {
    try {
      _snackSuccess('Preparing PDF download...');
      final pdfUrl = await CreditNoteService.downloadPDF(cn.id);
      if (kIsWeb) {
        html.AnchorElement(href: pdfUrl)
          ..setAttribute('download', '${cn.creditNoteNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
        _snackSuccess('✅ PDF download started for ${cn.creditNoteNumber}');
      } else {
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _snackSuccess('✅ PDF opened for ${cn.creditNoteNumber}');
        } else {
          throw 'Could not launch PDF viewer';
        }
      }
    } catch (e) {
      _snackError('Failed to download PDF: $e');
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      final url = await CreditNoteService.downloadImportTemplate();
      if (kIsWeb) {
        html.AnchorElement(href: url)
          ..setAttribute('download', 'credit_notes_import_template.csv')
          ..click();
        _snackSuccess('✅ Template downloaded');
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      _snackError('Failed to download template: $e');
    }
  }

  Future<void> _selectAndImportFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: kIsWeb,
      );
      if (result != null && result.files.isNotEmpty) {
        _snackSuccess('Importing credit notes...');
        final importResult =
            await CreditNoteService.importCreditNotes(result.files.first);
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Import Complete',
                style: TextStyle(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '✅ Successfully imported: ${importResult.successCount}'),
                if (importResult.errorCount > 0)
                  Text('❌ Failed: ${importResult.errorCount}',
                      style: const TextStyle(color: Colors.red)),
                if (importResult.errors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Errors:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...importResult.errors.take(5).map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• Line ${e['line']}: ${e['error']}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red)),
                      )),
                ],
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _refreshData();
                  },
                  child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      _snackError('Import failed: $e');
    }
  }

  Future<void> _exportToCsv() async {
    try {
      _snackSuccess('Preparing export...');
      final url = await CreditNoteService.exportCreditNotes(
        status:   _selectedStatus == 'All' ? null : _selectedStatus,
        fromDate: _fromDate,
        toDate:   _toDate,
      );
      if (kIsWeb) {
        html.AnchorElement(href: url)
          ..setAttribute('download', 'credit_notes_export.csv')
          ..click();
        _snackSuccess('✅ Export downloaded');
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      _snackError('Export failed: $e');
    }
  }

  // ── Share ─────────────────────────────────────────────────────────────────
  // Works on both web (clipboard fallback) and mobile (native share sheet)

  Future<void> _shareCreditNote(CreditNote cn) async {
    final text =
        'Credit Note\n'
        '─────────────────────────\n'
        'Credit Note # : ${cn.creditNoteNumber}\n'
        'Customer      : ${cn.customerName}\n'
        'Email         : ${cn.customerEmail ?? '-'}\n'
        'Date          : ${DateFormat('dd MMM yyyy').format(cn.creditNoteDate)}\n'
        'Reason        : ${cn.reason}\n'
        'Status        : ${cn.status}\n'
        'Amount        : ₹${cn.totalAmount.toStringAsFixed(2)}\n'
        'Balance       : ₹${cn.creditBalance.toStringAsFixed(2)}';

    try {
      if (kIsWeb) {
        // Web: try navigator.share via share_plus, fallback to clipboard
        try {
          await Share.share(text, subject: 'Credit Note: ${cn.creditNoteNumber}');
        } catch (_) {
          await Clipboard.setData(ClipboardData(text: text));
          _snackSuccess('✅ Copied to clipboard');
        }
      } else {
        // Mobile: native share sheet
        await Share.share(text, subject: 'Credit Note: ${cn.creditNoteNumber}');
      }
    } catch (e) {
      _snackError('Share failed: $e');
    }
  }

  // ── WhatsApp ──────────────────────────────────────────────────────────────
  // Web  → opens wa.me link in browser tab
  // Mobile → opens WhatsApp app via whatsapp:// scheme with fallback to wa.me

  Future<void> _whatsAppCreditNote(CreditNote cn) async {
    // Silently get phone — never displayed in UI
    final rawPhone = cn.customerPhone ?? '';
    if (rawPhone.trim().isEmpty) {
      _snackError('Customer phone not available for this credit note');
      return;
    }

    // Strip non-digits
    String phone = rawPhone.replaceAll(RegExp(r'\D'), '');

    // Prepend country code 91 (India) if not already present
    if (!phone.startsWith('91') && phone.length == 10) {
      phone = '91$phone';
    }

    if (phone.isEmpty) {
      _snackError('Invalid phone number for WhatsApp');
      return;
    }

    final message = Uri.encodeComponent(
      'Hello ${cn.customerName},\n\n'
      'Please find the details of your Credit Note below:\n\n'
      'Credit Note # : ${cn.creditNoteNumber}\n'
      'Date          : ${DateFormat('dd MMM yyyy').format(cn.creditNoteDate)}\n'
      'Reason        : ${cn.reason}\n'
      'Amount        : ₹${cn.totalAmount.toStringAsFixed(2)}\n'
      'Balance       : ₹${cn.creditBalance.toStringAsFixed(2)}\n\n'
      'Please contact us for any queries.\nThank you!',
    );

    try {
      if (kIsWeb) {
        // Web: always use wa.me (WhatsApp Web)
        final uri = Uri.parse('https://wa.me/$phone?text=$message');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _snackError('Could not open WhatsApp Web');
        }
      } else {
        // Mobile: try native whatsapp:// scheme first, fallback to wa.me
        final nativeUri = Uri.parse('whatsapp://send?phone=$phone&text=$message');
        if (await canLaunchUrl(nativeUri)) {
          await launchUrl(nativeUri, mode: LaunchMode.externalApplication);
        } else {
          // WhatsApp not installed — open wa.me in browser
          final webUri = Uri.parse('https://wa.me/$phone?text=$message');
          if (await canLaunchUrl(webUri)) {
            await launchUrl(webUri, mode: LaunchMode.externalApplication);
          } else {
            _snackError('Could not open WhatsApp');
          }
        }
      }
    } catch (e) {
      _snackError('WhatsApp failed: $e');
    }
  }

  // ── Raise Ticket ──────────────────────────────────────────────────────────

  void _raiseTicket([CreditNote? cn]) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _CreditNoteRaiseTicketOverlay(
        creditNote: cn,
        onTicketRaised: (msg) => _snackSuccess(msg),
        onError: (msg) => _snackError(msg),
      ),
    );
  }

  // ── Import dialog ─────────────────────────────────────────────────────────

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width > 600
              ? 520
              : MediaQuery.of(context).size.width * 0.92,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: _purple.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12)),
                  child:
                      const Icon(Icons.upload_file, color: _purple, size: 24),
                ),
                const SizedBox(width: 14),
                const Text('Import Credit Notes',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 24),
              _importStep(
                step: '1',
                color: _blue,
                icon: Icons.download,
                title: 'Download Template',
                subtitle:
                    'Get the CSV template with required column format and sample data.',
                buttonLabel: 'Download Template',
                onPressed: _downloadTemplate,
              ),
              const SizedBox(height: 16),
              _importStep(
                step: '2',
                color: _green,
                icon: Icons.upload,
                title: 'Upload Filled CSV',
                subtitle:
                    'Fill in the template and upload it to import your credit notes.',
                buttonLabel: 'Select CSV File',
                onPressed: () {
                  Navigator.pop(context);
                  _selectAndImportFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _importStep({
    required String step,
    required Color color,
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    final circle = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
          child: Text(step,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16))),
    );
    final textBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14)),
      const SizedBox(height: 4),
      Text(subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]);
    final button = ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label:
          Text(buttonLabel, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 340) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [circle, const SizedBox(width: 10), Expanded(child: textBlock)]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: button),
          ]);
        }
        return Row(children: [circle, const SizedBox(width: 14), Expanded(child: textBlock), const SizedBox(width: 12), button]);
      }),
    );
  }

  // ── Date pickers ──────────────────────────────────────────────────────────

  Future<void> _selectFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() { _fromDate = picked; });
      _loadCreditNotes();
    }
  }

  Future<void> _selectToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() { _toDate = picked; });
      _loadCreditNotes();
    }
  }

  void _clearDateFilters() {
    setState(() { _fromDate = null; _toDate = null; });
    _loadCreditNotes();
  }

  bool get _hasDateFilters => _fromDate != null || _toDate != null;

  // ── Snackbars ─────────────────────────────────────────────────────────────

  void _snackSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(msg),
      ]),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _snackError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: Colors.red[700],
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ==========================================================================
  //  BUILD
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(title: 'Credit Notes'),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildTopBar(),
            if (_stats != null) _buildStatsCards(),
            _isLoading
                ? const SizedBox(
                    height: 400,
                    child: Center(
                        child: CircularProgressIndicator(color: _navy)))
                : _errorMessage != null
                    ? SizedBox(height: 400, child: _buildErrorState())
                    : _creditNotes.isEmpty
                        ? SizedBox(height: 400, child: _buildEmptyState())
                        : _buildCreditNoteTable(),
            if (!_isLoading && _creditNotes.isNotEmpty) _buildPagination(),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  //  TOP BAR  — 3 breakpoints mirroring PaymentMadeListPage
  //
  //  Desktop (≥1100px) : single Row, Spacer → actions far right
  //  Tablet  (700–1100): 2-row Column
  //  Mobile  (<700px)  : 3-row Column, row-3 horizontally scrollable
  // ==========================================================================

  Widget _buildTopBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: LayoutBuilder(builder: (_, constraints) {
        final w = constraints.maxWidth;
        if (w >= 1100) return _topBarDesktop();
        if (w >= 700)  return _topBarTablet();
        return _topBarMobile();
      }),
    );
  }

  // ── Desktop ────────────────────────────────────────────────────────────────
  Widget _topBarDesktop() => Row(children: [
    _statusDropdown(),
    const SizedBox(width: 12),
    _searchField(width: 240),
    const SizedBox(width: 10),
    _dateChip(
      label: _fromDate != null
          ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
          : 'From Date',
      isActive: _fromDate != null,
      onTap: _selectFromDate,
    ),
    const SizedBox(width: 8),
    _dateChip(
      label: _toDate != null
          ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
          : 'To Date',
      isActive: _toDate != null,
      onTap: _selectToDate,
    ),
    if (_hasDateFilters) ...[
      const SizedBox(width: 6),
      _iconBtn(Icons.close, _clearDateFilters,
          tooltip: 'Clear Dates', color: Colors.red[600]!, bg: Colors.red[50]!),
    ],
    const SizedBox(width: 6),
    _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refreshData,
        tooltip: 'Refresh'),
    const Spacer(),
    _actionBtn('New Credit Note', Icons.add_rounded, _navy, _openNewCreditNote),
    const SizedBox(width: 8),
    _actionBtn('Import', Icons.upload_file_rounded, _purple, _showImportDialog),
    const SizedBox(width: 8),
    _actionBtn('Export', Icons.download_rounded, _blue,
        _isLoading ? null : _exportToCsv),
    const SizedBox(width: 8),
    _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange,
        () => _raiseTicket()),
  ]);

  // ── Tablet ─────────────────────────────────────────────────────────────────
  Widget _topBarTablet() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        _statusDropdown(),
        const SizedBox(width: 10),
        _searchField(width: 220),
        const SizedBox(width: 8),
        _dateChip(
          label: _fromDate != null
              ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
              : 'From Date',
          isActive: _fromDate != null,
          onTap: _selectFromDate,
        ),
        const SizedBox(width: 6),
        _dateChip(
          label: _toDate != null
              ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
              : 'To Date',
          isActive: _toDate != null,
          onTap: _selectToDate,
        ),
        if (_hasDateFilters) ...[
          const SizedBox(width: 6),
          _iconBtn(Icons.close, _clearDateFilters,
              tooltip: 'Clear Dates',
              color: Colors.red[600]!,
              bg: Colors.red[50]!),
        ],
        const SizedBox(width: 6),
        _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refreshData,
            tooltip: 'Refresh'),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _actionBtn(
            'New Credit Note', Icons.add_rounded, _navy, _openNewCreditNote),
        const SizedBox(width: 8),
        _actionBtn(
            'Import', Icons.upload_file_rounded, _purple, _showImportDialog),
        const SizedBox(width: 8),
        _actionBtn('Export', Icons.download_rounded, _blue,
            _isLoading ? null : _exportToCsv),
        const SizedBox(width: 8),
        _actionBtn('Raise Ticket', Icons.confirmation_number_rounded, _orange,
            () => _raiseTicket()),
      ]),
    ],
  );

  // ── Mobile ─────────────────────────────────────────────────────────────────
  Widget _topBarMobile() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Single row: dropdown + search + New button
      Row(children: [
        _statusDropdown(),
        const SizedBox(width: 8),
        Expanded(child: _searchField(width: double.infinity)),
        const SizedBox(width: 8),
        _actionBtn('New', Icons.add_rounded, _navy, _openNewCreditNote),
      ]),
      const SizedBox(height: 10),
      // Row 2: Scrollable strip of utility buttons
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _dateChip(
            label: _fromDate != null
                ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}'
                : 'From Date',
            isActive: _fromDate != null,
            onTap: _selectFromDate,
          ),
          const SizedBox(width: 6),
          _dateChip(
            label: _toDate != null
                ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}'
                : 'To Date',
            isActive: _toDate != null,
            onTap: _selectToDate,
          ),
          if (_hasDateFilters) ...[
            const SizedBox(width: 6),
            _iconBtn(Icons.close, _clearDateFilters,
                tooltip: 'Clear',
                color: Colors.red[600]!,
                bg: Colors.red[50]!),
          ],
          const SizedBox(width: 6),
          _iconBtn(Icons.refresh_rounded, _isLoading ? null : _refreshData,
              tooltip: 'Refresh'),
          const SizedBox(width: 6),
          _compactBtn('Import', _purple, _showImportDialog),
          const SizedBox(width: 6),
          _compactBtn('Export', _blue, _isLoading ? null : _exportToCsv),
          const SizedBox(width: 6),
          _compactBtn('Ticket', _orange, () => _raiseTicket()),
        ]),
      ),
    ],
  );

  // ── Shared top-bar widgets ─────────────────────────────────────────────────

  Widget _statusDropdown() => Container(
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F9FC),
      border: Border.all(color: const Color(0xFFDDE3EE)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedStatus,
        icon: const Icon(Icons.expand_more, size: 18, color: _navy),
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: _navy),
        items: _statusFilters
            .map((s) => DropdownMenuItem(
                value: s,
                child:
                    Text(s == 'All' ? 'All Credit Notes' : s)))
            .toList(),
        onChanged: (v) { if (v != null) _filterByStatus(v); },
      ),
    ),
  );

  Widget _searchField({required double width}) {
    final field = TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search credit notes...',
        hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
        prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _searchController.clear();
                  setState(() { _searchQuery = ''; _currentPage = 1; });
                  _loadCreditNotes();
                })
            : null,
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
      onChanged: (v) {
        setState(() { _searchQuery = v.toLowerCase(); _currentPage = 1; });
        Future.delayed(const Duration(milliseconds: 400), () {
          if (_searchQuery == v.toLowerCase()) _loadCreditNotes();
        });
      },
    );
    if (width == double.infinity) return field;
    return SizedBox(width: width, height: 44, child: field);
  }

  Widget _dateChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? _navy.withOpacity(0.08) : const Color(0xFFF7F9FC),
          border: Border.all(
              color: isActive ? _navy : const Color(0xFFDDE3EE)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today,
              size: 15,
              color: isActive ? _navy : Colors.grey[500]),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? _navy : Colors.grey[600],
              )),
        ]),
      ),
    );
  }

  Widget _iconBtn(
    IconData icon,
    VoidCallback? onTap, {
    String tooltip = '',
    Color color = const Color(0xFF7F8C8D),
    Color bg = const Color(0xFFF1F1F1),
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Icon(icon,
              size: 20,
              color: onTap == null ? Colors.grey[300] : color),
        ),
      ),
    );
  }

  Widget _actionBtn(
      String label, IconData icon, Color bg, VoidCallback? onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _compactBtn(String label, Color bg, VoidCallback? onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        disabledBackgroundColor: bg.withOpacity(0.5),
        elevation: 0,
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }

  // ==========================================================================
  //  STATS CARDS
  //  Always 4 in ONE row:
  //  • Desktop: Expanded — fills full width, horizontal layout inside card
  //  • Mobile : fixed 160px each, row is horizontally scrollable
  // ==========================================================================

  Widget _buildStatsCards() {
    if (_stats == null) return const SizedBox.shrink();

    final List<_StatCardData> cards = [
      _StatCardData(
        label: 'Total Credit Amount',
        value: '₹${_stats!.totalCreditAmount.toStringAsFixed(2)}',
        icon: Icons.receipt_long,
        color: const Color(0xFFE74C3C),
        gradientColors: const [Color(0xFFFF6B6B), Color(0xFFE74C3C)],
      ),
      _StatCardData(
        label: 'Available Balance',
        value: '₹${_stats!.totalCreditBalance.toStringAsFixed(2)}',
        icon: Icons.account_balance_wallet,
        color: const Color(0xFF27AE60),
        gradientColors: const [Color(0xFF2ECC71), Color(0xFF27AE60)],
      ),
      _StatCardData(
        label: 'Credit Used',
        value: '₹${_stats!.totalCreditUsed.toStringAsFixed(2)}',
        icon: Icons.check_circle_outline,
        color: const Color(0xFFE67E22),
        gradientColors: const [Color(0xFFF39C12), Color(0xFFE67E22)],
      ),
      _StatCardData(
        label: 'Total Credit Notes',
        value: _stats!.totalCreditNotes.toString(),
        icon: Icons.description_outlined,
        color: _navy,
        gradientColors: const [Color(0xFF2463AE), Color(0xFF1e3a8a)],
      ),
    ];

    return Container(
      width: double.infinity,
      color: const Color(0xFFF0F4F8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(builder: (_, constraints) {
        final isMobile = constraints.maxWidth < 700;

        if (isMobile) {
          // ── Mobile: horizontally scrollable, each card 160px wide ──────
          return SingleChildScrollView(
            controller: _statsHScrollCtrl,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: cards.asMap().entries.map((entry) {
                final i = entry.key;
                final c = entry.value;
                return Container(
                  width: 160,
                  margin: EdgeInsets.only(right: i < cards.length - 1 ? 10 : 0),
                  child: _buildStatCard(c, compact: true),
                );
              }).toList(),
            ),
          );
        }

        // ── Desktop/Tablet: 4 equal Expanded cards, fill full width ───────
        return Row(
          children: cards.asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < cards.length - 1 ? 10 : 0),
                child: _buildStatCard(c, compact: false),
              ),
            );
          }).toList(),
        );
      }),
    );
  }

  Widget _buildStatCard(_StatCardData data, {required bool compact}) {
    return Container(
      padding: compact
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            data.gradientColors[0].withOpacity(0.15),
            data.gradientColors[1].withOpacity(0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: data.color.withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: data.color.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: compact
          // ── Mobile compact: icon top, text below ──────────────────────
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: data.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(data.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  data.label,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  data.value,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: data.color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            )
          // ── Desktop: icon left, text right ────────────────────────────
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: data.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: data.color.withOpacity(0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(data.icon, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        data.label,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        data.value,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: data.color),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ==========================================================================
  //  TABLE
  // ==========================================================================

  Widget _buildCreditNoteTable() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Scrollbar(
          controller: _tableHScrollCtrl,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8,
          radius: const Radius.circular(4),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: SingleChildScrollView(
              controller: _tableHScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                      const Color(0xFF0D1B3E)),
                  headingTextStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.4),
                  headingRowHeight: 52,
                  dataRowMinHeight: 58,
                  dataRowMaxHeight: 72,
                  dataTextStyle: const TextStyle(fontSize: 14),
                  dataRowColor:
                      WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered))
                      return _navy.withOpacity(0.04);
                    return null;
                  }),
                  dividerThickness: 1,
                  columnSpacing: 18,
                  horizontalMargin: 16,
                  columns: [
                    DataColumn(
                      label: SizedBox(
                        width: 36,
                        child: Checkbox(
                          value: _selectAll,
                          fillColor:
                              WidgetStateProperty.all(Colors.white),
                          checkColor: const Color(0xFF0D1B3E),
                          onChanged: _toggleSelectAll,
                        ),
                      ),
                    ),
                    const DataColumn(label: Text('DATE')),
                    const DataColumn(label: Text('CREDIT NOTE#')),
                    const DataColumn(label: Text('CUSTOMER')),
                    const DataColumn(label: Text('REASON')),
                    const DataColumn(label: Text('STATUS')),
                    const DataColumn(label: Text('AMOUNT')),
                    const DataColumn(label: Text('BALANCE')),
                    const DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: _creditNotes
                      .map((cn) => _buildCreditNoteRow(cn))
                      .toList(),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  DataRow _buildCreditNoteRow(CreditNote creditNote) {
    final bool isSelected =
        _selectedCreditNotes.contains(creditNote.id);
    return DataRow(
      selected: isSelected,
      color: WidgetStateProperty.resolveWith((states) {
        if (isSelected) return _navy.withOpacity(0.06);
        if (states.contains(WidgetState.hovered))
          return _navy.withOpacity(0.04);
        return null;
      }),
      cells: [
        DataCell(Checkbox(
          value: isSelected,
          onChanged: (_) => _toggleSelection(creditNote.id),
        )),
        DataCell(SizedBox(
          width: 110,
          child: Text(DateFormat('dd MMM yyyy')
              .format(creditNote.creditNoteDate)),
        )),
        DataCell(SizedBox(
          width: 150,
          child: InkWell(
            onTap: () => _openEditCreditNote(creditNote.id),
            child: Text(
              creditNote.creditNoteNumber,
              style: const TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )),
        DataCell(SizedBox(
          width: 170,
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _navy.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  creditNote.customerName.isNotEmpty
                      ? creditNote.customerName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
              ),
            ),
            Expanded(
              child: Text(creditNote.customerName,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ]),
        )),
        DataCell(SizedBox(
          width: 140,
          child: Text(creditNote.reason,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[600])),
        )),
        DataCell(SizedBox(
            width: 110,
            child: _buildStatusBadge(creditNote.status))),
        DataCell(SizedBox(
          width: 120,
          child: Text(
            '₹${creditNote.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        )),
        DataCell(SizedBox(
          width: 120,
          child: Text(
            '₹${creditNote.creditBalance.toStringAsFixed(2)}',
            style: TextStyle(
                color: creditNote.creditBalance > 0
                    ? _green
                    : Colors.grey,
                fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        )),
        DataCell(SizedBox(
          width: 130,
          child: Row(children: [
            // Share button — blue
            Tooltip(
              message: 'Share',
              child: InkWell(
                onTap: () => _shareCreditNote(creditNote),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _blue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.share, size: 16, color: _blue),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // WhatsApp button — green
            // Tooltip(
            //   message: 'WhatsApp',
            //   child: InkWell(
            //     onTap: () => _whatsAppCreditNote(creditNote),
            //     borderRadius: BorderRadius.circular(8),
            //     child: Container(
            //       width: 32,
            //       height: 32,
            //       decoration: BoxDecoration(
            //         color: const Color(0xFF25D366).withOpacity(0.10),
            //         borderRadius: BorderRadius.circular(8),
            //       ),
            //       child: const Icon(Icons.chat, size: 16,
            //           color: Color(0xFF25D366)),
            //     ),
            //   ),
            // ),
            // const SizedBox(width: 4),
            // More actions popup
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              onSelected: (value) async {
                switch (value) {
                  case 'view':
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => CreditNoteDetailPage(creditNoteId: creditNote.id)));
                    break;
                  case 'edit':
                    _openEditCreditNote(creditNote.id);
                    break;
                  case 'send':
                    await _sendCreditNote(creditNote);
                    break;
                  case 'download':
                    await _downloadCreditNotePDF(creditNote);
                    break;
                  case 'ticket':
                    _raiseTicket(creditNote);
                    break;
                  case 'delete':
                    await _deleteCreditNote(creditNote);
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                      leading: Icon(Icons.visibility, size: 17, color: Color(0xFF3D8EFF)),
                      title: Text('View Details'),
                      contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                      leading: Icon(Icons.edit_outlined,
                          size: 17, color: _navy),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'send',
                  child: ListTile(
                      leading: Icon(Icons.send_outlined,
                          size: 17, color: _green),
                      title: Text('Send Email'),
                      contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'download',
                  child: ListTile(
                      leading: Icon(Icons.download_outlined,
                          size: 17, color: _purple),
                      title: Text('Download PDF'),
                      contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'ticket',
                  child: ListTile(
                      leading: Icon(Icons.confirmation_number_outlined,
                          size: 17, color: Color(0xFFE67E22)),
                      title: Text('Raise Ticket',
                          style: TextStyle(color: Color(0xFFE67E22))),
                      contentPadding: EdgeInsets.zero),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                      leading: Icon(Icons.delete_outline,
                          size: 17, color: Colors.red),
                      title: Text('Delete',
                          style: TextStyle(color: Colors.red)),
                      contentPadding: EdgeInsets.zero),
                ),
              ],
            ),
          ]),
        )),
      ],
    );
  }

  // ── Status Badge ──────────────────────────────────────────────────────────

  Widget _buildStatusBadge(String status) {
    final Map<String, List<Color>> statusColors = {
      'OPEN':     [const Color(0xFFDBEAFE), const Color(0xFF1D4ED8)],
      'CLOSED':   [const Color(0xFFF1F5F9), const Color(0xFF64748B)],
      'REFUNDED': [const Color(0xFFDCFCE7), const Color(0xFF15803D)],
      'VOID':     [const Color(0xFFFEE2E2), const Color(0xFFDC2626)],
      'DRAFT':    [const Color(0xFFFEF3C7), const Color(0xFFB45309)],
    };
    final c = statusColors[status] ??
        [const Color(0xFFF1F5F9), const Color(0xFF64748B)];
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c[0],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c[1].withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: c[1], shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(status,
            style: TextStyle(
                color: c[1],
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.3)),
      ]),
    );
  }

  // ==========================================================================
  //  PAGINATION
  // ==========================================================================

  Widget _buildPagination() {
    List<int> pages;
    if (_totalPages <= 5) {
      pages = List.generate(_totalPages, (i) => i + 1);
    } else {
      final int start =
          (_currentPage - 2).clamp(1, _totalPages - 4);
      pages = List.generate(5, (i) => start + i);
    }

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEF2F7))),
      ),
      child: LayoutBuilder(builder: (_, constraints) {
        final bool isNarrow = constraints.maxWidth < 500;
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            Text(
              'Showing ${(_currentPage - 1) * _itemsPerPage + 1}–'
              '${(_currentPage * _itemsPerPage).clamp(0, _totalCreditNotes)}'
              ' of $_totalCreditNotes',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _pageNavBtn(
                icon: Icons.chevron_left,
                enabled: _currentPage > 1,
                onTap: () {
                  setState(() => _currentPage--);
                  _loadCreditNotes();
                },
              ),
              const SizedBox(width: 4),
              if (!isNarrow && pages.first > 1) ...[
                _pageNumBtn(1),
                if (pages.first > 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text('…',
                        style: TextStyle(color: Colors.grey[400])),
                  ),
              ],
              ...pages.map((p) => _pageNumBtn(p)),
              if (!isNarrow && pages.last < _totalPages) ...[
                if (pages.last < _totalPages - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text('…',
                        style: TextStyle(color: Colors.grey[400])),
                  ),
                _pageNumBtn(_totalPages),
              ],
              const SizedBox(width: 4),
              _pageNavBtn(
                icon: Icons.chevron_right,
                enabled: _currentPage < _totalPages,
                onTap: () {
                  setState(() => _currentPage++);
                  _loadCreditNotes();
                },
              ),
            ]),
          ],
        );
      }),
    );
  }

  Widget _pageNumBtn(int page) {
    final bool isActive = _currentPage == page;
    return GestureDetector(
      onTap: () {
        if (!isActive) {
          setState(() => _currentPage = page);
          _loadCreditNotes();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: isActive ? _navy : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: isActive ? _navy : Colors.grey[300]!),
        ),
        child: Center(
          child: Text('$page',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color:
                      isActive ? Colors.white : Colors.grey[700])),
        ),
      ),
    );
  }

  Widget _pageNavBtn({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(icon,
            size: 18,
            color: enabled ? _navy : Colors.grey[300]),
      ),
    );
  }

  // ==========================================================================
  //  EMPTY STATE
  // ==========================================================================

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _navy.withOpacity(0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.receipt_long_outlined,
                size: 64, color: _navy.withOpacity(0.4)),
          ),
          const SizedBox(height: 20),
          const Text('No credit notes found',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A202C))),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _selectedStatus != 'All'
                ? 'Try adjusting your filters'
                : 'Create your first credit note to get started',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _openNewCreditNote,
            icon: const Icon(Icons.add),
            label: const Text('Create Credit Note',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
    );
  }

  // ==========================================================================
  //  ERROR STATE
  // ==========================================================================

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: Colors.red[50], shape: BoxShape.circle),
            child: Icon(Icons.error_outline,
                size: 56, color: Colors.red[400]),
          ),
          const SizedBox(height: 20),
          const Text('Failed to Load Credit Notes',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A202C))),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _errorMessage ?? 'An unknown error occurred',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again',
                style: TextStyle(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ]),
      ),
    );
  }
} // ← END of _CreditNotesListPageState

// =============================================================================
//  RAISE TICKET OVERLAY
//  Replicates _RaiseTicketOverlay from recurring_invoices_list_page.dart
//  Works on both web and mobile (pure Flutter dialog — no platform differences)
// =============================================================================

class _CreditNoteRaiseTicketOverlay extends StatefulWidget {
  final CreditNote? creditNote;
  final void Function(String) onTicketRaised;
  final void Function(String) onError;

  const _CreditNoteRaiseTicketOverlay({
    this.creditNote,
    required this.onTicketRaised,
    required this.onError,
  });

  @override
  State<_CreditNoteRaiseTicketOverlay> createState() =>
      _CreditNoteRaiseTicketOverlayState();
}

class _CreditNoteRaiseTicketOverlayState
    extends State<_CreditNoteRaiseTicketOverlay> {
  final _tmsService = TMSService();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filtered  = [];
  Map<String, dynamic>?      _selectedEmp;
  bool _loading   = true;
  bool _assigning = false;
  String _priority = 'Medium';

  static const Color _navy   = Color(0xFF1e3a8a);
  static const Color _orange = Color(0xFFE67E22);
  static const Color _green  = Color(0xFF27AE60);
  static const Color _red    = Color(0xFFE74C3C);

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    final resp = await _tmsService.fetchEmployees();
    if (resp['success'] == true && resp['data'] != null) {
      setState(() {
        _employees = List<Map<String, dynamic>>.from(resp['data']);
        _filtered  = _employees;
        _loading   = false;
      });
    } else {
      setState(() => _loading = false);
      widget.onError('Failed to load employees');
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _employees
          : _employees.where((e) {
              return (e['name_parson'] ?? '').toLowerCase().contains(q) ||
                     (e['email'] ?? '').toLowerCase().contains(q) ||
                     (e['role'] ?? '').toLowerCase().contains(q);
            }).toList();
    });
  }

  String _buildTicketMessage() {
    if (widget.creditNote == null) {
      return 'A credit note ticket has been raised and requires your attention.';
    }
    final cn = widget.creditNote!;
    return 'Credit Note "${cn.creditNoteNumber}" for customer '
        '"${cn.customerName}" (${cn.customerEmail ?? '-'}) requires attention.\n\n'
        'Credit Note Details:\n'
        '• Date    : ${DateFormat('dd MMM yyyy').format(cn.creditNoteDate)}\n'
        '• Reason  : ${cn.reason}\n'
        '• Status  : ${cn.status}\n'
        '• Amount  : ₹${cn.totalAmount.toStringAsFixed(2)}\n'
        '• Balance : ₹${cn.creditBalance.toStringAsFixed(2)}\n\n'
        'Please review and take necessary action.';
  }

  Future<void> _assign() async {
    if (_selectedEmp == null) return;
    setState(() => _assigning = true);
    try {
      final resp = await _tmsService.createTicket(
        subject: widget.creditNote != null
            ? 'Credit Note: ${widget.creditNote!.creditNoteNumber}'
            : 'Credit Notes — Action Required',
        message:    _buildTicketMessage(),
        priority:   _priority,
        timeline:   1440, // 24 hours
        assignedTo: _selectedEmp!['_id'].toString(),
      );
      setState(() => _assigning = false);
      if (resp['success'] == true) {
        widget.onTicketRaised(
            'Ticket assigned to ${_selectedEmp!['name_parson']}');
        if (mounted) Navigator.pop(context);
      } else {
        widget.onError(resp['message'] ?? 'Failed to create ticket');
      }
    } catch (e) {
      setState(() => _assigning = false);
      widget.onError('Failed to assign ticket: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        width: 520,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ── Header ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1e3a8a), Color(0xFF2463AE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft:  Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                    Icons.confirmation_number_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Raise a Ticket',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  if (widget.creditNote != null)
                    Text(
                      'Credit Note: ${widget.creditNote!.creditNoteNumber}',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                ]),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),

          // ── Body ──────────────────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Auto message preview
                if (widget.creditNote != null) ...[
                  const Text('Auto-generated message',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: _navy)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4F8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFDDE3EE)),
                    ),
                    child: Text(_buildTicketMessage(),
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            height: 1.5)),
                  ),
                  const SizedBox(height: 20),
                ],

                // Priority selector
                const Text('Priority',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: _navy)),
                const SizedBox(height: 8),
                Row(
                  children: ['Low', 'Medium', 'High'].map((pr) {
                    final isSel = _priority == pr;
                    final color = pr == 'High'
                        ? _red
                        : pr == 'Medium'
                            ? _orange
                            : _green;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => setState(() => _priority = pr),
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel ? color : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: isSel
                                      ? color
                                      : Colors.grey[300]!),
                              boxShadow: isSel
                                  ? [
                                      BoxShadow(
                                        color:
                                            color.withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      )
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: Text(pr,
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSel
                                          ? Colors.white
                                          : Colors.grey[700])),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // Employee search
                const Text('Assign To',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: _navy)),
                const SizedBox(height: 8),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search employees…',
                    prefixIcon: Icon(Icons.search,
                        size: 18, color: Colors.grey[400]),
                    filled: true,
                    fillColor: const Color(0xFFF7F9FC),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFFDDE3EE))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFFDDE3EE))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: _navy, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 8),

                // Employee list
                _loading
                    ? const SizedBox(
                        height: 120,
                        child: Center(
                            child: CircularProgressIndicator(
                                color: _navy)))
                    : _filtered.isEmpty
                        ? Container(
                            height: 80,
                            alignment: Alignment.center,
                            child: Text('No employees found',
                                style: TextStyle(
                                    color: Colors.grey[500])))
                        : Container(
                            constraints:
                                const BoxConstraints(maxHeight: 240),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: const Color(0xFFDDE3EE)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  color: Color(0xFFEEF2F7)),
                              itemBuilder: (_, i) {
                                final emp  = _filtered[i];
                                final isSel =
                                    _selectedEmp?['_id'] == emp['_id'];
                                return InkWell(
                                  onTap: () => setState(() =>
                                      _selectedEmp =
                                          isSel ? null : emp),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    color: isSel
                                        ? _navy.withOpacity(0.06)
                                        : Colors.transparent,
                                    child: Row(children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: isSel
                                            ? _navy
                                            : _navy.withOpacity(0.10),
                                        child: Text(
                                          (emp['name_parson'] ??
                                                  'U')[0]
                                              .toUpperCase(),
                                          style: TextStyle(
                                              color: isSel
                                                  ? Colors.white
                                                  : _navy,
                                              fontWeight:
                                                  FontWeight.bold,
                                              fontSize: 13),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                emp['name_parson'] ??
                                                    'Unknown',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600,
                                                    fontSize: 13)),
                                            if (emp['email'] != null)
                                              Text(emp['email'],
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Colors
                                                          .grey[600]),
                                                  overflow: TextOverflow
                                                      .ellipsis),
                                            if (emp['role'] != null)
                                              Container(
                                                margin:
                                                    const EdgeInsets.only(
                                                        top: 3),
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 6,
                                                    vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: _navy
                                                      .withOpacity(0.08),
                                                  borderRadius:
                                                      BorderRadius
                                                          .circular(4),
                                                ),
                                                child: Text(
                                                  emp['role']
                                                      .toString()
                                                      .toUpperCase(),
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: _navy),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (isSel)
                                        const Icon(Icons.check_circle,
                                            color: _navy, size: 20),
                                    ]),
                                  ),
                                );
                              },
                            ),
                          ),
              ]),
            ),
          ),

          // ── Footer ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F9FC),
              border:
                  Border(top: BorderSide(color: Color(0xFFEEF2F7))),
              borderRadius: BorderRadius.only(
                bottomLeft:  Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_selectedEmp == null || _assigning)
                      ? null
                      : _assign,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _navy.withOpacity(0.4),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _assigning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(
                          _selectedEmp != null
                              ? 'Assign to ${_selectedEmp!['name_parson'] ?? ''}'
                              : 'Select Employee',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}