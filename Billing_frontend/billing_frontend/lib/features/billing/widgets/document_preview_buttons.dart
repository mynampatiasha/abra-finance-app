import 'web_utils_stub.dart'
    if (dart.library.html) 'web_utils_web.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../app/config/api_config.dart';
import '../../../core/services/api_service.dart';

const Color _navy  = Color(0xFF0F1E3D);
const Color _blue  = Color(0xFF2563EB);
const Color _green = Color(0xFF27AE60);
const Color _amber = Color(0xFFF59E0B);
const Color _red   = Color(0xFFEF4444);

// ─── iframe registry (web only) ──────────────────────────────────────────────
// Each viewType ID can only be registered ONCE with platformViewRegistry.
// We register it once, but keep a direct reference to the IFrameElement
// so we can update its src in-place when refreshing after save.
int _iframeCounter = 0;

/// Registers a PDF iframe by fetching the PDF as a blob and rendering it directly.
/// This avoids Google Docs Viewer which requires a publicly accessible URL.
String _registerPdfIframe(String pdfUrl, void Function(html.IFrameElement) onElement) {
  if (!kIsWeb) return '';
  final id = 'doc-iframe-${_iframeCounter++}';

  // ignore: undefined_prefixed_name
  html.platformViewRegistry.registerViewFactory(id, (_) {
    final iframe = html.IFrameElement()
      ..style.border = 'none'
      ..style.width  = '100%'
      ..style.height = '100%';
    onElement(iframe);

    // Fetch the PDF with credentials (token is in the URL query param)
    // and render it as a blob URL so no external viewer is needed.
    html.HttpRequest.request(pdfUrl, method: 'GET', responseType: 'arraybuffer').then((xhr) {
      final bytes = xhr.response as dynamic;
      final blob  = html.Blob([bytes], 'application/pdf');
      final url   = html.Url.createObjectUrl(blob);
      iframe.src  = url;
    }).catchError((e) {
      debugPrint('⚠️ PDF iframe load error: $e');
      // Fallback: show a simple error message in the iframe
      final errorHtml = '<html><body style="font-family:sans-serif;padding:20px;color:#555">'
          '<p>Could not load PDF preview.</p>'
          '<p><a href="$pdfUrl" target="_blank">Open PDF directly</a></p>'
          '</body></html>';
      final blob = html.Blob([errorHtml], 'text/html');
      iframe.src = html.Url.createObjectUrl(blob);
    });

    return iframe;
  });
  return id;
}

String _registerHtmlIframe(String html_) {
  if (!kIsWeb) return '';
  final id   = 'email-iframe-${_iframeCounter++}';
  final blob = html.Blob([html_], 'text/html');
  final url  = html.Url.createObjectUrl(blob);
  // ignore: undefined_prefixed_name
  html.platformViewRegistry.registerViewFactory(id, (_) {
    final iframe = html.IFrameElement()
      ..src          = url
      ..style.border = 'none'
      ..style.width  = '100%'
      ..style.height = '100%';
    return iframe;
  });
  return id;
}

// =============================================================================
// PUBLIC HELPERS
// =============================================================================

Future<void> openDocumentPdf({
  required BuildContext                              context,
  required String?                                   docId,
  required String                                    pdfEndpoint,
  required String                                    docNumber,
  Map<String, dynamic>                               fields = const {},
  Future<void> Function(Map<String, dynamic>)?       onSaveFields,
}) async {
  if (docId == null || docId.isEmpty) {
    _snack(context, 'Save the document first to preview PDF');
    return;
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    final url   = '${ApiConfig.baseUrl}$pdfEndpoint/$docId/pdf?token=$token';
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _PdfPreviewDialog(
        url:          url,
        docNumber:    docNumber,
        fields:       Map<String, dynamic>.from(fields),
        onSaveFields: onSaveFields,
      ),
    );
  } catch (e) {
    if (context.mounted) _snack(context, 'Failed to open PDF: $e');
  }
}

