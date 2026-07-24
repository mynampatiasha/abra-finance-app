import 'package:abra_finance/core/utils/app_snackbar.dart';
// ============================================================================
// REMINDER SETTINGS PAGE
// ============================================================================
// File: lib/screens/billing/reminder_settings_page.dart
//
// FEATURES:
// ✅ 3-breakpoint responsive (Desktop ≥1100 / Tablet 700-1100 / Mobile <700)
// ✅ Preview Overdue Email button — like new_invoice.dart Preview Email
// ✅ Preview Pre-Due Email button
// ✅ Preview dialog shows full rendered HTML in WebView
// ✅ Test email button sends to specified address
// ✅ Channel selection — Email / WhatsApp / Both
// ✅ Schedule — frequency, time, grace period, max cap, pre-due days
// ✅ Blackout days and hours
// ✅ CC/BCC email management
// ✅ Optional custom template override fields
// ✅ WhatsApp Meta credentials
// ✅ ReminderLogWidget (reusable — used in invoice_detail_page.dart)
// ✅ Same design language as invoices_list_page.dart + invoice_detail_page.dart
// ============================================================================

import '../widgets/web_utils_stub.dart'
    if (dart.library.html) '../widgets/web_utils_web.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/services/invoice_service.dart';
import '../../../../core/services/api_service.dart';
import '../app_top_bar.dart';

// ── Brand palette (matches invoices_list_page.dart) ──────────────────────────
const Color _navy = Color(0xFF0D1B3E);
const Color _navyM = Color(0xFF1A3A6B);
const Color _navyL = Color(0xFF2463AE);
const Color _accent = Color(0xFF3D8EFF);
const Color _green = Color(0xFF27AE60);
const Color _red = Color(0xFFE74C3C);
const Color _orange = Color(0xFFE67E22);
const Color _blue = Color(0xFF2980B9);

// ── iframe registry (web only) ────────────────────────────────────────────────
int _iframeCounter = 0;

String _registerHtmlIframe(String htmlContent) {
  if (!kIsWeb) return '';
  final id = 'reminder-email-iframe-${_iframeCounter++}';
  final blob = html.Blob([htmlContent], 'text/html');
  final url = html.Url.createObjectUrl(blob);
  // ignore: undefined_prefixed_name
  html.platformViewRegistry.registerViewFactory(id, (_) {
    final iframe = html.IFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    return iframe;
  });
  return id;
}

// ============================================================================
// REMINDER SERVICE
// ============================================================================

class ReminderService {
  static final ApiService _api = ApiService();
  static const String _base = '/api/finance/reminder-settings';
  static const String _invoicesBase = '/api/finance/invoices';

  static Future<Map<String, dynamic>> getSettings() async {
    final data = await _api.get(_base);
    return Map<String, dynamic>.from(data['data'] ?? {});
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    await _api.put(_base, body: settings);
  }

  /// Returns { subject, html, type } for preview dialog
  static Future<Map<String, dynamic>> getPreview(String type) async {
    final data = await _api.get('$_base/preview/$type');
    return Map<String, dynamic>.from(data['data'] ?? {});
  }

  static Future<void> sendTestEmail(String testEmail, String type) async {
    await _api.post('$_base/test-email', body: {
      'testEmail': testEmail,
      'type': type,
    });
  }

  /// Returns { type, message, testPhone, invoiceNumber, customerName }
  static Future<Map<String, dynamic>> getWhatsAppPreview(String type) async {
    final data = await _api.get('$_base/whatsapp-preview/$type');
    return Map<String, dynamic>.from(data['data'] ?? {});
  }

  static Future<void> saveWhatsAppTemplates(
      Map<String, dynamic> templates) async {
    await _api.put(_base, body: templates);
  }

  static Future<List<Map<String, dynamic>>> getReminderLog(
      String invoiceId) async {
    final data = await _api.get('$_invoicesBase/$invoiceId/reminder-log');
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
  }

  /// Fetches approved WhatsApp templates from the WABA via backend
  static Future<List<Map<String, dynamic>>> getWhatsAppTemplates() async {
    final data = await _api.get('/api/finance/auth/whatsapp-templates');
    return List<Map<String, dynamic>>.from(data['data']?['templates'] ?? []);
  }

  static Future<void> pauseReminder(String invoiceId) async {
    await _api.patch('$_invoicesBase/$invoiceId/pause-reminder');
  }

  static Future<void> resumeReminder(String invoiceId) async {
    await _api.patch('$_invoicesBase/$invoiceId/resume-reminder');
  }
}

// ============================================================================
// REMINDER LOG WIDGET — reusable, shown in invoice_detail_page.dart
// ============================================================================

class ReminderLogWidget extends StatefulWidget {
  final String invoiceId;
  final bool reminderPaused;
  final int reminderCount;
  final VoidCallback? onStatusChanged;

  const ReminderLogWidget({
    Key? key,
    required this.invoiceId,
    required this.reminderPaused,
    required this.reminderCount,
    this.onStatusChanged,
  }) : super(key: key);

  @override
  State<ReminderLogWidget> createState() => _ReminderLogWidgetState();
}

class _ReminderLogWidgetState extends State<ReminderLogWidget> {
  List<Map<String, dynamic>> _log = [];
  bool _loading = true;
  bool _actioning = false;
  late bool _paused;

  @override
  void initState() {
    super.initState();
    _paused = widget.reminderPaused;
    _loadLog();
  }

