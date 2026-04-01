// ============================================================================
// MANUAL JOURNAL DETAIL PAGE
// ============================================================================
// File: lib/screens/billing/pages/manual_journal_detail.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/manual_journal_service.dart';
import '../../../../app/config/api_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'new_manual_journal.dart';

const Color _kNavyDark  = Color(0xFF0F172A);
const Color _kNavy      = Color(0xFF1E3A5F);
const Color _kAccent    = Color(0xFF2563EB);

class ManualJournalDetailPage extends StatefulWidget {
  final String journalId;
  const ManualJournalDetailPage({Key? key, required this.journalId}) : super(key: key);

  @override
  State<ManualJournalDetailPage> createState() => _ManualJournalDetailPageState();
}

class _ManualJournalDetailPageState extends State<ManualJournalDetailPage> {
  ManualJournal? _journal;
  bool _isLoading = true;
  String? _error;
  bool _isActing  = false;

  // For apply credits dialog
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _bills    = [];
  bool _creditsLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final j = await ManualJournalService.getJournal(widget.journalId);
      setState(() { _journal = j; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
  void _showSuccess(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _publish() async {
    if (_journal == null) return;
    final diff = _journal!.difference.abs();
    if (diff > 0.01) {
      _showError('Cannot publish: Difference ₹${_journal!.difference.toStringAsFixed(2)} must be ₹0.00');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Publish Journal'),
        content: Text('Publish ${_journal!.journalNumber}?\n\nThis will post all ${_journal!.lineItems.length} entries to the Chart of Accounts immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isActing = true);
    try {
      final j = await ManualJournalService.publishJournal(widget.journalId);
      setState(() { _journal = j; _isActing = false; });
      _showSuccess('${j.journalNumber} published and posted to COA ✅');
    } catch (e) {
      setState(() => _isActing = false);
      _showError(e.toString());
    }
  }

  Future<void> _void() async {
    if (_journal == null) return;
    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          const Icon(Icons.warning_amber, color: Colors.red),
          const SizedBox(width: 8),
          const Text('Void Journal'),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Void ${_journal!.journalNumber}?'),
          const SizedBox(height: 6),
          if (_journal!.status == 'Published')
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!)),
              child: const Text('⚠️ Since this journal is Published, all COA entries will be reversed.',
                  style: TextStyle(fontSize: 13)),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            decoration: const InputDecoration(
              labelText: 'Reason for voiding (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Void Journal'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isActing = true);
    try {
      final j = await ManualJournalService.voidJournal(widget.journalId, reason: reasonCtrl.text);
      setState(() { _journal = j; _isActing = false; });
      _showSuccess('${j.journalNumber} voided. COA entries reversed ↩️');
    } catch (e) {
      setState(() => _isActing = false);
      _showError(e.toString());
    }
  }

  Future<void> _clone() async {
    setState(() => _isActing = true);
    try {
      final j = await ManualJournalService.cloneJournal(widget.journalId);
      setState(() => _isActing = false);
      _showSuccess('Cloned as ${j.journalNumber} 📋');
      // Navigate to edit the cloned journal
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => NewManualJournalPage(journalId: j.id),
        )).then((_) => _load());
      }
    } catch (e) {
      setState(() => _isActing = false);
      _showError(e.toString());
    }
  }