Future<void> openEmailPreview({
  required BuildContext context,
  required String?      docId,
  required String       emailEndpoint,
  String?               sendEndpoint,
}) async {
  if (docId == null || docId.isEmpty) {
    _snack(context, 'Save the document first to preview email');
    return;
  }
  try {
    final api  = ApiService();
    final data = await api.get('$emailEndpoint/$docId/email-preview');
    if (data['success'] != true) {
      if (context.mounted) _snack(context, (data['message'] as String?) ?? 'Failed to load email preview');
      return;
    }
    final preview = (data['data'] as Map<String, dynamic>?) ?? {};
    final html    = (preview['html']    as String?) ?? '';
    final subject = (preview['subject'] as String?) ?? 'Email Preview';
    final to      = (preview['to']      as String?) ?? '';
    if (html.isEmpty) {
      if (context.mounted) _snack(context, 'Email preview is empty');
      return;
    }
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => _EmailPreviewDialog(
        html:         html,
        subject:      subject,
        to:           to,
        docId:        docId,
        sendEndpoint: sendEndpoint ?? emailEndpoint,
        saveEndpoint: emailEndpoint,
      ),
    );
  } catch (e) {
    if (context.mounted) _snack(context, 'Failed to load email preview: $e');
  }
}

void _snack(BuildContext ctx, String msg, {Color? color}) {
  try {
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating),
    );
  } catch (_) {
    debugPrint('⚠️ _snack: $msg');
  }
}

// =============================================================================
// PDF PREVIEW DIALOG
// Tabs: [Preview]  [Edit Fields]  [Changes]
// =============================================================================

enum _PdfTab { preview, edit, diff }

class _DiffEntry {
  final String before;
  final String after;
  const _DiffEntry({required this.before, required this.after});
}

class _PdfPreviewDialog extends StatefulWidget {
  final String                                       url;
  final String                                       docNumber;
  final Map<String, dynamic>                         fields;
  final Future<void> Function(Map<String, dynamic>)? onSaveFields;

  const _PdfPreviewDialog({
    required this.url,
    required this.docNumber,
    required this.fields,
    this.onSaveFields,
  });

  @override
  State<_PdfPreviewDialog> createState() => _PdfPreviewDialogState();
}

class _PdfPreviewDialogState extends State<_PdfPreviewDialog> {
  // ── native ─────────────────────────────────────────────────────────────────
  WebViewController? _wvc;

  // ── web ────────────────────────────────────────────────────────────────────
  String              _iframeId      = '';
  html.IFrameElement? _iframeElement; // kept so we can mutate .src on refresh

  // ── fields ─────────────────────────────────────────────────────────────────
  late Map<String, dynamic>                _edited;
  late Map<String, dynamic>                _original;
  Map<String, dynamic>                     _prevSnapshot = {};
  final Map<String, TextEditingController> _ctls         = {};

  _PdfTab _tab     = _PdfTab.preview;
  bool    _loading = true;
  bool    _saving  = false;

  @override
  void initState() {
    super.initState();
    _original = Map<String, dynamic>.from(widget.fields);
    _edited   = Map<String, dynamic>.from(widget.fields);
    for (final e in _edited.entries) {
      _ctls[e.key] = TextEditingController(text: e.value?.toString() ?? '');
    }
    _initViewer(widget.url);
  }

  /// First call  → registers iframe / creates WebViewController.
  /// Refresh call → updates src directly (web) or reloads (native).
  void _initViewer(String pdfUrl) {
    if (kIsWeb) {
      if (_iframeId.isEmpty) {
        // Register once — capture element reference for future src updates
        _iframeId = _registerPdfIframe(pdfUrl, (el) => _iframeElement = el);
      } else {
        // Refresh: re-fetch the PDF as a blob and update src in-place
        html.HttpRequest.request(pdfUrl, method: 'GET', responseType: 'arraybuffer').then((xhr) {
          final bytes = xhr.response as dynamic;
          final blob  = html.Blob([bytes], 'application/pdf');
          _iframeElement?.src = html.Url.createObjectUrl(blob);
        }).catchError((e) {
          debugPrint('⚠️ PDF refresh error: $e');
        });
      }
      if (mounted) setState(() => _loading = false);
    } else {
      if (_wvc == null) {
        _wvc = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(NavigationDelegate(
            onPageStarted:      (_) { if (mounted) setState(() => _loading = true); },
            onPageFinished:     (_) { if (mounted) setState(() => _loading = false); },
            onWebResourceError: (e) {
              if (mounted) {
                setState(() => _loading = false);
                _snack(context, 'PDF error: ${e.description}');
              }
            },
          ));
      }
      _wvc!.loadRequest(Uri.parse(pdfUrl));
    }
  }