  Future<void> _loadLog() async {
    setState(() => _loading = true);
    try {
      final log = await ReminderService.getReminderLog(widget.invoiceId);
      setState(() {
        _log = log;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _togglePause() async {
    setState(() => _actioning = true);
    try {
      if (_paused) {
        await ReminderService.resumeReminder(widget.invoiceId);
      } else {
        await ReminderService.pauseReminder(widget.invoiceId);
      }
      setState(() {
        _paused = !_paused;
        _actioning = false;
      });
      widget.onStatusChanged?.call();
      _snack(
          _paused ? 'Reminders paused for this invoice' : 'Reminders resumed',
          success: true);
    } catch (e) {
      setState(() => _actioning = false);
      _snack('Failed: $e', success: false);
    }
  }

  void _snack(String msg, {required bool success}) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE3EE)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F9FC),
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12), topRight: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7))),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: _navy.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.notifications_outlined,
                    color: _navy, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Reminder Automation',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _navy)),
                    Text('${widget.reminderCount} reminder(s) sent',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ])),
              // Pause/Resume button
              _actioning
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _navy))
                  : GestureDetector(
                      onTap: _togglePause,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _paused
                              ? _green.withOpacity(0.10)
                              : _orange.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _paused
                                  ? _green.withOpacity(0.4)
                                  : _orange.withOpacity(0.4)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                              _paused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                              size: 16,
                              color: _paused ? _green : _orange),
                          const SizedBox(width: 4),
                          Text(_paused ? 'Resume' : 'Pause',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _paused ? _green : _orange)),
                        ]),
                      ),
                    ),
              const SizedBox(width: 8),
              // Status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _paused
                      ? _red.withOpacity(0.08)
                      : _green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _paused
                          ? _red.withOpacity(0.3)
                          : _green.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: _paused ? _red : _green,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(_paused ? 'PAUSED' : 'ACTIVE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _paused ? _red : _green,
                          letterSpacing: 0.3)),
                ]),
              ),
            ]),
          ),

          // Log list
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: CircularProgressIndicator(
                        color: _navy, strokeWidth: 2)))
          else if (_log.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: Column(children: [
                Icon(Icons.notifications_off_outlined,
                    size: 36, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('No reminders sent yet',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13)),
              ])),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _log.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFFEEF2F7)),
              itemBuilder: (_, i) {
                final entry = _log[_log.length - 1 - i];
                final success = entry['success'] == true;
                final channel = (entry['channel'] ?? 'email').toString();
                final type = (entry['type'] ?? 'overdue').toString();
                final sentAt = entry['sentAt'] != null
                    ? DateTime.tryParse(entry['sentAt'].toString())
                    : null;
                final isEmail = channel == 'email';

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isEmail
                            ? _blue.withOpacity(0.10)
                            : const Color(0xFF25D366).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isEmail ? Icons.email_outlined : Icons.chat_outlined,
                        size: 17,
                        color: isEmail ? _blue : const Color(0xFF25D366),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Text(isEmail ? 'Email' : 'WhatsApp',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: type == 'predue'
                                    ? _orange.withOpacity(0.10)
                                    : _red.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                type == 'predue' ? 'PRE-DUE' : 'OVERDUE',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: type == 'predue' ? _orange : _red),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 2),
                          if (sentAt != null)
                            Text(
                                DateFormat('dd MMM yyyy, hh:mm a')
                                    .format(sentAt),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[500])),
                          if (!success && entry['failReason'] != null)
                            Text(entry['failReason'].toString(),
                                style: TextStyle(fontSize: 11, color: _red),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ])),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: success
                            ? _green.withOpacity(0.08)
                            : _red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            success
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            size: 13,
                            color: success ? _green : _red),
                        const SizedBox(width: 4),
                        Text(success ? 'Sent' : 'Failed',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: success ? _green : _red)),
                      ]),
                    ),
                  ]),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// REMINDER SETTINGS PAGE
// ============================================================================

class ReminderSettingsPage extends StatefulWidget {
  const ReminderSettingsPage({Key? key}) : super(key: key);

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Settings state
  bool _enabled = false;
  String _channel = 'email';
  int _frequencyDays = 1;
  String _reminderTime = '10:00';
  int _gracePeriodDays = 1;
  int _maxCap = 10;
  int _preDueDays = 0;
  List<int> _blackoutDays = [];
  int _blackoutStart = 22;
  int _blackoutEnd = 8;
  List<String> _ccEmails = [];

  // Custom template override (optional)
  final _emailSubjectCtrl = TextEditingController();
  final _emailBodyCtrl = TextEditingController();
  final _emailSubjectPreCtrl = TextEditingController();
  final _emailBodyPreCtrl = TextEditingController();
  final _waTemplateCtrl = TextEditingController();
  final _waTemplatePreCtrl = TextEditingController();
  final _ccEmailCtrl = TextEditingController();
  final _testEmailCtrl = TextEditingController();

