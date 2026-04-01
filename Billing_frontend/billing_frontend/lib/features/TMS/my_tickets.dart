// lib/screens/tms/my_tickets_screen.dart
// ============================================================================
// 🎫 MY TICKETS SCREEN
// ============================================================================
// Layout:
// - Top bar: back + title + [My Tickets | Raised by Me] tabs
// - Stat cards: centered, h-scroll, switch per tab
// - Single horizontally scrollable filter+action row:
//   Search | Status | Priority | Date From | Date To | Export | Refresh
// - Dark navy #0D1B3E table, drag-to-scroll, ellipsis pagination
// - My Tickets tab   → status dropdown per row, full overlay on tap
// - Raised by Me tab → status badge only (read-only), share only
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/services/tms_service.dart';
import '../../core/utils/export_helper.dart';
import '../TMS/ticket_detail_screen.dart';
import '../TMS/raise_ticket.dart';

// lib/screens/tms/my_tickets_screen.dart
// ============================================================================
// 🎫 MY TICKETS SCREEN
// ============================================================================


class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({Key? key}) : super(key: key);

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen>
    with SingleTickerProviderStateMixin {
  final _tmsService       = TMSService();
  final _searchController = TextEditingController();
  final ScrollController _hScroll  = ScrollController();
  final ScrollController _vScroll  = ScrollController();
  final ScrollController _hScroll2 = ScrollController();
  final ScrollController _vScroll2 = ScrollController();

  // ── Design tokens ──────────────────────────────────────────────────────────
  static const Color navyDark   = Color(0xFF0D1B3E);
  static const Color navyMid    = Color(0xFF1A2F5E);
  static const Color navyLight  = Color(0xFF243B6E);
  static const Color accentBlue = Color(0xFF3B82F6);

  static const Color cOpen       = Color(0xFFEF4444);
  static const Color cInProgress = Color(0xFFF59E0B);
  static const Color cApproved   = Color(0xFF10B981);
  static const Color cRejected   = Color(0xFFEF4444);
  static const Color cReply      = Color(0xFF8B5CF6);
  static const Color cClosed     = Color(0xFF64748B);

  int _activeTab = 0;

  List<Map<String, dynamic>> _allData    = [];
  List<Map<String, dynamic>> _myTickets  = [];
  List<Map<String, dynamic>> _raisedByMe = [];
  List<Map<String, dynamic>> _filtered   = [];

  bool _isLoading   = true;
  bool _isExporting = false;

  String    _statusFilter   = 'all';
  String    _priorityFilter = 'all';
  String    _searchQuery    = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  int _myOpen = 0, _myInProgress = 0, _myApproved = 0,
      _myRejected = 0, _myReply = 0, _myClosed = 0;
  int _rOpen = 0, _rInProgress = 0, _rApproved = 0,
      _rRejected = 0, _rReply = 0, _rClosed = 0;

  int _currentPage  = 1;
  final int _perPage = 15;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  static const List<String> _allStatuses = [
    'Open', 'In Progress', 'Approved', 'Rejected', 'Reply', 'closed'
  ];

  // Statuses that trigger the compose dialog
  static const List<String> _composeStatuses = ['Approved', 'Rejected', 'Reply'];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        duration: const Duration(milliseconds: 1500), vsync: this)
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _fetchTickets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _hScroll.dispose(); _vScroll.dispose();
    _hScroll2.dispose(); _vScroll2.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────
  Future<void> _fetchTickets() async {
    setState(() => _isLoading = true);
    // Fetch both in parallel
    final results = await Future.wait([
      _tmsService.fetchMyTickets(status: null),
      _tmsService.fetchRaisedByMe(),
    ]);
    final myR     = results[0];
    final raisedR = results[1];

    setState(() {
      _myTickets  = myR['success'] == true && myR['data'] != null
          ? List<Map<String, dynamic>>.from(myR['data'])
          : [];
      _raisedByMe = raisedR['success'] == true && raisedR['data'] != null
          ? List<Map<String, dynamic>>.from(raisedR['data'])
          : [];
      _allData    = _myTickets;
      _calcStats();
      _applyFilters();
      _isLoading  = false;
    });

    if (myR['success'] != true) _snack('Failed to load tickets', isError: true);
  }

  void _calcStats() {
    _myOpen = _myInProgress = _myApproved =
        _myRejected = _myReply = _myClosed = 0;
    for (final t in _myTickets) {
      switch (t['status']) {
        case 'Open':        _myOpen++;        break;
        case 'In Progress': _myInProgress++;  break;
        case 'Approved':    _myApproved++;    break;
        case 'Rejected':    _myRejected++;    break;
        case 'Reply':       _myReply++;       break;
        case 'closed':      _myClosed++;      break;
      }
    }
    _rOpen = _rInProgress = _rApproved =
        _rRejected = _rReply = _rClosed = 0;
    for (final t in _raisedByMe) {
      switch (t['status']) {
        case 'Open':        _rOpen++;        break;
        case 'In Progress': _rInProgress++;  break;
        case 'Approved':    _rApproved++;    break;
        case 'Rejected':    _rRejected++;    break;
        case 'Reply':       _rReply++;       break;
        case 'closed':      _rClosed++;      break;
      }
    }
  }

  void _applyFilters() {
    final source = _activeTab == 0 ? _myTickets : _raisedByMe;
    List<Map<String, dynamic>> res = List.from(source);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      res = res.where((t) =>
        (t['subject']?.toString().toLowerCase().contains(q) ?? false) ||
        (t['ticket_number']?.toString().toLowerCase().contains(q) ?? false) ||
        (t['message']?.toString().toLowerCase().contains(q) ?? false) ||
        (t['assigned_to_name']?.toString().toLowerCase().contains(q) ?? false)
      ).toList();
    }
    if (_statusFilter != 'all') {
      res = res.where((t) => t['status'] == _statusFilter).toList();
    }
    if (_priorityFilter != 'all') {
      res = res.where((t) =>
        t['priority']?.toString().toLowerCase() == _priorityFilter.toLowerCase()
      ).toList();
    }
    if (_dateFrom != null || _dateTo != null) {
      res = res.where((t) {
        final d = DateTime.tryParse(t['created_at']?.toString() ?? '');
        if (d == null) return false;
        if (_dateFrom != null && d.isBefore(_dateFrom!)) return false;
        if (_dateTo != null) {
          final end = DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day, 23, 59, 59);
          if (d.isAfter(end)) return false;
        }
        return true;
      }).toList();
    }
    setState(() { _filtered = res; _currentPage = 1; });
  }

  List<Map<String, dynamic>> get _paged {
    final s = (_currentPage - 1) * _perPage;
    final e = (s + _perPage).clamp(0, _filtered.length);
    if (s >= _filtered.length) return [];
    return _filtered.sublist(s, e);
  }
  int get _totalPages => (_filtered.length / _perPage).ceil().clamp(1, 9999);

  // ── Helpers ────────────────────────────────────────────────────────────────
  Color _sc(String s) {
    switch (s) {
      case 'Open':        return cOpen;
      case 'In Progress': return cInProgress;
      case 'Approved':    return cApproved;
      case 'Rejected':    return cRejected;
      case 'Reply':       return cReply;
      case 'closed':      return cClosed;
      default:            return Colors.grey;
    }
  }
  String _sl(String s) => s == 'closed' ? 'Closed' : s;

  Color _pc(String p) {
    switch (p.toLowerCase()) {
      case 'high':   return cOpen;
      case 'medium': return cInProgress;
      case 'low':    return cApproved;
      default:       return Colors.grey;
    }
  }

  String _fmtTimeline(dynamic m) {
    final mins = int.tryParse(m?.toString() ?? '') ?? 0;
    if (mins <= 0)    return 'Not Set';
    if (mins < 60)    return '$mins min';
    if (mins < 1440)  return '${(mins/60).floor()}h';
    if (mins < 10080) return '${(mins/1440).floor()}d';
    if (mins < 43200) return '${(mins/10080).floor()}w';
    return '${(mins/43200).floor()}mo';
  }
  String _fmtDate(dynamic r) {
    if (r == null) return 'N/A';
    final d = DateTime.tryParse(r.toString());
    return d == null ? 'N/A' : DateFormat('dd MMM yyyy').format(d.toLocal());
  }
  String _fmtDateTime(dynamic r) {
    if (r == null) return 'N/A';
    final d = DateTime.tryParse(r.toString());
    return d == null ? 'N/A' : DateFormat('dd MMM yyyy, hh:mm a').format(d.toLocal());
  }
  String _fmtExport(dynamic r) {
    if (r == null) return 'N/A';
    final d = DateTime.tryParse(r.toString());
    return d == null ? 'N/A' : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
  }

  // ── Pre-fill templates ─────────────────────────────────────────────────────
  String _defaultSubject(String status, String ticketNum, String subject) {
    switch (status) {
      case 'Approved': return 'Approved: $subject';
      case 'Rejected': return 'Rejected: $subject';
      case 'Reply':    return 'Re: $subject';
      default:         return subject;
    }
  }

  String _defaultMessage(String status, String ticketNum, String subject) {
    switch (status) {
      case 'Approved':
        return 'Dear Requester,\n\nYour ticket $ticketNum has been reviewed and approved.\n\nSubject: $subject\n\nPlease proceed accordingly.\n\nThank you.';
      case 'Rejected':
        return 'Dear Requester,\n\nAfter careful review, your ticket $ticketNum has been rejected.\n\nSubject: $subject\n\nReason: [Please provide reason here]\n\nThank you.';
      case 'Reply':
        return 'Dear Requester,\n\nRegarding your ticket $ticketNum:\n\nSubject: $subject\n\n[Type your reply here]\n\nThank you.';
      default:
        return '';
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Called when any status change is requested.
  /// For Approved/Rejected/Reply → shows compose dialog first.
  /// For closed → shows simple confirmation.
  /// For others → updates directly.
  void _handleStatusChange(Map<String, dynamic> ticket, String newStatus) {
    final id        = ticket['_id']?.toString() ?? '';
    final ticketNum = ticket['ticket_number'] ?? '';
    final subject   = ticket['subject'] ?? '';

    if (_composeStatuses.contains(newStatus)) {
      _showComposeDialog(
        ticketId:  id,
        ticketNum: ticketNum,
        newStatus: newStatus,
        subject:   subject,
        ticket:    ticket,
      );
    } else if (newStatus == 'closed') {
      _showCloseConfirmation(id);
    } else {
      _updateStatus(id, newStatus, null, null, ticketNum: ticketNum);
    }
  }

  Future<void> _updateStatus(
    String id,
    String newStatus,
    String? replySubject,
    String? replyMessage, {
    String? ticketNum,
  }) async {
    final r = await _tmsService.updateTicketStatus(
      id,
      newStatus,
      replySubject: replySubject,
      replyMessage: replyMessage,
    );
    if (r['success'] == true) {
      final label = ticketNum != null ? '$ticketNum — ${_sl(newStatus)}' : _sl(newStatus);
      _snack('✅ $label');
      _fetchTickets();
    } else {
      _snack('Failed to update status', isError: true);
    }
  }

  void _share(Map<String, dynamic> t) =>
    Share.share('Ticket: ${t['ticket_number'] ?? 'N/A'}\nSubject: ${t['subject'] ?? ''}');

  Future<void> _export() async {
    if (_filtered.isEmpty) { _snack('No tickets to export', isError: true); return; }
    setState(() => _isExporting = true);
    try {
      final data = <List<dynamic>>[
        ['Ticket #','Subject','Message','Raised By','Creator Email',
         'Assigned To','Assigned Email','Priority','Status',
         'Timeline','Deadline','Created At','Updated At','Source'],
      ];
      for (final t in _filtered) {
        data.add([
          t['ticket_number'] ?? '', t['subject'] ?? '', t['message'] ?? '',
          t['name'] ?? t['created_by_name'] ?? 'N/A',
          t['creator_email'] ?? '',
          t['assigned_to_name'] ?? 'Not Assigned',
          t['assigned_email'] ?? '',
          t['priority'] ?? '', _sl(t['status'] ?? ''),
          _fmtTimeline(t['timeline']),
          _fmtExport(t['deadline']), _fmtExport(t['created_at']),
          _fmtExport(t['updated_at']), t['source'] ?? 'manual',
        ]);
      }
      await ExportHelper.exportToExcel(
          data: data,
          filename: _activeTab == 0 ? 'my_tickets' : 'raised_by_me');
      _snack('✅ Exported ${_filtered.length} tickets');
    } catch (e) {
      _snack('Export failed: $e', isError: true);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.check_circle,
            color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _showCloseConfirmation(String ticketId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Close Ticket?',
            style: TextStyle(color: navyDark, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to close this ticket?',
            style: TextStyle(color: Color(0xFF64748B))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateStatus(ticketId, 'closed', null, null);
            },
            style: ElevatedButton.styleFrom(backgroundColor: cOpen,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Close Ticket',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Re-raise helper ────────────────────────────────────────────────────────
  /// Finds the original creator's employee _id by matching creator_email
  /// against the already-loaded employees list.
  String? _findEmployeeIdByEmail(String email) {
    if (email.isEmpty) return null;
    // _myTickets employees aren't loaded here — we need to fetch from service.
    // We'll pass null and let RaiseTicketScreen handle the pre-selection via name only.
    return null;
  }

  /// Saves the reply then opens RaiseTicketScreen pre-filled to re-raise back
  /// to the original ticket creator.
  Future<void> _confirmAndReRaise({
    required String ticketId,
    required String ticketNum,
    required String newStatus,
    required String replySubject,
    required String replyMessage,
    required Map<String, dynamic> ticket,
    required BuildContext dialogCtx,
    required void Function(void Function()) setD,
  }) async {
    setD(() {});
    Navigator.pop(dialogCtx);

    // 1. Save the reply / status update
    await _updateStatus(
      ticketId,
      newStatus,
      replySubject,
      replyMessage,
      ticketNum: ticketNum,
    );

    // 2. Build pre-fill data for the new ticket
    final creatorEmail = ticket['creator_email']?.toString() ?? '';
    final creatorName  = (ticket['name'] ?? ticket['created_by_name'] ?? '').toString();
    final origSubject  = ticket['subject']?.toString() ?? '';
    final origMessage  = ticket['message']?.toString() ?? '';
    final origPriority = ticket['priority']?.toString() ?? 'Medium';
    final origTimeline = int.tryParse(ticket['timeline']?.toString() ?? '');

    // Try to find the creator's _id from the employees list
    // (employees are fetched fresh in RaiseTicketScreen, so we pass email as name hint)
    final prefillSubject = 'Re: $origSubject [ref: $ticketNum]';
    final prefillMessage =
        'Dear $creatorName,\n\nRegarding your ticket $ticketNum:\n\n'
        'Subject: $origSubject\n\nOriginal message:\n$origMessage\n\n'
        '[Add your follow-up here]\n\nThank you.';

    if (!mounted) return;

    // 3. Navigate to RaiseTicketScreen pre-filled
    // We pass creatorEmail as assignedToName so the user can see who it's going to.
    // The employee _id lookup happens inside RaiseTicketScreen via _fetchEmployees.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RaiseTicketScreen(
          prefillSubject:        prefillSubject,
          prefillMessage:        prefillMessage,
          prefillPriority:       origPriority,
          prefillTimeline:       origTimeline,
          prefillAssignedToName: creatorName.isNotEmpty ? creatorName : creatorEmail,
          // _id is resolved inside RaiseTicketScreen after employees load
        ),
      ),
    );
  }

  // ── Compose Dialog ─────────────────────────────────────────────────────────
  void _showComposeDialog({
    required String ticketId,
    required String ticketNum,
    required String newStatus,
    required String subject,
    required Map<String, dynamic> ticket,
  }) {
    final subjectCtrl = TextEditingController(
        text: _defaultSubject(newStatus, ticketNum, subject));
    final messageCtrl = TextEditingController(
        text: _defaultMessage(newStatus, ticketNum, subject));
    final statusColor = _sc(newStatus);
    bool isSending = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30, offset: const Offset(0, 12))],
            ),
            child: Column(children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [statusColor.withOpacity(0.9), statusColor],
                    begin: Alignment.centerLeft, end: Alignment.centerRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(children: [
                  Icon(_statusIcon(newStatus), color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Mark as ${_sl(newStatus)}',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(ticketNum,
                          style: TextStyle(color: Colors.white.withOpacity(0.8),
                              fontSize: 12)),
                    ]),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ]),
              ),

              // Body
              Expanded(child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline, size: 16, color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'This response will be saved to the ticket and visible to the ticket raiser under "Raised by Me".',
                        style: TextStyle(fontSize: 12, color: statusColor),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Subject
                  _composeLabel('Subject', Icons.subject),
                  const SizedBox(height: 6),
                  _composeField(subjectCtrl, 'Enter subject...', maxLines: 1),
                  const SizedBox(height: 14),

                  // Message
                  _composeLabel('Message / Response', Icons.message_outlined),
                  const SizedBox(height: 6),
                  _composeField(messageCtrl, 'Type your response...', maxLines: 7),
                ]),
              )),

              // Footer
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(color: Colors.grey.withOpacity(0.15))),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Row 1: Cancel + Confirm & Mark
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: Colors.grey.withOpacity(0.3)),
                        ),
                        child: const Text('Cancel',
                            style: TextStyle(color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: isSending ? null : () async {
                          if (subjectCtrl.text.trim().isEmpty ||
                              messageCtrl.text.trim().isEmpty) {
                            _snack('Subject and message are required',
                                isError: true);
                            return;
                          }
                          setD(() => isSending = true);
                          Navigator.pop(ctx);
                          await _updateStatus(
                            ticketId,
                            newStatus,
                            subjectCtrl.text.trim(),
                            messageCtrl.text.trim(),
                            ticketNum: ticketNum,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: statusColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isSending
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Row(mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.send_rounded,
                                      size: 16, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text('Confirm & Mark ${_sl(newStatus)}',
                                      style: const TextStyle(color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // Row 2: Confirm & Re-raise (full width)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSending ? null : () async {
                        if (subjectCtrl.text.trim().isEmpty ||
                            messageCtrl.text.trim().isEmpty) {
                          _snack('Subject and message are required',
                              isError: true);
                          return;
                        }
                        setD(() => isSending = true);
                        await _confirmAndReRaise(
                          ticketId:     ticketId,
                          ticketNum:    ticketNum,
                          newStatus:    newStatus,
                          replySubject: subjectCtrl.text.trim(),
                          replyMessage: messageCtrl.text.trim(),
                          ticket:       ticket,
                          dialogCtx:    ctx,
                          setD:         setD,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: navyDark,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isSending
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.reply_all_rounded,
                                    size: 16, color: Colors.white),
                                SizedBox(width: 8),
                                Text('Confirm & Re-raise Ticket',
                                    style: TextStyle(color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ]),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _composeLabel(String label, IconData icon) => Row(children: [
    Icon(icon, size: 14, color: navyDark),
    const SizedBox(width: 6),
    Text(label, style: const TextStyle(fontSize: 13,
        fontWeight: FontWeight.bold, color: navyDark)),
  ]);

  Widget _composeField(TextEditingController ctrl, String hint,
      {int maxLines = 1}) =>
    TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13, color: navyDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: navyDark, width: 1.5)),
      ),
    );

  IconData _statusIcon(String s) {
    switch (s) {
      case 'Approved': return Icons.check_circle_outline;
      case 'Rejected': return Icons.cancel_outlined;
      case 'Reply':    return Icons.reply;
      default:         return Icons.info_outline;
    }
  }

  // ==========================================================================
  // BUILD
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        _buildTopBar(),
        _buildStatCards(),
        const SizedBox(height: 14),
        _buildFilterRow(),
        const SizedBox(height: 10),
        Expanded(child: _isLoading ? _loader() : _buildBody()),
      ]),
    );
  }

  // ── Top Bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
          colors: [navyDark, navyMid, navyLight],
          begin: Alignment.centerLeft, end: Alignment.centerRight),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 14),
          const Icon(Icons.confirmation_number_outlined,
              color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          const Text('Tickets', style: TextStyle(color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          _tabBtn('My Tickets', 0),
          const SizedBox(width: 8),
          _tabBtn('Raised by Me', 1),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20)),
            child: Text('${_filtered.length} records',
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ]),
      ),
    ),
  );

  Widget _tabBtn(String label, int idx) {
    final active = _activeTab == idx;
    return GestureDetector(
      onTap: () => setState(() { _activeTab = idx; _applyFilters(); }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? Colors.white : Colors.white.withOpacity(0.3)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? navyDark : Colors.white)),
      ),
    );
  }

  // ── Stat Cards ─────────────────────────────────────────────────────────────
  Widget _buildStatCards() {
    final isTab0 = _activeTab == 0;
    final cards = [
      _SC('Open',        isTab0 ? _myOpen       : _rOpen,       Icons.radio_button_unchecked, cOpen),
      _SC('In Progress', isTab0 ? _myInProgress : _rInProgress, Icons.autorenew,              cInProgress),
      _SC('Approved',    isTab0 ? _myApproved   : _rApproved,   Icons.check_circle_outline,   cApproved),
      _SC('Rejected',    isTab0 ? _myRejected   : _rRejected,   Icons.cancel_outlined,        cRejected),
      _SC('Reply',       isTab0 ? _myReply      : _rReply,      Icons.reply,                  cReply),
      _SC('Closed',      isTab0 ? _myClosed     : _rClosed,     Icons.lock_outline,           cClosed),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: cards.asMap().entries.map((e) => Padding(
              padding: EdgeInsets.only(left: e.key == 0 ? 0 : 12),
              child: _statCard(e.value),
            )).toList(),
          ),
        ),
      ),
    );
  }

  Widget _statCard(_SC d) => GestureDetector(
    onTap: () => setState(() {
      _statusFilter = d.label == 'Closed' ? 'closed' : d.label;
      _applyFilters();
    }),
    child: Container(
      width: 155,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [d.color.withOpacity(0.18), d.color.withOpacity(0.06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: d.color.withOpacity(0.25)),
        boxShadow: [BoxShadow(color: d.color.withOpacity(0.10),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(d.icon, color: d.color, size: 28),
        const SizedBox(height: 10),
        Text('${d.count}', style: TextStyle(fontSize: 32,
            fontWeight: FontWeight.bold, color: d.color)),
        const SizedBox(height: 5),
        Text(d.label, style: const TextStyle(fontSize: 13,
            color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    ),
  );

  // ── Filter Row ─────────────────────────────────────────────────────────────
  Widget _buildFilterRow() => Container(
    height: 48,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _searchBox(),
        const SizedBox(width: 8),
        _filterDropdown<String>(
          value: _statusFilter,
          items: [
            const DropdownMenuItem(value: 'all', child: Text('All Status')),
            ..._allStatuses.map((s) => DropdownMenuItem(value: s,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 7, height: 7,
                      decoration: BoxDecoration(
                          color: _sc(s), shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(_sl(s)),
                ]))),
          ],
          onChanged: (v) => setState(() { _statusFilter = v ?? 'all'; _applyFilters(); }),
        ),
        const SizedBox(width: 8),
        _filterDropdown<String>(
          value: _priorityFilter,
          items: const [
            DropdownMenuItem(value: 'all',    child: Text('All Priority')),
            DropdownMenuItem(value: 'High',   child: Text('High')),
            DropdownMenuItem(value: 'Medium', child: Text('Medium')),
            DropdownMenuItem(value: 'Low',    child: Text('Low')),
          ],
          onChanged: (v) => setState(() { _priorityFilter = v ?? 'all'; _applyFilters(); }),
        ),
        const SizedBox(width: 8),
        _datePicker('From', _dateFrom,
            (d) => setState(() { _dateFrom = d; _applyFilters(); })),
        const SizedBox(width: 8),
        _datePicker('To', _dateTo,
            (d) => setState(() { _dateTo = d; _applyFilters(); })),
        const SizedBox(width: 8),
        _actionChip(
          _isExporting
              ? const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.download, size: 16, color: Colors.white),
          'Export', navyDark, _isExporting ? null : _export,
        ),
        const SizedBox(width: 8),
        _actionChip(
          const Icon(Icons.refresh, size: 16, color: Colors.white),
          'Refresh', const Color(0xFF0EA5E9),
          _isLoading ? null : _fetchTickets,
        ),
      ]),
    ),
  );

  Widget _searchBox() => Container(
    width: 200, height: 40,
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: navyDark.withOpacity(0.15))),
    child: TextField(
      controller: _searchController,
      style: const TextStyle(fontSize: 13, color: navyDark),
      decoration: InputDecoration(
        hintText: 'Search tickets...',
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
        suffixIcon: _searchQuery.isNotEmpty
            ? GestureDetector(
                onTap: () { _searchController.clear();
                  setState(() { _searchQuery = ''; _applyFilters(); }); },
                child: const Icon(Icons.clear, size: 16,
                    color: Color(0xFF94A3B8)))
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        isDense: true,
      ),
      onChanged: (v) => setState(() { _searchQuery = v; _applyFilters(); }),
    ),
  );

  Widget _filterDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: navyDark.withOpacity(0.15))),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value, isDense: true,
        dropdownColor: Colors.white,
        icon: const Icon(Icons.keyboard_arrow_down, size: 16,
            color: Color(0xFF64748B)),
        style: const TextStyle(fontSize: 12, color: navyDark),
        items: items, onChanged: onChanged,
      ),
    ),
  );

  Widget _datePicker(String label, DateTime? date, Function(DateTime?) onPick) =>
    GestureDetector(
      onTap: () async {
        final p = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (p != null) onPick(p);
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: date != null ? navyDark.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: date != null
              ? navyDark.withOpacity(0.4) : navyDark.withOpacity(0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_today, size: 14,
              color: Color(0xFF64748B)),
          const SizedBox(width: 6),
          Text(date == null ? label : DateFormat('dd MMM').format(date),
              style: TextStyle(fontSize: 12,
                  color: date != null ? navyDark : const Color(0xFF94A3B8),
                  fontWeight: date != null ? FontWeight.w600 : FontWeight.normal)),
          if (date != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => onPick(null),
              child: const Icon(Icons.close, size: 12, color: navyDark),
            ),
          ],
        ]),
      ),
    );

  Widget _actionChip(Widget icon, String label, Color color,
      VoidCallback? onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: onTap != null ? color : color.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          icon, const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12,
              color: Colors.white, fontWeight: FontWeight.w600)),
        ]),
      ),
    );

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _loader() =>
      const Center(child: CircularProgressIndicator(color: navyDark));

  Widget _buildBody() {
    if (_filtered.isEmpty) return _emptyState();
    return Column(children: [
      Expanded(child: _buildTable()),
      _buildPagination(),
    ]);
  }

  // ==========================================================================
  // TABLE
  // ==========================================================================
  Widget _buildTable() {
    final isRaised = _activeTab == 1;
    final hScroll  = isRaised ? _hScroll2 : _hScroll;
    final vScroll  = isRaised ? _vScroll2 : _vScroll;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(children: [
          _tableHeader(isRaised),
          Expanded(child: Scrollbar(
            controller: vScroll, thumbVisibility: true,
            child: SingleChildScrollView(
              controller: vScroll,
              child: Scrollbar(
                controller: hScroll, thumbVisibility: true,
                notificationPredicate: (n) => n.depth == 1,
                child: SingleChildScrollView(
                  controller: hScroll,
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: _paged.asMap().entries
                        .map((e) => _buildRow(e.value, e.key.isEven, isRaised))
                        .toList(),
                  ),
                ),
              ),
            ),
          )),
        ]),
      ),
    );
  }

  Widget _tableHeader(bool isRaised) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Container(
      color: navyDark,
      child: Row(children: [
        _hCell('#',           60),
        _hCell('Ticket #',   130),
        _hCell('Subject',    210),
        if (isRaised) _hCell('Assigned To', 160)
        else          _hCell('Raised By',   160),
        _hCell('Priority',   100),
        _hCell('Status',     isRaised ? 120 : 155),
        _hCell('Timeline',   100),
        _hCell('Deadline',   170),
        _hCell('Created At', 130),
        _hCell('Actions',    90),
      ]),
    ),
  );

  Widget _hCell(String t, double w) => Container(
    width: w,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    child: Text(t, style: const TextStyle(color: Colors.white,
        fontSize: 13, fontWeight: FontWeight.bold)),
  );

  Widget _buildRow(Map<String, dynamic> ticket, bool even, bool isRaised) {
    final id        = ticket['_id']?.toString() ?? '';
    final idx       = (_currentPage - 1) * _perPage + _paged.indexOf(ticket) + 1;
    final ticketNum = ticket['ticket_number'] ?? 'N/A';
    final subject   = ticket['subject'] ?? 'No Subject';
    final priority  = ticket['priority'] ?? 'medium';
    final status    = ticket['status'] ?? 'Open';
    final person    = isRaised
        ? (ticket['assigned_to_name'] ?? 'Not Assigned')
        : (ticket['name'] ?? ticket['created_by_name'] ?? 'System');
    final personEmail = isRaised
        ? (ticket['assigned_email'] ?? '')
        : (ticket['creator_email'] ?? '');

    // Reply info — shown only on "My Tickets" tab when ticket was actioned
    final replyMessage = ticket['reply_message']?.toString() ?? '';
    final repliedBy    = ticket['replied_by']?.toString() ?? '';
    final hasReply     = isRaised && replyMessage.isNotEmpty &&
        ['Approved', 'Rejected', 'Reply'].contains(status);

    return GestureDetector(
      onTap: () => _showDetailOverlay(ticket, isRaised),
      child: Container(
        color: even ? Colors.white : const Color(0xFFF8FAFC),
        child: Row(children: [
          _dCell(Text('$idx', style: const TextStyle(
              fontSize: 13, color: Color(0xFF94A3B8))), 60),
          _dCell(Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [navyDark, navyMid]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(ticketNum, style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.bold, color: Colors.white)),
          ), 130),
          // Subject + reply message
          _dCell(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(subject, style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w600, color: navyDark),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              if (hasReply) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _sc(status).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _sc(status).withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (repliedBy.isNotEmpty)
                        Text('By $repliedBy', style: TextStyle(
                            fontSize: 10, fontWeight: FontWeight.bold,
                            color: _sc(status))),
                      Text(replyMessage, style: TextStyle(
                          fontSize: 11, color: Colors.grey[700], height: 1.3),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ],
          ), 210),
          _dCell(Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text(person, style: const TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600, color: navyDark),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (personEmail.isNotEmpty)
              Text(personEmail, style: const TextStyle(
                  fontSize: 11, color: Color(0xFF94A3B8)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          ]), 160),
          _dCell(_priorityBadge(priority), 100),
          _dCell(
            isRaised
                ? _statusBadge(status)
                : _statusDropdown(ticket, status),
            isRaised ? 120 : 155,
          ),
          _dCell(Text(_fmtTimeline(ticket['timeline']),
              style: const TextStyle(fontSize: 13,
                  color: Color(0xFF64748B))), 100),
          _dCell(_deadlineWidget(ticket['deadline']), 170),
          _dCell(Text(_fmtDate(ticket['created_at']),
              style: const TextStyle(fontSize: 13,
                  color: Color(0xFF64748B))), 130),
          _dCell(_actionBtn(Icons.share, accentBlue,
              () => _share(ticket)), 90),
        ]),
      ),
    );
  }

  Widget _dCell(Widget child, double w) => Container(
    width: w,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    child: child,
  );

  Widget _priorityBadge(String p) {
    final c = _pc(p);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(0.3))),
      child: Text(p.toUpperCase(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c)),
    );
  }

  Widget _statusBadge(String status) {
    final c = _sc(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(0.3))),
      child: Text(_sl(status),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c)),
    );
  }

  Widget _statusDropdown(Map<String, dynamic> ticket, String currentStatus) {
    final c = _sc(currentStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withOpacity(0.35))),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentStatus, isDense: true,
          dropdownColor: Colors.white,
          icon: Icon(Icons.keyboard_arrow_down, size: 16, color: c),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c),
          items: _allStatuses.map((s) {
            final sc = _sc(s);
            return DropdownMenuItem<String>(value: s,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: sc, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(_sl(s), style: TextStyle(fontSize: 12,
                    color: sc, fontWeight: FontWeight.w600)),
              ]),
            );
          }).toList(),
          onChanged: (newStatus) {
            if (newStatus != null && newStatus != currentStatus) {
              _handleStatusChange(ticket, newStatus);
            }
          },
        ),
      ),
    );
  }

  Widget _deadlineWidget(dynamic deadline) {
    if (deadline == null) return const Text('No deadline',
        style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)));
    final d = DateTime.tryParse(deadline.toString());
    if (d == null) return const Text('N/A');
    final diff    = d.difference(DateTime.now());
    final overdue = diff.isNegative;
    final warn    = !overdue && diff.inHours < 4;
    final color   = overdue ? cOpen : warn ? cInProgress : cApproved;
    final label   = overdue
        ? 'Overdue ${diff.abs().inDays}d'
        : diff.inDays > 0 ? '${diff.inDays}d left' : '${diff.inHours}h left';
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(overdue ? Icons.warning_amber_rounded : Icons.access_time,
              size: 11, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11,
              fontWeight: FontWeight.bold, color: color)),
        ]),
        Text(DateFormat('dd MMM, HH:mm').format(d.toLocal()),
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.75))),
      ]),
    );
    return overdue ? FadeTransition(opacity: _pulseAnim, child: w) : w;
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Icon(icon, size: 15, color: color),
      ),
    );

  // ── Pagination ─────────────────────────────────────────────────────────────
  Widget _buildPagination() {
    if (_totalPages <= 1) return const SizedBox(height: 10);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _pgBtn(Icons.chevron_left,
            _currentPage > 1 ? () => setState(() => _currentPage--) : null),
        const SizedBox(width: 6),
        ..._pageNums(),
        const SizedBox(width: 6),
        _pgBtn(Icons.chevron_right,
            _currentPage < _totalPages
                ? () => setState(() => _currentPage++) : null),
      ]),
    );
  }

  List<Widget> _pageNums() {
    final pages = <int>{1, _totalPages};
    for (int i = _currentPage - 1; i <= _currentPage + 1; i++) {
      if (i > 0 && i <= _totalPages) pages.add(i);
    }
    final sorted = pages.toList()..sort();
    final ws = <Widget>[];
    int? prev;
    for (final p in sorted) {
      if (prev != null && p - prev > 1) {
        ws.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 3),
            child: Text('…', style: TextStyle(color: Color(0xFF94A3B8)))));
      }
      final active = p == _currentPage;
      ws.add(GestureDetector(
        onTap: () => setState(() => _currentPage = p),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: active ? navyDark : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? navyDark : const Color(0xFFE2E8F0)),
          ),
          alignment: Alignment.center,
          child: Text('$p', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : navyDark)),
        ),
      ));
      prev = p;
    }
    return ws;
  }

  Widget _pgBtn(IconData icon, VoidCallback? onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: onTap != null ? navyDark : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 17,
          color: onTap != null ? Colors.white : const Color(0xFFCBD5E1)),
    ),
  );

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.inbox_outlined, size: 64, color: navyDark.withOpacity(0.18)),
      const SizedBox(height: 12),
      Text(_activeTab == 0 ? 'No tickets assigned to you'
          : 'No tickets raised by you',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
              color: Color(0xFF64748B))),
      const SizedBox(height: 6),
      const Text('Try adjusting your filters',
          style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
    ]),
  );

  // ==========================================================================
  // DETAIL OVERLAY
  // ==========================================================================
  void _showDetailOverlay(Map<String, dynamic> ticket, bool isRaised) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 820),
          decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30, offset: const Offset(0, 12))]),
          child: Column(children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [navyDark, navyMid, navyLight],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight),
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(ticket['ticket_number'] ?? 'N/A',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 13, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Ticket Details',
                    style: TextStyle(color: Colors.white,
                        fontSize: 17, fontWeight: FontWeight.bold))),
                _oBtn(Icons.share, () { Navigator.pop(context); _share(ticket); }),
                const SizedBox(width: 6),
                _oBtn(Icons.open_in_full, () async {
                  Navigator.pop(context);
                  final updated = await Navigator.push(context,
                      MaterialPageRoute(builder: (_) =>
                          TicketDetailScreen(ticket: ticket)));
                  if (updated == true) _fetchTickets();
                }),
                const SizedBox(width: 6),
                _oBtn(Icons.close, () => Navigator.pop(context)),
              ]),
            ),

            // Content
            Expanded(child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Subject + badges
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Text(ticket['subject'] ?? 'No Subject',
                      style: const TextStyle(fontSize: 16,
                          fontWeight: FontWeight.bold, color: navyDark))),
                  const SizedBox(width: 10),
                  _sBadgeLg(ticket['status'] ?? 'Open'),
                  const SizedBox(width: 6),
                  _pBadgeLg(ticket['priority'] ?? 'medium'),
                ]),
                const SizedBox(height: 14),

                // Message
                _oSec('Message', Icons.message_outlined, accentBlue,
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: SelectableText(ticket['message'] ?? 'No message',
                        style: const TextStyle(fontSize: 13,
                            color: navyDark, height: 1.6)),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Response Section (shown when reply_message exists) ──────
                if (ticket['reply_message'] != null &&
                    ticket['reply_message'].toString().isNotEmpty) ...[
                  _oSec(
                    'Response',
                    _statusIcon(ticket['status'] ?? ''),
                    _sc(ticket['status'] ?? ''),
                    _responseCard(ticket),
                  ),
                  const SizedBox(height: 14),
                ],

                // People row
                Row(children: [
                  Expanded(child: _oSec('Raised By',
                      Icons.person_outline, cInProgress,
                    _personCard(
                      name: ticket['name'] ?? ticket['created_by_name'] ?? 'System',
                      email: ticket['creator_email'] ?? '',
                      tag: ticket['source'] == 'crm' ? 'CRM' : 'Manual',
                      tagColor: cReply,
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _oSec('Assigned To',
                      Icons.person_pin_outlined, cApproved,
                    _personCard(
                      name: ticket['assigned_to_name'] ?? 'Not Assigned',
                      email: ticket['assigned_email'] ?? '',
                    ),
                  )),
                ]),
                const SizedBox(height: 14),

                // Dates
                Row(children: [
                  Expanded(child: _iTile('Created At',
                      _fmtDateTime(ticket['created_at']),
                      Icons.add_circle_outline, cApproved)),
                  const SizedBox(width: 8),
                  Expanded(child: _iTile('Deadline',
                      _fmtDateTime(ticket['deadline']),
                      Icons.alarm, cOpen)),
                  const SizedBox(width: 8),
                  Expanded(child: _iTile('Updated At',
                      _fmtDateTime(ticket['updated_at']),
                      Icons.update, cInProgress)),
                ]),
                const SizedBox(height: 14),

                Row(children: [
                  Expanded(child: _iTile('Timeline',
                      _fmtTimeline(ticket['timeline']),
                      Icons.timer_outlined, cReply)),
                  const SizedBox(width: 8),
                  Expanded(child: _iTile('Source',
                      ticket['source'] == 'crm' ? 'CRM System' : 'Manual',
                      Icons.source_outlined, cClosed)),
                  const SizedBox(width: 8),
                  Expanded(child: _iTile('Attachment',
                      ticket['attachment'] ?? 'None',
                      Icons.attach_file, const Color(0xFF0EA5E9))),
                ]),

                // Status update buttons — My Tickets tab only
                if (!isRaised) ...[
                  const SizedBox(height: 18),
                  const Text('Update Status', style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.bold, color: navyDark)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8,
                      children: _allStatuses.map((s) {
                    final isActive = ticket['status'] == s;
                    final sc = _sc(s);
                    return GestureDetector(
                      onTap: isActive ? null : () {
                        Navigator.pop(context);
                        _handleStatusChange(ticket, s);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isActive ? sc : sc.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sc,
                              width: isActive ? 1.5 : 1),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(isActive
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                              size: 14,
                              color: isActive ? Colors.white : sc),
                          const SizedBox(width: 5),
                          Text(_sl(s), style: TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.white : sc)),
                        ]),
                      ),
                    );
                  }).toList()),
                ] else ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: cInProgress.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cInProgress.withOpacity(0.2))),
                    child: Row(children: [
                      Icon(Icons.info_outline, size: 16, color: cInProgress),
                      const SizedBox(width: 8),
                      const Expanded(child: Text(
                          'This is a read-only view of tickets you raised.',
                          style: TextStyle(fontSize: 12,
                              color: Color(0xFF64748B)))),
                    ]),
                  ),
                ],
              ]),
            )),
          ]),
        ),
      ),
    );
  }

  /// Response card — shown in overlay when reply_message exists
  Widget _responseCard(Map<String, dynamic> ticket) {
    final status     = ticket['status'] ?? '';
    final color      = _sc(status);
    final repliedBy  = ticket['replied_by']?.toString() ?? 'Staff';
    final repliedAt  = _fmtDateTime(ticket['replied_at']);
    final replySubj  = ticket['reply_subject']?.toString() ?? '';
    final replyMsg   = ticket['reply_message']?.toString() ?? '';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Response header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(11),
                topRight: Radius.circular(11)),
          ),
          child: Row(children: [
            Icon(_statusIcon(status), size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(
              replySubj.isNotEmpty ? replySubj : '${_sl(status)} Response',
              style: TextStyle(fontSize: 13,
                  fontWeight: FontWeight.bold, color: color),
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(_sl(status), style: TextStyle(fontSize: 10,
                  fontWeight: FontWeight.bold, color: color)),
            ),
          ]),
        ),
        // Reply body
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(replyMsg,
                style: const TextStyle(fontSize: 13,
                    color: navyDark, height: 1.6)),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.person_outline, size: 13,
                  color: color.withOpacity(0.7)),
              const SizedBox(width: 4),
              Text(repliedBy, style: TextStyle(fontSize: 11,
                  color: color, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(Icons.access_time, size: 12,
                  color: const Color(0xFF94A3B8)),
              const SizedBox(width: 4),
              Text(repliedAt, style: const TextStyle(
                  fontSize: 11, color: Color(0xFF94A3B8))),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _oBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: Colors.white, size: 18),
    ),
  );

  Widget _oSec(String title, IconData icon, Color color, Widget child) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(title, style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.bold, color: color)),
      ]),
      const SizedBox(height: 7), child,
    ]);

  Widget _personCard({required String name, required String email,
      String? tag, Color? tagColor}) =>
    Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(children: [
        CircleAvatar(
          radius: 17,
          backgroundColor: navyDark.withOpacity(0.12),
          child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(color: navyDark,
                  fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        const SizedBox(width: 9),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: navyDark),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (tag != null) Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                  color: (tagColor ?? cReply).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(tag, style: TextStyle(fontSize: 9,
                  color: tagColor ?? cReply, fontWeight: FontWeight.bold)),
            ),
          ]),
          if (email.isNotEmpty)
            Text(email, style: const TextStyle(
                fontSize: 10, color: Color(0xFF94A3B8)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
      ]),
    );

  Widget _iTile(String label, String value, IconData icon, Color color) =>
    Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10,
              color: color.withOpacity(0.8), fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 11,
              color: navyDark, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );

  Widget _sBadgeLg(String s) {
    final c = _sc(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withOpacity(0.3))),
      child: Text(_sl(s),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c)),
    );
  }

  Widget _pBadgeLg(String p) {
    final c = _pc(p);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.withOpacity(0.3))),
      child: Text(p.toUpperCase(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c)),
    );
  }
}

class _SC {
  final String label; final int count;
  final IconData icon; final Color color;
  const _SC(this.label, this.count, this.icon, this.color);
}