  @override
  void dispose() {
    for (final c in _ctls.values) c.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _changes {
    final out = <String, dynamic>{};
    for (final k in _edited.keys) {
      final nv = _ctls[k]?.text ?? '';
      if (nv != (_original[k]?.toString() ?? '')) out[k] = nv;
    }
    return out;
  }

  Future<void> _saveAndRefresh() async {
    for (final k in _edited.keys) _edited[k] = _ctls[k]?.text ?? '';
    if (_changes.isEmpty) { _snack(context, 'No changes to save'); return; }
    setState(() => _saving = true);
    try {
      await widget.onSaveFields?.call(Map<String, dynamic>.from(_edited));
      if (!mounted) return;
      _prevSnapshot = Map<String, dynamic>.from(_original);
      _original     = Map<String, dynamic>.from(_edited);
      _initViewer(widget.url); // refresh viewer
      setState(() { _saving = false; _tab = _PdfTab.diff; });
    } catch (e) {
      if (mounted) { setState(() => _saving = false); _snack(context, 'Save failed: $e', color: _red); }
    }
  }

  String _label(String key) => key
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(0)}')
      .replaceAll('_', ' ').trim()
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            if (_ctls.isNotEmpty) _tabs(),
            _body(),
            _footer(),
          ],
        ),
      );

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: _navy,
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12), topRight: Radius.circular(12)),
        ),
        child: Row(children: [
          const Icon(Icons.picture_as_pdf_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.docNumber,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              overflow: TextOverflow.ellipsis)),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
        ]),
      );

  Widget _tabs() => Container(
        color: _navy.withOpacity(0.07),
        child: Row(children: [
          _tabItem(Icons.visibility_outlined, 'Preview',     _PdfTab.preview),
          _tabItem(Icons.edit_outlined,       'Edit Fields', _PdfTab.edit),
          _tabItem(Icons.compare_arrows,      'Changes',     _PdfTab.diff),
        ]),
      );

  Widget _tabItem(IconData icon, String label, _PdfTab t) {
    final on = _tab == t;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = t),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: on ? _blue : Colors.transparent, width: 2)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 13, color: on ? _blue : Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11,
                fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                color: on ? _blue : Colors.grey[600])),
          ]),
        ),
      ),
    );
  }

  Widget _body() => SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: switch (_tab) {
            _PdfTab.preview => _pdfView(),
            _PdfTab.edit    => _editView(),
            _PdfTab.diff    => _diffView(),
          },
        ),
      );

  Widget _pdfView() {
    if (kIsWeb) {
      return Stack(key: const ValueKey('pdf-web'), children: [
        if (_iframeId.isNotEmpty)
          HtmlElementView(viewType: _iframeId)
        else
          const Center(child: CircularProgressIndicator(color: _navy)),
        if (_loading) const Center(child: CircularProgressIndicator(color: _navy)),
      ]);
    }
    return Stack(key: const ValueKey('pdf-native'), children: [
      if (_wvc != null) WebViewWidget(controller: _wvc!),
      if (_loading) const Center(child: CircularProgressIndicator(color: _navy)),
    ]);
  }

  Widget _editView() {
    // No fields passed — show helpful message instead of blank screen
    if (_ctls.isEmpty) {
      return Center(
        key: const ValueKey('edit-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.info_outline, color: Colors.grey[400], size: 48),
            const SizedBox(height: 12),
            Text(
              'No editable fields provided.\nPass a fields map to openDocumentPdf().',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ]),
        ),
      );
    }
    return SingleChildScrollView(
      key: const ValueKey('edit'),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _amber.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _amber.withOpacity(0.4)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 14, color: _amber),
            SizedBox(width: 8),
            Expanded(child: Text('Edit fields below, then tap Save & Refresh.',
                style: TextStyle(fontSize: 12, color: _amber))),
          ]),
        ),
        const SizedBox(height: 16),
        ..._ctls.entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextFormField(
            controller: e.value,
            decoration: InputDecoration(
              labelText: _label(e.key),
              labelStyle: const TextStyle(fontSize: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _blue, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
        )),
      ]),
    );
  }

  Widget _diffView() {
    final changed = <String, _DiffEntry>{};
    for (final k in _edited.keys) {
      final before = _prevSnapshot[k]?.toString() ?? '';
      final after  = _edited[k]?.toString() ?? '';
      if (before != after) changed[k] = _DiffEntry(before: before, after: after);
    }
    if (changed.isEmpty) {
      return const Center(
        key: ValueKey('diff-empty'),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_outline, color: _green, size: 48),
          SizedBox(height: 12),
          Text('No changes recorded yet.\nSave some edits first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
        ]),
      );
    }
    return ListView(
      key: const ValueKey('diff-list'),
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          const Icon(Icons.compare_arrows, size: 16, color: _navy),
          const SizedBox(width: 6),
          Text('${changed.length} field${changed.length > 1 ? 's' : ''} changed',
              style: const TextStyle(fontWeight: FontWeight.w600, color: _navy, fontSize: 13)),
        ]),
        const SizedBox(height: 12),
        ...changed.entries.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8), topRight: Radius.circular(8)),
              ),
              child: Text(_label(e.key),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _navy)),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: _red.withOpacity(0.07),
              child: Row(children: [
                const Icon(Icons.remove, size: 12, color: _red),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  e.value.before.isEmpty ? '(empty)' : e.value.before,
                  style: const TextStyle(fontSize: 12, color: _red, decoration: TextDecoration.lineThrough),
                )),
              ]),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: _green.withOpacity(0.07),
              child: Row(children: [
                const Icon(Icons.add, size: 12, color: _green),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  e.value.after.isEmpty ? '(empty)' : e.value.after,
                  style: const TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w500),
                )),
              ]),
            ),
          ]),
        )),
      ],
    );
  }

  Widget _footer() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
          borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
        ),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: const BorderSide(color: _navy),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Close'),
            ),
          ),
          if (_tab == _PdfTab.edit) ...[
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _saveAndRefresh,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(_saving ? 'Saving...' : 'Save & Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ]),
      );
}