  // ── WhatsApp Meta template selection ─────────────────────────────────────
  List<Map<String, dynamic>> _waTemplates = [];
  bool _loadingWaTemplates = false;
  String? _waOverdueTemplateName; // selected approved template for overdue
  String? _waPreDueTemplateName; // selected approved template for pre-due
  String _waTemplateLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadWaTemplates();
  }

  @override
  void dispose() {
    _emailSubjectCtrl.dispose();
    _emailBodyCtrl.dispose();
    _emailSubjectPreCtrl.dispose();
    _emailBodyPreCtrl.dispose();
    _waTemplateCtrl.dispose();
    _waTemplatePreCtrl.dispose();
    _ccEmailCtrl.dispose();
    _testEmailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await ReminderService.getSettings();
      setState(() {
        _enabled = s['enabled'] ?? false;
        _channel = s['channel'] ?? 'email';
        _frequencyDays = s['frequencyDays'] ?? 1;
        _reminderTime = s['reminderTime'] ?? '10:00';
        _gracePeriodDays = s['gracePeriodDays'] ?? 1;
        _maxCap = s['maxReminderCap'] ?? 10;
        _preDueDays = s['preDueDays'] ?? 0;
        _blackoutDays = List<int>.from(s['blackoutDays'] ?? []);
        _blackoutStart = s['blackoutStartHour'] ?? 22;
        _blackoutEnd = s['blackoutEndHour'] ?? 8;
        _ccEmails = List<String>.from(s['ccEmails'] ?? []);
        _emailSubjectCtrl.text = s['emailSubjectTemplate'] ?? '';
        _emailBodyCtrl.text = s['emailTemplate'] ?? '';
        _emailSubjectPreCtrl.text = s['emailSubjectPreDue'] ?? '';
        _emailBodyPreCtrl.text = s['emailTemplatePreDue'] ?? '';
        _waTemplateCtrl.text = s['whatsappTemplate'] ?? '';
        _waTemplatePreCtrl.text = s['whatsappTemplatePreDue'] ?? '';
        // WhatsApp template names
        _waOverdueTemplateName =
            (s['whatsappOverdueTemplateName'] as String?)?.isNotEmpty == true
                ? s['whatsappOverdueTemplateName'] as String
                : null;
        _waPreDueTemplateName =
            (s['whatsappPreDueTemplateName'] as String?)?.isNotEmpty == true
                ? s['whatsappPreDueTemplateName'] as String
                : null;
        _waTemplateLanguage = s['whatsappTemplateLanguage'] as String? ?? 'en';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadWaTemplates() async {
    setState(() => _loadingWaTemplates = true);
    try {
      final templates = await ReminderService.getWhatsAppTemplates();
      if (mounted)
        setState(() {
          _waTemplates = templates;
          _loadingWaTemplates = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadingWaTemplates = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ReminderService.saveSettings({
        'enabled': _enabled,
        'channel': _channel,
        'frequencyDays': _frequencyDays,
        'reminderTime': _reminderTime,
        'gracePeriodDays': _gracePeriodDays,
        'maxReminderCap': _maxCap,
        'preDueDays': _preDueDays,
        'blackoutDays': _blackoutDays,
        'blackoutStartHour': _blackoutStart,
        'blackoutEndHour': _blackoutEnd,
        'ccEmails': _ccEmails,
        'emailSubjectTemplate': _emailSubjectCtrl.text.trim(),
        'emailTemplate': _emailBodyCtrl.text.trim(),
        'emailSubjectPreDue': _emailSubjectPreCtrl.text.trim(),
        'emailTemplatePreDue': _emailBodyPreCtrl.text.trim(),
        'whatsappTemplate': _waTemplateCtrl.text.trim(),
        'whatsappTemplatePreDue': _waTemplatePreCtrl.text.trim(),
        // WhatsApp approved template names
        'whatsappOverdueTemplateName': _waOverdueTemplateName ?? '',
        'whatsappPreDueTemplateName': _waPreDueTemplateName ?? '',
        'whatsappTemplateLanguage': _waTemplateLanguage,
      });
      setState(() => _saving = false);
      _snack('Settings saved successfully', success: true);
    } catch (e) {
      setState(() => _saving = false);
      _snack('Failed to save: $e', success: false);
    }
  }

  // ── Preview email dialog ────────────────────────────────────────────────────

  Future<void> _openPreview(String type) async {
    try {
      _snack('Loading preview...', success: true);
      final preview = await ReminderService.getPreview(type);
      if (!mounted) return;

      final subject = preview['subject'] ?? '';
      final html = preview['html'] ?? '';

      // Pass the current template values so the Edit tab is pre-filled
      final isOverdue = type == 'overdue';
      final savedSubject =
          isOverdue ? _emailSubjectCtrl.text : _emailSubjectPreCtrl.text;
      final savedBody =
          isOverdue ? _emailBodyCtrl.text : _emailBodyPreCtrl.text;

      // If no custom override saved, pre-fill with the fetched default so user can edit from it
      final initSubject =
          savedSubject.isNotEmpty ? savedSubject : (preview['subject'] ?? '');
      final initBody =
          savedBody.isNotEmpty ? savedBody : (preview['html'] ?? '');

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => _EmailPreviewDialog(
          subject: subject,
          html: html,
          type: type,
          initSubject: initSubject,
          initBody: initBody,
          onSendTest: (email) => _sendTest(email, type),
          onSaveTemplate: (newSubject, newBody) async {
            // Update the in-page controllers so the settings form stays in sync
            if (isOverdue) {
              _emailSubjectCtrl.text = newSubject;
              _emailBodyCtrl.text = newBody;
            } else {
              _emailSubjectPreCtrl.text = newSubject;
              _emailBodyPreCtrl.text = newBody;
            }
            // Persist immediately — only the template fields for this type
            await ReminderService.saveSettings({
              'emailSubjectTemplate': _emailSubjectCtrl.text.trim(),
              'emailTemplate': _emailBodyCtrl.text.trim(),
              'emailSubjectPreDue': _emailSubjectPreCtrl.text.trim(),
              'emailTemplatePreDue': _emailBodyPreCtrl.text.trim(),
            });
          },
        ),
      );
    } catch (e) {
      _snack('Failed to load preview: $e', success: false);
    }
  }

  Future<void> _sendTest(String email, String type) async {
    if (email.trim().isEmpty) {
      _snack('Enter a test email address', success: false);
      return;
    }
    try {
      await ReminderService.sendTestEmail(email.trim(), type);
      _snack('Test email sent to $email', success: true);
    } catch (e) {
      _snack('Test email failed: $e', success: false);
    }
  }

  Future<void> _openWhatsAppPreview(String type) async {
    try {
      _snack('Loading WhatsApp preview...', success: true);
      final preview = await ReminderService.getWhatsAppPreview(type);
      if (!mounted) return;

      final isOverdue = type == 'overdue';
      final savedOverride =
          isOverdue ? _waTemplateCtrl.text : _waTemplatePreCtrl.text;
      // If user has no custom override, pre-fill with the default so they can edit from it
      final initMessage =
          savedOverride.isNotEmpty ? savedOverride : (preview['message'] ?? '');

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => _WhatsAppPreviewDialog(
          type: type,
          message: preview['message'] ?? '',
          phone: preview['testPhone'] ?? '+91 98765 43210',
          invoiceNumber: preview['invoiceNumber'] ?? 'INV-2024-0042',
          customerName: preview['customerName'] ?? 'Rajesh Kumar',
          initMessage: initMessage,
          onSaveTemplate: (newMessage) async {
            if (isOverdue) {
              _waTemplateCtrl.text = newMessage;
            } else {
              _waTemplatePreCtrl.text = newMessage;
            }
            await ReminderService.saveWhatsAppTemplates({
              'whatsappTemplate': _waTemplateCtrl.text.trim(),
              'whatsappTemplatePreDue': _waTemplatePreCtrl.text.trim(),
            });
          },
          onRefreshPreview: () => ReminderService.getWhatsAppPreview(type),
        ),
      );
    } catch (e) {
      _snack('Failed to load WhatsApp preview: $e', success: false);
    }
  }

  void _snack(String msg, {required bool success}) {
    if (!mounted) return;
    AppSnackbar.show(context, message: msg);
  }

  // ============================================================================
  // BUILD
  // ============================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      backgroundColor: const Color(0xFFF0F4F8),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : _error != null
              ? _buildError()
              : LayoutBuilder(builder: (_, constraints) {
                  final w = constraints.maxWidth;
                  if (w >= 1100) return _buildDesktop();
                  if (w >= 700) return _buildTablet();
                  return _buildMobile();
                }),
    );
  }

  // ── App bar — matches new_invoice.dart style ─────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_navy, _navyM, _navyL],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          title: const Text('Reminder Settings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          actions: [
            // Preview Overdue Email — red
            TextButton.icon(
              onPressed: () => _openPreview('overdue'),
              icon: const Icon(Icons.visibility_outlined,
                  color: Colors.white70, size: 18),
              label: const Text('Preview Overdue',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            const SizedBox(width: 4),
            // Preview Pre-Due Email — orange
            TextButton.icon(
              onPressed: () => _openPreview('predue'),
              icon: const Icon(Icons.visibility_outlined,
                  color: Color(0xFFFFCC80), size: 18),
              label: const Text('Preview Pre-Due',
                  style: TextStyle(color: Color(0xFFFFCC80), fontSize: 13)),
            ),
            const SizedBox(width: 4),
            // WhatsApp Overdue Preview
            TextButton.icon(
              onPressed: () => _openWhatsAppPreview('overdue'),
              icon: const Icon(Icons.chat_rounded,
                  color: Color(0xFF25D366), size: 18),
              label: const Text('WA Overdue',
                  style: TextStyle(color: Color(0xFF25D366), fontSize: 13)),
            ),
            const SizedBox(width: 4),
            // WhatsApp Pre-Due Preview
            TextButton.icon(
              onPressed: () => _openWhatsAppPreview('predue'),
              icon: const Icon(Icons.chat_rounded,
                  color: Color(0xFFFFCC80), size: 18),
              label: const Text('WA Pre-Due',
                  style: TextStyle(color: Color(0xFFFFCC80), fontSize: 13)),
            ),
            const SizedBox(width: 8),
            // Save button
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? 'Saving...' : 'Save Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }

  // ── Desktop — 2 columns ─────────────────────────────────────────────────────
  Widget _buildDesktop() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Column(children: [
          _buildMasterToggle(),
          const SizedBox(height: 16),
          _buildChannelCard(),
          const SizedBox(height: 16),
          _buildScheduleCard(),
          const SizedBox(height: 16),
          _buildBlackoutCard(),
        ])),
        const SizedBox(width: 16),
        Expanded(
            child: Column(children: [
          _buildCCCard(),
          const SizedBox(height: 16),
          if (_channel == 'whatsapp' || _channel == 'both') ...[
            _buildWhatsAppTemplateCard(),
            const SizedBox(height: 16),
          ],
          _buildTestEmailCard(),
        ])),
      ]),
    );
  }

  // ── Tablet / Mobile ──────────────────────────────────────────────────────────
  Widget _buildTablet() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _buildMasterToggle(),
        const SizedBox(height: 12),
        _buildChannelCard(),
        const SizedBox(height: 12),
        _buildScheduleCard(),
        const SizedBox(height: 12),
        _buildBlackoutCard(),
        const SizedBox(height: 12),
        _buildCCCard(),
        const SizedBox(height: 12),
        if (_channel == 'whatsapp' || _channel == 'both') ...[
          _buildWhatsAppTemplateCard(),
          const SizedBox(height: 12),
        ],
        _buildTestEmailCard(),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildMobile() => _buildTablet();

  // ── Master toggle ────────────────────────────────────────────────────────────
  Widget _buildMasterToggle() {
    return _card(
      title: 'Automation Status',
      icon: Icons.notifications_active_outlined,
      iconColor: _enabled ? _green : Colors.grey,
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _enabled
                ? 'Reminder automation is ENABLED'
                : 'Reminder automation is DISABLED',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: _enabled ? _green : Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          Text(
            _enabled
                ? 'Reminders will be sent automatically as per the schedule below.'
                : 'Enable to start sending automated reminders for overdue invoices.',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ])),
        Switch(
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
          activeColor: _green,
        ),
      ]),
    );
  }

  // ── Channel card ─────────────────────────────────────────────────────────────
  Widget _buildChannelCard() {
    return _card(
      title: 'Reminder Channel',
      icon: Icons.send_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Send reminders via:',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 12),
        Row(children: [
          _channelChip('email', 'Email', Icons.email_outlined),
          const SizedBox(width: 8),
          _channelChip('whatsapp', 'WhatsApp', Icons.chat_outlined),
          const SizedBox(width: 8),
          _channelChip('both', 'Both', Icons.send_rounded),
        ]),
      ]),
    );
  }

  Widget _channelChip(String value, String label, IconData icon) {
    final sel = _channel == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _channel = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: sel ? _navy : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? _navy : const Color(0xFFDDE3EE)),
            boxShadow: sel
                ? [
                    BoxShadow(
                        color: _navy.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 3))
                  ]
                : [],
          ),
          child: Column(children: [
            Icon(icon, size: 20, color: sel ? Colors.white : Colors.grey[500]),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : Colors.grey[600])),
          ]),
        ),
      ),
    );
  }

  // ── Schedule card ─────────────────────────────────────────────────────────────
  Widget _buildScheduleCard() {
    return _card(
      title: 'Schedule',
      icon: Icons.schedule_outlined,
      child: Column(children: [
        _numRow('Send every', _frequencyDays, 1, 30, 'day(s)',
            (v) => setState(() => _frequencyDays = v)),
        const SizedBox(height: 14),
        _numRow(
            'Grace period',
            _gracePeriodDays,
            0,
            30,
            'day(s) after due date',
            (v) => setState(() => _gracePeriodDays = v)),
        const SizedBox(height: 14),
        _numRow('Stop after', _maxCap, 1, 50, 'reminder(s)',
            (v) => setState(() => _maxCap = v)),
        const SizedBox(height: 14),
        _numRow(
            'Pre-due nudge',
            _preDueDays,
            0,
            30,
            'day(s) before due (0 = off)',
            (v) => setState(() => _preDueDays = v)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
              child: Text('Send at time',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500))),
          GestureDetector(
            onTap: () async {
              final parts = _reminderTime.split(':').map(int.parse).toList();
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
              );
              if (picked != null) {
                setState(() => _reminderTime =
                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _navy.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _navy.withOpacity(0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.access_time, size: 16, color: _navy),
                const SizedBox(width: 6),
                Text(_reminderTime,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _navy,
                        fontSize: 14)),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _numRow(String label, int value, int min, int max, String suffix,
      ValueChanged<int> onChange) {
    return Row(children: [
      Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500))),
      _numBtn(Icons.remove, value > min ? () => onChange(value - 1) : null),
      SizedBox(
          width: 44,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: _navy))),
      _numBtn(Icons.add, value < max ? () => onChange(value + 1) : null),
      const SizedBox(width: 8),
      Flexible(
          child: Text(suffix,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]))),
    ]);
  }

  Widget _numBtn(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap != null ? _navy.withOpacity(0.08) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color:
                  onTap != null ? _navy.withOpacity(0.2) : Colors.grey[300]!),
        ),
        child: Icon(icon,
            size: 16, color: onTap != null ? _navy : Colors.grey[400]),
      ),
    );
  }

  // ── Blackout card ─────────────────────────────────────────────────────────────
  Widget _buildBlackoutCard() {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return _card(
      title: 'Blackout Settings',
      icon: Icons.do_not_disturb_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Do not send on:',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(7, (i) {
            final sel = _blackoutDays.contains(i);
            return GestureDetector(
              onTap: () => setState(() {
                if (sel)
                  _blackoutDays.remove(i);
                else
                  _blackoutDays.add(i);
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: sel ? _navy : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: sel ? _navy : const Color(0xFFDDE3EE)),
                ),
                child: Text(days[i],
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: sel ? Colors.white : Colors.grey[600])),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        Text('Quiet hours (no reminders):',
            style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _hourDropdown('From', _blackoutStart,
                  (v) => setState(() => _blackoutStart = v))),
          const SizedBox(width: 12),
          Expanded(
              child: _hourDropdown(
                  'To', _blackoutEnd, (v) => setState(() => _blackoutEnd = v))),
        ]),
      ]),
    );
  }

  Widget _hourDropdown(String label, int value, ValueChanged<int> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          border: Border.all(color: const Color(0xFFDDE3EE)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            items: List.generate(
                24,
                (h) => DropdownMenuItem(
                      value: h,
                      child: Text('${h.toString().padLeft(2, '0')}:00',
                          style: const TextStyle(fontSize: 13)),
                    )),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    ]);
  }

  // ── CC/BCC card ───────────────────────────────────────────────────────────────
  Widget _buildCCCard() {
    return _card(
      title: 'CC / BCC Emails',
      icon: Icons.alternate_email,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('All reminder emails will also be copied to these addresses:',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _textField(_ccEmailCtrl, 'Enter email address')),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              final email = _ccEmailCtrl.text.trim();
              if (email.isNotEmpty && !_ccEmails.contains(email)) {
                setState(() {
                  _ccEmails.add(email);
                  _ccEmailCtrl.clear();
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                  color: _navy, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.add, color: Colors.white, size: 18),
            ),
          ),
        ]),
        if (_ccEmails.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _ccEmails
                .map((email) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _navy.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _navy.withOpacity(0.2)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(email,
                            style: const TextStyle(fontSize: 12, color: _navy)),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => setState(() => _ccEmails.remove(email)),
                          child:
                              const Icon(Icons.close, size: 14, color: _navy),
                        ),
                      ]),
                    ))
                .toList(),
          ),
        ],
      ]),
    );
  }

  // ── WhatsApp Template Card ────────────────────────────────────────────────────
  Widget _buildWhatsAppTemplateCard() {
    final hasTemplates = _waTemplates.isNotEmpty;
    final noCredentials = !hasTemplates && !_loadingWaTemplates;

    return _card(
      title: 'WhatsApp Templates',
      icon: Icons.chat_rounded,
      iconColor: const Color(0xFF25D366),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
            border:
                Border.all(color: const Color(0xFF25D366).withOpacity(0.25)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 15, color: Color(0xFF128C7E)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              'WhatsApp requires approved templates for business-initiated messages. '
              'Select a template for each reminder type below. '
              'Create templates in Meta Business Manager → WhatsApp Manager → Message Templates.',
              style:
                  TextStyle(fontSize: 11, color: Colors.grey[700], height: 1.5),
            )),
          ]),
        ),

        const SizedBox(height: 14),

        // Fetch / Refresh button
        Row(children: [
          Expanded(
              child: Text(
            hasTemplates
                ? '${_waTemplates.length} approved template(s) loaded'
                : _loadingWaTemplates
                    ? 'Loading templates...'
                    : 'No templates loaded yet',
            style: TextStyle(
              fontSize: 12,
              color: hasTemplates ? const Color(0xFF128C7E) : Colors.grey[500],
              fontWeight: hasTemplates ? FontWeight.w600 : FontWeight.normal,
            ),
          )),
          GestureDetector(
            onTap: _loadingWaTemplates ? null : _loadWaTemplates,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: const Color(0xFF25D366).withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _loadingWaTemplates
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF25D366)))
                    : const Icon(Icons.refresh,
                        size: 14, color: Color(0xFF25D366)),
                const SizedBox(width: 5),
                Text(_loadingWaTemplates ? 'Loading...' : 'Refresh',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF25D366),
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),

        if (noCredentials) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _orange.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _orange.withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: _orange),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                'Save your WhatsApp credentials in Settings → WhatsApp Automation first, then refresh.',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              )),
            ]),
          ),
        ],

        if (hasTemplates) ...[
          const SizedBox(height: 16),

          // Overdue template selector
          _templateDropdownRow(
            label: 'Overdue Reminder Template',
            badge: 'OVERDUE',
            badgeColor: _red,
            value: _waOverdueTemplateName,
            templates: _waTemplates,
            onChanged: (v) => setState(() => _waOverdueTemplateName = v),
          ),

          const SizedBox(height: 14),

          // Pre-due template selector
          _templateDropdownRow(
            label: 'Pre-Due Reminder Template',
            badge: 'PRE-DUE',
            badgeColor: _orange,
            value: _waPreDueTemplateName,
            templates: _waTemplates,
            onChanged: (v) => setState(() => _waPreDueTemplateName = v),
          ),

          const SizedBox(height: 14),

          // Language
          Row(children: [
            Expanded(
                child: Text('Template Language Code',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500))),
            SizedBox(
              width: 110,
              child: TextField(
                controller: TextEditingController(text: _waTemplateLanguage)
                  ..selection = TextSelection.collapsed(
                      offset: _waTemplateLanguage.length),
                onChanged: (v) =>
                    _waTemplateLanguage = v.trim().isEmpty ? 'en' : v.trim(),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g. en, en_US',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  filled: true,
                  fillColor: const Color(0xFFF7F9FC),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: Color(0xFF25D366), width: 1.5)),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 10),
          Text(
            'Tip: use "en" for English, "en_US" for US English, "hi" for Hindi, etc.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ]),
    );
  }

  Widget _templateDropdownRow({
    required String label,
    required String badge,
    required Color badgeColor,
    required String? value,
    required List<Map<String, dynamic>> templates,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: badgeColor.withOpacity(0.3)),
          ),
          child: Text(badge,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: badgeColor)),
        ),
      ]),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          border: Border.all(color: const Color(0xFFDDE3EE)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            hint: Text('Select a template (auto-pick if none)',
                style: TextStyle(fontSize: 13, color: Colors.grey[400])),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Auto-pick first approved template',
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
              ),
              ...templates.map((t) => DropdownMenuItem<String>(
                    value: t['name'] as String,
                    child: Row(children: [
                      Expanded(
                          child: Text(t['name'] as String,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500))),
                      const SizedBox(width: 6),
                      Text(t['language'] as String? ?? '',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ]),
                  )),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
      if (value != null) ...[
        const SizedBox(height: 4),
        Text('✅ Will use template "$value"',
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF128C7E),
                fontWeight: FontWeight.w500)),
      ] else ...[
        const SizedBox(height: 4),
        Text('Will auto-pick the first approved template at send time.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    ]);
  }

  // ── Test email card ───────────────────────────────────────────────────────────
  Widget _buildTestEmailCard() {
    return _card(
      title: 'Test Configuration',
      icon: Icons.science_outlined,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'Send a test email to verify SMTP and see how it looks in your inbox:',
            style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        const SizedBox(height: 12),
        _textField(_testEmailCtrl, 'Enter test email address'),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _testBtn('Send Overdue Test', _red,
                  () => _sendTest(_testEmailCtrl.text, 'overdue'))),
          const SizedBox(width: 10),
          Expanded(
              child: _testBtn('Send Pre-Due Test', _orange,
                  () => _sendTest(_testEmailCtrl.text, 'predue'))),
        ]),
      ]),
    );
  }

  Widget _testBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.send, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────────

  Widget _card(
      {required String title,
      required IconData icon,
      required Widget child,
      Color iconColor = _navy}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDE3EE)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: iconColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14, color: iconColor)),
        ]),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Color(0xFFEEF2F7)),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _textField(TextEditingController ctrl, String hint,
      {int maxLines = 1, bool obscure = false}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      obscureText: obscure,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _navy, width: 1.5)),
      ),
    );
  }

  Widget _buildError() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
        const SizedBox(height: 12),
        Text(_error ?? 'Error loading settings',
            style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loadSettings,
          style: ElevatedButton.styleFrom(
              backgroundColor: _navy, foregroundColor: Colors.white),
          child: const Text('Retry'),
        ),
      ]));
}