  Future<void> _downloadPdf() async {
    final url = await ManualJournalService.getPdfUrl(widget.journalId);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showError('Could not open PDF viewer');
    }
  }

  Future<void> _showApplyCreditsDialog() async {
    if (_journal == null) return;
    setState(() => _creditsLoading = true);

    // Load invoices and bills
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final headers = {'Authorization': 'Bearer $token', 'Accept': 'application/json'};

      final results = await Future.wait([
        http.get(Uri.parse('${ApiConfig.baseUrl}/api/finance/invoices?status=UNPAID&limit=100'), headers: headers),
        http.get(Uri.parse('${ApiConfig.baseUrl}/api/finance/bills?status=OPEN&limit=100'), headers: headers),
      ]);

      final invData  = jsonDecode(results[0].body);
      final billData = jsonDecode(results[1].body);

      _invoices = List<Map<String, dynamic>>.from(invData['data'] ?? []);
      _bills    = List<Map<String, dynamic>>.from(billData['data'] ?? []);
    } catch (_) {}

    setState(() => _creditsLoading = false);

    if (!mounted) return;

    // Determine which account types are in line items for guidance
    final hasAR = _journal!.lineItems.any((l) => l.accountName.toLowerCase().contains('receivable'));
    final hasAP = _journal!.lineItems.any((l) => l.accountName.toLowerCase().contains('payable'));

    showDialog(
      context: context,
      builder: (_) => _ApplyCreditsDialog(
        journal: _journal!,
        invoices: _invoices,
        bills: _bills,
        hasAR: hasAR,
        hasAP: hasAP,
        onApply: (type, refId, refNumber, amount) async {
          try {
            final j = await ManualJournalService.applyCredits(
              widget.journalId,
              type: type,
              referenceId: refId,
              referenceNumber: refNumber,
              amount: amount,
            );
            setState(() => _journal = j);
            if (mounted) Navigator.pop(context);
            _showSuccess('Credit applied to $type $refNumber ✅');
          } catch (e) {
            _showError(e.toString());
          }
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _load, child: const Text('Retry')),
                ]))
              : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final j = _journal;
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_kNavyDark, _kNavy, _kAccent],
              begin: Alignment.centerLeft, end: Alignment.centerRight),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(j?.journalNumber ?? 'Journal Detail',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            if (j != null)
              Text(DateFormat('dd MMM yyyy').format(j.date),
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
          actions: j == null ? [] : [
            if (j.status == 'Draft') ...[
              _appBarBtn(Icons.edit_outlined, 'Edit', Colors.white70, () async {
                final r = await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => NewManualJournalPage(journalId: widget.journalId),
                ));
                if (r == true && mounted) _load();
              }),
              const SizedBox(width: 4),
              _appBarBtn(Icons.publish, 'Publish', Colors.green[300]!, _publish),
            ],
            if (j.status == 'Published') ...[
              _appBarBtn(Icons.link, 'Apply Credits', Colors.blue[200]!, _showApplyCreditsDialog),
            ],
            if (j.status != 'Void')
              _appBarBtn(Icons.copy_outlined, 'Clone', Colors.white70, _clone),
            _appBarBtn(Icons.picture_as_pdf_outlined, 'PDF', Colors.white70, _downloadPdf),
            if (j.status != 'Void')
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (v) { if (v == 'void') _void(); },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'void',
                      child: Text('Void Journal', style: TextStyle(color: Colors.red))),
                ],
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  Widget _appBarBtn(IconData icon, String tooltip, Color color, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: IconButton(
          icon: Icon(icon, color: color, size: 20),
          onPressed: _isActing ? null : onTap,
        ),
      );

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    final j = _journal!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 800;
        if (isWide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Column(children: [
              _buildInfoCard(j),
              const SizedBox(height: 16),
              _buildLineItemsCard(j),
              const SizedBox(height: 16),
              if (j.appliedCredits.isNotEmpty) _buildAppliedCreditsCard(j),
              if (j.attachments.isNotEmpty) ...[const SizedBox(height: 16), _buildAttachmentsCard(j)],
            ])),
            const SizedBox(width: 16),
            SizedBox(width: 280, child: Column(children: [
              _buildStatusCard(j),
              const SizedBox(height: 16),
              _buildTotalsCard(j),
              const SizedBox(height: 16),
              _buildActionsCard(j),
            ])),
          ]);
        }
        return Column(children: [
          _buildStatusCard(j),
          const SizedBox(height: 12),
          _buildInfoCard(j),
          const SizedBox(height: 12),
          _buildTotalsCard(j),
          const SizedBox(height: 12),
          _buildLineItemsCard(j),
          const SizedBox(height: 12),
          if (j.appliedCredits.isNotEmpty) ...[_buildAppliedCreditsCard(j), const SizedBox(height: 12)],
          if (j.attachments.isNotEmpty) ...[_buildAttachmentsCard(j), const SizedBox(height: 12)],
          _buildActionsCard(j),
        ]);
      }),
    );
  }

  // ── Info Card ──────────────────────────────────────────────────────────────

  Widget _buildInfoCard(ManualJournal j) => _card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Journal Information', Icons.info_outline),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (_, cs) {
        final isWide = cs.maxWidth > 500;
        final items = [
          ('Journal #',         j.journalNumber),
          ('Date',              DateFormat('dd MMM yyyy').format(j.date)),
          ('Reference #',       j.referenceNumber.isEmpty ? '-' : j.referenceNumber),
          ('Reporting Method',  j.reportingMethod),
          ('Currency',          j.currency),
          ('Notes',             j.notes.isEmpty ? '-' : j.notes),
          if (j.clonedFromNumber != null) ('Cloned From', j.clonedFromNumber!),
          if (j.publishedAt != null) ('Published On', DateFormat('dd MMM yyyy HH:mm').format(j.publishedAt!)),
          if (j.voidedAt != null)    ('Voided On',    DateFormat('dd MMM yyyy HH:mm').format(j.voidedAt!)),
          if (j.voidReason != null && j.voidReason!.isNotEmpty) ('Void Reason', j.voidReason!),
        ];
        return Wrap(
          spacing: 24,
          runSpacing: 12,
          children: items.map((item) => SizedBox(
            width: isWide ? 200 : double.infinity,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.$1, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500)),
              const SizedBox(height: 3),
              Text(item.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _kNavyDark)),
            ]),
          )).toList(),
        );
      }),
    ]),
  );

  // ── Status Card ────────────────────────────────────────────────────────────

  Widget _buildStatusCard(ManualJournal j) {
    final statusData = {
      'Draft':     [Colors.orange[100]!, Colors.orange[800]!, Icons.edit_note],
      'Published': [Colors.green[100]!,  Colors.green[800]!,  Icons.check_circle],
      'Void':      [Colors.red[100]!,    Colors.red[800]!,    Icons.cancel],
    };
    final d = statusData[j.status] ?? [Colors.grey[100]!, Colors.grey[800]!, Icons.help];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (d[0] as Color),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: (d[1] as Color).withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(d[2] as IconData, color: d[1] as Color, size: 28),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Status', style: TextStyle(fontSize: 12, color: (d[1] as Color).withOpacity(0.8))),
          Text(j.status, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: d[1] as Color)),
        ]),
        const Spacer(),
        if (j.status == 'Draft')
          ElevatedButton.icon(
            onPressed: _isActing ? null : _publish,
            icon: const Icon(Icons.publish, size: 16),
            label: const Text('Publish Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        if (j.status == 'Published')
          ElevatedButton.icon(
            onPressed: _isActing ? null : _showApplyCreditsDialog,
            icon: const Icon(Icons.link, size: 16),
            label: const Text('Apply Credits'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kAccent, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
      ]),
    );
  }

  // ── Totals Card ────────────────────────────────────────────────────────────

  Widget _buildTotalsCard(ManualJournal j) {
    final isBalanced = j.difference.abs() <= 0.01;
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Totals', Icons.calculate),
      const SizedBox(height: 14),
      _totalRow('Sub Total', j.totalDebit, j.totalCredit),
      const Divider(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isBalanced ? Colors.green[50] : Colors.red[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isBalanced ? Colors.green[300]! : Colors.red[300]!),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(isBalanced ? Icons.check_circle : Icons.error,
                color: isBalanced ? Colors.green : Colors.red, size: 18),
            const SizedBox(width: 8),
            Text('Total (₹)', style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14,
              color: isBalanced ? Colors.green[700] : Colors.red[700],
            )),
          ]),
          Row(children: [
            Text('₹${j.totalDebit.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 16),
            Text('₹${j.totalCredit.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold, fontSize: 14)),
          ]),
        ]),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Difference', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold,
          color: isBalanced ? Colors.green[700] : Colors.red[700],
        )),
        Text('₹${j.difference.toStringAsFixed(2)}', style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.bold,
          color: isBalanced ? Colors.green[700] : Colors.red[700],
        )),
      ]),
    ]));
  }

  Widget _totalRow(String label, double debit, double credit) => Row(
    children: [
      Expanded(child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13))),
      Text('₹${debit.toStringAsFixed(2)}',
          style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.w600, fontSize: 13)),
      const SizedBox(width: 16),
      Text('₹${credit.toStringAsFixed(2)}',
          style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600, fontSize: 13)),
    ],
  );

  // ── Line Items Card ────────────────────────────────────────────────────────

  Widget _buildLineItemsCard(ManualJournal j) => _card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Line Items (${j.lineItems.length})', Icons.list_alt),
      const SizedBox(height: 12),
      // Column headers
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_kNavyDark, _kNavy]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(children: [
          Expanded(flex: 3, child: Text('ACCOUNT',     style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          SizedBox(width: 8),
          Expanded(flex: 2, child: Text('DESCRIPTION', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          SizedBox(width: 8),
          Expanded(flex: 2, child: Text('CONTACT',     style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
          SizedBox(width: 8),
          SizedBox(width: 100, child: Text('DEBIT',    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
          SizedBox(width: 8),
          SizedBox(width: 100, child: Text('CREDIT',   style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
        ]),
      ),
      const SizedBox(height: 4),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 600),
          child: Column(
            children: j.lineItems.asMap().entries.map((e) {
              final idx  = e.key;
              final line = e.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: idx % 2 == 0 ? Colors.white : Colors.grey[50],
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(children: [
                  Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(line.accountName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    if (line.accountCode.isNotEmpty)
                      Text(line.accountCode, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ])),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: Text(line.description.isEmpty ? '-' : line.description,
                      style: const TextStyle(fontSize: 13))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: line.contactName != null
                      ? Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: line.contactType == 'vendor' ? Colors.orange[50] : Colors.blue[50],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              line.contactType == 'vendor' ? 'V' : 'C',
                              style: TextStyle(
                                fontSize: 10,
                                color: line.contactType == 'vendor' ? Colors.orange[700] : Colors.blue[700],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(child: Text(line.contactName!, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                        ])
                      : Text('-', style: TextStyle(color: Colors.grey[400], fontSize: 13))),
                  const SizedBox(width: 8),
                  SizedBox(width: 100, child: Text(
                    line.debit > 0 ? '₹${line.debit.toStringAsFixed(2)}' : '-',
                    style: TextStyle(
                      color: line.debit > 0 ? Colors.red[700] : Colors.grey[400],
                      fontWeight: line.debit > 0 ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.right,
                  )),
                  const SizedBox(width: 8),
                  SizedBox(width: 100, child: Text(
                    line.credit > 0 ? '₹${line.credit.toStringAsFixed(2)}' : '-',
                    style: TextStyle(
                      color: line.credit > 0 ? Colors.green[700] : Colors.grey[400],
                      fontWeight: line.credit > 0 ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.right,
                  )),
                ]),
              );
            }).toList(),
          ),
        ),
      ),
    ]),
  );

  // ── Applied Credits Card ───────────────────────────────────────────────────

  Widget _buildAppliedCreditsCard(ManualJournal j) => _card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Applied Credits (${j.appliedCredits.length})', Icons.link),
      const SizedBox(height: 12),
      ...j.appliedCredits.map((c) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(children: [
          Icon(c.type == 'Invoice' ? Icons.receipt_long : Icons.receipt,
              color: Colors.blue[700], size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c.type} ${c.referenceNumber}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            Text('Applied: ${DateFormat('dd MMM yyyy').format(c.appliedDate)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ])),
          Text('₹${c.amount.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[700], fontSize: 15)),
        ]),
      )).toList(),
    ]),
  );

  // ── Attachments Card ───────────────────────────────────────────────────────

  Widget _buildAttachmentsCard(ManualJournal j) => _card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Attachments (${j.attachments.length}/5)', Icons.attach_file),
      const SizedBox(height: 12),
      ...j.attachments.map((a) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.insert_drive_file_outlined, color: _kAccent),
        title: Text(a.filename, style: const TextStyle(fontSize: 13)),
        subtitle: Text('${(a.size / 1024).toStringAsFixed(1)} KB · ${DateFormat('dd MMM yyyy').format(a.uploadedAt)}',
            style: const TextStyle(fontSize: 11)),
      )).toList(),
    ]),
  );

  // ── Actions Card ───────────────────────────────────────────────────────────

  Widget _buildActionsCard(ManualJournal j) => _card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('Actions', Icons.touch_app),
      const SizedBox(height: 14),
      if (j.status == 'Draft') ...[
        _actionBtn(Icons.edit_outlined, 'Edit Journal', Colors.orange, () async {
          final r = await Navigator.push(context,
              MaterialPageRoute(builder: (_) => NewManualJournalPage(journalId: widget.journalId)));
          if (r == true && mounted) _load();
        }),
        const SizedBox(height: 8),
        _actionBtn(Icons.publish, 'Publish to COA', Colors.green, _publish),
      ],
      if (j.status == 'Published') ...[
        _actionBtn(Icons.link, 'Apply Credits', _kAccent, _showApplyCreditsDialog),
        const SizedBox(height: 8),
      ],
      _actionBtn(Icons.copy_outlined, 'Clone Journal', Colors.purple, _clone),
      const SizedBox(height: 8),
      _actionBtn(Icons.picture_as_pdf_outlined, 'Download PDF', _kNavy, _downloadPdf),
      if (j.status != 'Void') ...[
        const SizedBox(height: 8),
        _actionBtn(Icons.block, 'Void Journal', Colors.red, _void),
      ],
    ]),
  );

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: _isActing ? null : onTap,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.centerLeft,
        ),
      ));

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3))],
    ),
    child: child,
  );

  Widget _sectionTitle(String title, IconData icon) => Row(children: [
    Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_kNavyDark, _kNavy]),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: Colors.white, size: 16),
    ),
    const SizedBox(width: 10),
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kNavyDark)),
  ]);
}