// =============================================================================
// EMAIL PREVIEW DIALOG
// Tabs: [Preview]  [Edit]
// Send Now is always enabled — no _savedOnce gate
// =============================================================================

enum _EmailTab { preview, edit }

class _EmailPreviewDialog extends StatefulWidget {
  final String html;
  final String subject;
  final String to;
  final String docId;
  final String sendEndpoint;
  final String saveEndpoint;

  const _EmailPreviewDialog({
    required this.html,
    required this.subject,
    required this.to,
    required this.docId,
    required this.sendEndpoint,
    required this.saveEndpoint,
  });

  @override
  State<_EmailPreviewDialog> createState() => _EmailPreviewDialogState();
}

class _EmailPreviewDialogState extends State<_EmailPreviewDialog> {
  WebViewController? _wvc;
  String             _iframeId = '';

  late TextEditingController _toCtl;
  late TextEditingController _subCtl;
  late TextEditingController _bodyCtl;

  _EmailTab _tab     = _EmailTab.preview;
  bool      _saving  = false;
  bool      _sending = false;

  @override
  void initState() {
    super.initState();
    _toCtl   = TextEditingController(text: widget.to);
    _subCtl  = TextEditingController(text: widget.subject);
    _bodyCtl = TextEditingController(text: widget.html);
    _loadHtml(widget.html);
  }