// ============================================================================
// EMAIL PREVIEW DIALOG — Preview tab + Edit tab
// ============================================================================

enum _PreviewTab { preview, edit }

class _EmailPreviewDialog extends StatefulWidget {
  final String subject;
  final String html;
  final String type;
  final String initSubject; // current saved subject override (may be empty)
  final String initBody; // current saved body override (may be empty)
  final void Function(String email) onSendTest;
  final Future<void> Function(String subject, String body) onSaveTemplate;

  const _EmailPreviewDialog({
    required this.subject,
    required this.html,
    required this.type,
    required this.initSubject,
    required this.initBody,
    required this.onSendTest,
    required this.onSaveTemplate,
  });

  @override
  State<_EmailPreviewDialog> createState() => _EmailPreviewDialogState();
}

class _EmailPreviewDialogState extends State<_EmailPreviewDialog> {
  _PreviewTab _tab = _PreviewTab.preview;

  // Preview
  final _testEmailCtrl = TextEditingController();
  String _iframeId = '';
  String _liveHtml = ''; // updated after save

  // Edit
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _bodyCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _liveHtml = widget.html;
    _subjectCtrl = TextEditingController(text: widget.initSubject);
    _bodyCtrl = TextEditingController(text: widget.initBody);
    if (kIsWeb) _iframeId = _registerHtmlIframe(_liveHtml);
  }

  @override
  void dispose() {
    _testEmailCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSaveTemplate(
        _subjectCtrl.text.trim(),
        _bodyCtrl.text.trim(),
      );
      // Re-fetch preview so the iframe reflects the saved template
      final preview = await ReminderService.getPreview(widget.type);
      final newHtml = (preview['html'] as String?) ?? _liveHtml;
      setState(() {
        _liveHtml = newHtml;
        if (kIsWeb) _iframeId = _registerHtmlIframe(newHtml);
        _saving = false;
        _tab = _PreviewTab.preview; // jump back to preview
      });
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue = widget.type == 'overdue';
    final badgeColor =
        isOverdue ? const Color(0xFFdc2626) : const Color(0xFFd97706);
    final badgeLabel = isOverdue ? '⚠ OVERDUE REMINDER' : '🔔 PRE-DUE REMINDER';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: 700,
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 24,
                offset: const Offset(0, 8))
          ],
        ),
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_navy, _navyM]),
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(
                  _tab == _PreviewTab.preview
                      ? Icons.visibility_outlined
                      : Icons.edit_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      _tab == _PreviewTab.preview
                          ? 'Email Preview'
                          : 'Edit Template',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(badgeLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                  ])),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),

          // ── Tab bar ──────────────────────────────────────────────────────────
          Container(
            color: _navy.withOpacity(0.06),
            child: Row(children: [
              _tabItem(
                  Icons.visibility_outlined, 'Preview', _PreviewTab.preview),
              _tabItem(Icons.edit_outlined, 'Edit', _PreviewTab.edit),
            ]),
          ),

          // ── Subject strip (preview tab only) ────────────────────────────────
          if (_tab == _PreviewTab.preview)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FC),
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(children: [
                Text('Subject:',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(widget.subject,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _navy))),
              ]),
            ),

          // ── Body ────────────────────────────────────────────────────────────
          Expanded(
              child:
                  _tab == _PreviewTab.preview ? _previewBody() : _editBody()),

          // ── Footer ──────────────────────────────────────────────────────────
          _tab == _PreviewTab.preview ? _previewFooter() : _editFooter(),
        ]),
      ),
    );
  }

  // ── Tab pill ────────────────────────────────────────────────────────────────
  Widget _tabItem(IconData icon, String label, _PreviewTab t) {
    final on = _tab == t;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = t),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: on ? _accent : Colors.transparent, width: 2)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14, color: on ? _accent : Colors.grey),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                  color: on ? _accent : Colors.grey[600],
                )),
          ]),
        ),
      ),
    );
  }

  // ── Preview body ─────────────────────────────────────────────────────────────
  Widget _previewBody() {
    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: kIsWeb
          ? (_iframeId.isNotEmpty
              ? HtmlElementView(key: ValueKey(_iframeId), viewType: _iframeId)
              : const Center(
                  child:
                      CircularProgressIndicator(color: _navy, strokeWidth: 2)))
          : const Center(
              child: Text('Preview not supported on this platform',
                  style: TextStyle(color: Colors.grey))),
    );
  }

  // ── Edit body ────────────────────────────────────────────────────────────────
  Widget _editBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Variable hint
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _navy.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _navy.withOpacity(0.12)),
          ),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            Text('Available variables:',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600)),
            ...[
              '{{invoiceNumber}}',
              '{{customerName}}',
              '{{amount}}',
              '{{amountDue}}',
              '{{dueDate}}',
              '{{companyName}}',
              '{{daysOverdue}}',
              '{{daysBefore}}'
            ].map((v) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: _navy.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(v,
                      style: const TextStyle(
                          fontSize: 10, color: _navy, fontFamily: 'monospace')),
                )),
          ]),
        ),

        const SizedBox(height: 16),

        // Subject
        const Text('Subject line',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(height: 6),
        TextField(
          controller: _subjectCtrl,
          style: const TextStyle(fontSize: 13),
          decoration: _inputDec('Leave blank to use default subject'),
        ),

        const SizedBox(height: 16),

        // Body
        const Text('Email body HTML',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(height: 6),
        TextField(
          controller: _bodyCtrl,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          maxLines: 14,
          decoration: _inputDec('Leave blank to use default template'),
        ),

        const SizedBox(height: 8),
        Text('Tip: leave both fields blank to restore the default template.',
            style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ]),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
        filled: true,
        fillColor: const Color(0xFFF7F9FC),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _navy, width: 1.5)),
      );

  // ── Preview footer — test email ───────────────────────────────────────────────
  Widget _previewFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
      ),
      child: Row(children: [
        Expanded(
            child: TextField(
          controller: _testEmailCtrl,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Enter email to send test',
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            prefixIcon: const Icon(Icons.email_outlined, size: 18),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _navy, width: 1.5)),
          ),
        )),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: () {
            widget.onSendTest(_testEmailCtrl.text);
            Navigator.pop(context);
          },
          icon: const Icon(Icons.send, size: 16),
          label: const Text('Send Test',
              style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _navy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
    );
  }

  // ── Edit footer — save ────────────────────────────────────────────────────────
  Widget _editFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
      ),
      child: Row(children: [
        Expanded(
            child: Text(
          'Changes are saved to your reminder settings and the preview will refresh.',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        )),
        const SizedBox(width: 12),
        TextButton(
          onPressed:
              _saving ? null : () => setState(() => _tab = _PreviewTab.preview),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.save_outlined, size: 16),
          label: Text(_saving ? 'Saving…' : 'Save & Preview',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _navy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
    );
  }
}