// ============================================================================
// APPLY CREDITS DIALOG
// ============================================================================

class _ApplyCreditsDialog extends StatefulWidget {
  final ManualJournal journal;
  final List<Map<String, dynamic>> invoices;
  final List<Map<String, dynamic>> bills;
  final bool hasAR;
  final bool hasAP;
  final Function(String type, String refId, String refNumber, double amount) onApply;

  const _ApplyCreditsDialog({
    required this.journal,
    required this.invoices,
    required this.bills,
    required this.hasAR,
    required this.hasAP,
    required this.onApply,
  });

  @override
  State<_ApplyCreditsDialog> createState() => _ApplyCreditsDialogState();
}

class _ApplyCreditsDialogState extends State<_ApplyCreditsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _amountCtrl = TextEditingController();
  String? _selectedId;
  String? _selectedNumber;
  double _selectedDue = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this,
        initialIndex: widget.hasAR ? 0 : (widget.hasAP ? 1 : 0));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_kNavyDark, _kNavy]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              const Icon(Icons.link, color: Colors.white),
              const SizedBox(width: 10),
              const Expanded(child: Text('Apply Credits',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          // Guidance
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Text(
              widget.hasAR
                  ? '📘 Journal has Accounts Receivable — apply as Customer Credit against invoices'
                  : widget.hasAP
                      ? '📗 Journal has Accounts Payable — apply as Vendor Credit against bills'
                      : '📎 Select the invoice or bill to apply this journal credit against',
              style: TextStyle(fontSize: 12, color: Colors.blue[800]),
            ),
          ),
          // Tabs
          TabBar(
            controller: _tabCtrl,
            labelColor: _kAccent,
            unselectedLabelColor: Colors.grey,
            indicatorColor: _kAccent,
            tabs: const [
              Tab(text: 'Invoices (Unpaid)'),
              Tab(text: 'Bills (Open)'),
            ],
          ),
          Expanded(child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildList(widget.invoices, 'Invoice', 'invoiceNumber', 'amountDue', 'customerName'),
              _buildList(widget.bills,    'Bill',    'billNumber',    'amountDue', 'vendorName'),
            ],
          )),
          // Amount input + Apply
          if (_selectedId != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Selected: $_selectedNumber  (Due: ₹${_selectedDue.toStringAsFixed(2)})',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount to Apply (₹)',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixText: '₹',
                    ),
                  )),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      final amt = double.tryParse(_amountCtrl.text);
                      if (amt == null || amt <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid amount')));
                        return;
                      }
                      final type = _tabCtrl.index == 0 ? 'Invoice' : 'Bill';
                      widget.onApply(type, _selectedId!, _selectedNumber!, amt);
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Apply'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, foregroundColor: Colors.white,
                    ),
                  ),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _buildList(
    List<Map<String, dynamic>> items,
    String type,
    String numberKey,
    String dueKey,
    String nameKey,
  ) {
    if (items.isEmpty) {
      return Center(child: Text('No ${type}s found', style: TextStyle(color: Colors.grey[600])));
    }
    // Filter out already applied
    final applied = widget.journal.appliedCredits.map((c) => c.referenceId).toSet();
    final filtered = items.where((i) => !applied.contains(i['_id'] ?? '')).toList();

    if (filtered.isEmpty) {
      return const Center(child: Text('All credits already applied'));
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final item = filtered[i];
        final id     = item['_id']?.toString() ?? '';
        final number = item[numberKey]?.toString() ?? '';
        final due    = (item[dueKey] ?? 0).toDouble();
        final name   = item[nameKey]?.toString() ?? '';
        final isSelected = _selectedId == id;

        return ListTile(
          selected: isSelected,
          selectedTileColor: _kAccent.withOpacity(0.08),
          leading: CircleAvatar(
            backgroundColor: isSelected ? _kAccent : Colors.grey[200],
            radius: 18,
            child: Icon(
              type == 'Invoice' ? Icons.receipt_long : Icons.receipt,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 16,
            ),
          ),
          title: Text(number, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(name),
          trailing: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Due', style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            Text('₹${due.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[700], fontSize: 13)),
          ]),
          onTap: () {
            setState(() {
              _selectedId     = id;
              _selectedNumber = number;
              _selectedDue    = due;
              _amountCtrl.text = due.toStringAsFixed(2);
            });
          },
        );
      },
    );
  }
}