  void _loadHtml(String html) {
    if (kIsWeb) {
      _iframeId = _registerHtmlIframe(html);
      if (mounted) setState(() {});
    } else {
      if (_wvc == null) {
        _wvc = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted);
      }
      _wvc!.loadHtmlString(html);
    }
  }

  @override
  void dispose() {
    _toCtl.dispose();
    _subCtl.dispose();
    _bodyCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _bodyCtl.text;
    setState(() => _saving = true);
    try {
      final api    = ApiService();
      final result = await api.patch(
        '${widget.saveEndpoint}/${widget.docId}/email-preview',
        body: {'to': _toCtl.text.trim(), 'subject': _subCtl.text.trim(), 'html': body},
      );
      if (!mounted) return;
      if (result['success'] == true) {
        final updatedHtml = (result['data']?['html'] as String?) ?? body;
        _loadHtml(updatedHtml);
        setState(() { _saving = false; _tab = _EmailTab.preview; });
        _snack(context, 'Email updated', color: _green);
      } else {
        setState(() => _saving = false);
        _snack(context, (result['message'] as String?) ?? 'Save failed', color: _red);
      }
    } catch (e) {
      if (mounted) { setState(() => _saving = false); _snack(context, 'Error: $e', color: _red); }
    }
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      final api    = ApiService();
      final result = await api.post('${widget.sendEndpoint}/${widget.docId}/send');
      if (!mounted) return;
      if (result['success'] == true) {
        Navigator.pop(context);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Email sent successfully'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        setState(() => _sending = false);
        _snack(context, (result['message'] as String?) ?? 'Send failed', color: _red);
      }
    } catch (e) {
      if (mounted) { setState(() => _sending = false); _snack(context, 'Error: $e', color: _red); }
    }
  }

  @override
  Widget build(BuildContext ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_header(), _tabs(), _body(), _footer()],
        ),
      );

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          color: _navy,
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12), topRight: Radius.circular(12)),
        ),
        child: Row(children: [
          const Icon(Icons.email_outlined, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_subCtl.text.isNotEmpty ? _subCtl.text : widget.subject,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                overflow: TextOverflow.ellipsis),
            if (_toCtl.text.isNotEmpty)
              Text('To: ${_toCtl.text}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
          ])),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          ),
        ]),
      );

  Widget _tabs() => Container(
        color: _navy.withOpacity(0.07),
        child: Row(children: [
          _tabItem(Icons.visibility_outlined, 'Preview', _EmailTab.preview),
          _tabItem(Icons.edit_outlined,       'Edit',    _EmailTab.edit),
        ]),
      );

  Widget _tabItem(IconData icon, String label, _EmailTab t) {
    final on = _tab == t;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = t),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: on ? _blue : Colors.transparent, width: 2)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 13, color: on ? _blue : Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12,
                fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                color: on ? _blue : Colors.grey[600])),
          ]),
        ),
      ),
    );
  }

  Widget _body() => SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: _tab == _EmailTab.preview ? _previewWidget() : _editWidget(),
      );

  Widget _previewWidget() {
    if (kIsWeb) {
      return HtmlElementView(key: ValueKey(_iframeId), viewType: _iframeId);
    }
    return WebViewWidget(key: const ValueKey('email-preview'), controller: _wvc!);
  }

  Widget _editWidget() => SingleChildScrollView(
        key: const ValueKey('email-edit'),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _field('To',      _toCtl,  hint: 'recipient@example.com'),
          const SizedBox(height: 12),
          _field('Subject', _subCtl, hint: 'Email subject'),
          const SizedBox(height: 12),
          const Text('Body (HTML)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy)),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextFormField(
              controller: _bodyCtl,
              maxLines: 14,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
                hintText: '<html>...</html>',
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.info_outline, size: 12, color: _amber),
            const SizedBox(width: 4),
            Expanded(child: Text(
              'Edit the raw HTML above. Changes are saved as-is without reformatting.',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            )),
          ]),
        ]),
      );

  Widget _field(String label, TextEditingController ctl, {String? hint}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _navy)),
          const SizedBox(height: 4),
          TextFormField(
            controller: ctl,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _blue, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      );

  Widget _footer() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
          borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
        ),
        child: Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: const BorderSide(color: _navy),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Close'),
            ),
          ),
          const SizedBox(width: 12),
          // Edit tab → Save
          if (_tab == _EmailTab.edit)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(_saving ? 'Saving...' : 'Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          // Preview tab → Send Now (always enabled)
          if (_tab == _EmailTab.preview)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send, size: 16),
                label: Text(_sending ? 'Sending...' : 'Send Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
        ]),
      );
}