// ============================================================================
// WHATSAPP PREVIEW DIALOG — Preview tab + Edit tab
// ============================================================================

class _WhatsAppPreviewDialog extends StatefulWidget {
  final String type;
  final String message;
  final String phone;
  final String invoiceNumber;
  final String customerName;
  final String initMessage;
  final Future<void> Function(String message) onSaveTemplate;
  final Future<Map<String, dynamic>> Function() onRefreshPreview;

  const _WhatsAppPreviewDialog({
    required this.type,
    required this.message,
    required this.phone,
    required this.invoiceNumber,
    required this.customerName,
    required this.initMessage,
    required this.onSaveTemplate,
    required this.onRefreshPreview,
  });

  @override
  State<_WhatsAppPreviewDialog> createState() => _WhatsAppPreviewDialogState();
}

class _WhatsAppPreviewDialogState extends State<_WhatsAppPreviewDialog> {
  _PreviewTab _tab = _PreviewTab.preview;
  late String _liveMessage;
  late final TextEditingController _msgCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _liveMessage = widget.message;
    _msgCtrl = TextEditingController(text: widget.initMessage);
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSaveTemplate(_msgCtrl.text.trim());
      // Refresh preview with saved template
      final preview = await widget.onRefreshPreview();
      final newMessage = (preview['message'] as String?) ?? _liveMessage;
      setState(() {
        _liveMessage = newMessage;
        _saving = false;
        _tab = _PreviewTab.preview;
      });
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue = widget.type == 'overdue';
    final badgeColor =
        isOverdue ? const Color(0xFFDC2626) : const Color(0xFFD97706);
    final badgeLabel = isOverdue ? '⚠ OVERDUE REMINDER' : '🔔 PRE-DUE REMINDER';
    final headerColor = const Color(0xFF128C7E); // WhatsApp green header

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        width: 480,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 24,
                offset: const Offset(0, 8))
          ],
        ),
        child: Column(children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: Center(
                    child: Text(
                  widget.customerName.isNotEmpty
                      ? widget.customerName[0].toUpperCase()
                      : 'C',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                )),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      _tab == _PreviewTab.preview
                          ? widget.customerName
                          : 'Edit WhatsApp Template',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                    Text(
                      _tab == _PreviewTab.preview
                          ? widget.phone
                          : 'Customize the message format',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(badgeLabel,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ]),
          ),

          // ── Tab bar ───────────────────────────────────────────────────────
          Container(
            color: const Color(0xFFF0F2F5),
            child: Row(children: [
              _tabItem(Icons.visibility_outlined, 'Preview',
                  _PreviewTab.preview, headerColor),
              _tabItem(
                  Icons.edit_outlined, 'Edit', _PreviewTab.edit, headerColor),
            ]),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: _tab == _PreviewTab.preview ? _previewBody() : _editBody(),
          ),

          // ── Footer ───────────────────────────────────────────────────────
          _tab == _PreviewTab.preview ? _previewFooter() : _editFooter(),
        ]),
      ),
    );
  }

  Widget _tabItem(
      IconData icon, String label, _PreviewTab t, Color activeColor) {
    final on = _tab == t;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = t),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                  color: on ? activeColor : Colors.transparent, width: 2),
            ),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 14, color: on ? activeColor : Colors.grey[500]),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                  color: on ? activeColor : Colors.grey[600],
                )),
          ]),
        ),
      ),
    );
  }

  // ── Preview body — WhatsApp chat UI ──────────────────────────────────────
  Widget _previewBody() {
    return Container(
      color: const Color(0xFFECE5DD), // WhatsApp wallpaper color
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        // ── Test data notice ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.75),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            'Preview with test data — Invoice ${widget.invoiceNumber}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF555555)),
            textAlign: TextAlign.center,
          ),
        ),

        // ── Date chip ─────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.75),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            DateFormat('dd MMM yyyy').format(DateTime.now()),
            style: const TextStyle(fontSize: 11, color: Color(0xFF555555)),
          ),
        ),

        // ── Message bubble ────────────────────────────────────────────────
        Expanded(
          child: Align(
            alignment: Alignment.bottomRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              decoration: BoxDecoration(
                color: const Color(0xFFDCF8C6),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(1, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildWhatsAppText(_liveMessage),
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      DateFormat('hh:mm a').format(DateTime.now()),
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF777777)),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.done_all,
                        size: 14, color: Color(0xFF4FC3F7)),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Edit body ─────────────────────────────────────────────────────────────
  Widget _editBody() {
    final isOverdue = widget.type == 'overdue';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Info box
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF25D366).withOpacity(0.3)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 16, color: Color(0xFF25D366)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              'Leave blank to restore the default template. '
              'Use *bold* for bold text in WhatsApp. '
              'The variables below will be replaced with real invoice data.',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.5),
            )),
          ]),
        ),

        const SizedBox(height: 14),

        // Variable hints
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _navy.withOpacity(0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _navy.withOpacity(0.12)),
          ),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            Text('Variables:',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600)),
            ...[
              '{{customerName}}',
              '{{invoiceNumber}}',
              '{{companyName}}',
              '{{amountDue}}',
              '{{dueDate}}',
              isOverdue ? '{{daysOverdue}}' : '{{daysBefore}}',
              '{{orgPhone}}',
              '{{upiId}}'
            ].map((v) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _navy.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(v,
                      style: const TextStyle(
                          fontSize: 10, color: _navy, fontFamily: 'monospace')),
                )),
          ]),
        ),

        const SizedBox(height: 16),

        Text(
          isOverdue ? 'Overdue Message' : 'Pre-Due Message',
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13, color: _navy),
        ),
        const SizedBox(height: 6),

        TextField(
          controller: _msgCtrl,
          maxLines: 12,
          style: const TextStyle(fontSize: 13, height: 1.5),
          decoration: InputDecoration(
            hintText: 'Leave blank to use default template',
            hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
            filled: true,
            fillColor: const Color(0xFFF7F9FC),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFDDE3EE))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF25D366), width: 1.5)),
          ),
        ),

        const SizedBox(height: 8),

        // Live preview of what they're typing — re-render bubble
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _msgCtrl.text.isNotEmpty
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SizedBox(height: 8),
                  Text('Live preview:',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECE5DD),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 300),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        decoration: const BoxDecoration(
                          color: Color(0xFFDCF8C6),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(4),
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _msgCtrl,
                              builder: (_, value, __) =>
                                  _buildWhatsAppText(value.text),
                            ),
                            const SizedBox(height: 4),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(DateFormat('hh:mm a').format(DateTime.now()),
                                  style: const TextStyle(
                                      fontSize: 10, color: Color(0xFF777777))),
                              const SizedBox(width: 4),
                              const Icon(Icons.done_all,
                                  size: 14, color: Color(0xFF4FC3F7)),
                            ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ])
              : const SizedBox.shrink(),
        ),
      ]),
    );
  }

  // ── Preview footer ────────────────────────────────────────────────────────
  Widget _previewFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
            child: Text(
          'This preview uses test data. Actual messages will use real invoice details.',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        )),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => setState(() => _tab = _PreviewTab.edit),
          icon: const Icon(Icons.edit_outlined,
              size: 14, color: Color(0xFF25D366)),
          label: const Text('Edit Message',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF25D366),
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  // ── Edit footer ───────────────────────────────────────────────────────────
  Widget _editFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(children: [
        Expanded(
            child: Text(
          'Changes save immediately and preview refreshes.',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        )),
        const SizedBox(width: 12),
        TextButton(
          onPressed:
              _saving ? null : () => setState(() => _tab = _PreviewTab.preview),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.save_outlined, size: 16),
          label: Text(_saving ? 'Saving…' : 'Save & Preview',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF128C7E),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ]),
    );
  }

  // ── Render *bold* markers ─────────────────────────────────────────────────
  Widget _buildWhatsAppText(String message) {
    if (message.isEmpty) {
      return Text('(empty message)',
          style: TextStyle(
              fontSize: 12,
              color: Colors.grey[400],
              fontStyle: FontStyle.italic));
    }
    final lines = message.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: lines.map((line) {
        final spans = <TextSpan>[];
        final parts = line.split('*');
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].isEmpty) continue;
          spans.add(TextSpan(
            text: parts[i],
            style: TextStyle(
              fontSize: 13,
              color: const Color(0xFF111111),
              fontWeight: i.isOdd ? FontWeight.bold : FontWeight.normal,
              height: 1.4,
            ),
          ));
        }
        return RichText(text: TextSpan(children: spans));
      }).toList(),
    );
  }
}
