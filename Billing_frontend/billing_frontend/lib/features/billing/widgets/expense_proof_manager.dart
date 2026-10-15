// =============================================================================
// EXPENSE PROOFS — several proofs per expense
//   • up to 10 files per expense, images or PDF, 10 MB each
//   • add many at once (or take a photo, repeat), view, and delete any of them
// Shared by the expenses list page and the expense detail page.
// =============================================================================

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

import '../../../core/services/api_service.dart';
import '../../../core/services/expenses_service.dart';

const int kMaxProofsPerExpense = 10;
const int _kMaxProofBytes = 10 * 1024 * 1024;

const Color _pmTeal = Color(0xFF16A085);
const Color _pmNavy = Color(0xFF1e3a8a);
const Color _pmPurple = Color(0xFF9B59B6);
const Color _pmRed = Color(0xFFE74C3C);

String _proofUrl(ApiService api, String expenseId, [String? filename]) =>
    '${api.baseUrl}/api/finance/expenses/$expenseId/proof'
    '${filename != null ? '/${Uri.encodeComponent(filename)}' : ''}';

List<ProofFile> _proofsFromResponse(dynamic data) {
  final list = (data is Map ? data['proofFiles'] : null) as List?;
  if (list == null) return [];
  return list
      .map((e) => ProofFile.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList();
}

// -----------------------------------------------------------------------------
// PICTURE CACHE — every proof picture is downloaded ONCE and kept in memory
// (the file name is unique, so a cached picture can never be the wrong one).
// Keeps at most 24 pictures / 40 MB, dropping the least recently used first.
// -----------------------------------------------------------------------------
class ProofImageCache {
  ProofImageCache._();
  static final ProofImageCache instance = ProofImageCache._();

  static const int _maxEntries = 24;
  static const int _maxBytes = 40 * 1024 * 1024;

  final LinkedHashMap<String, Uint8List> _bytes = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inflight = {};
  int _total = 0;

  /// The cached picture, or null. (Marks it as recently used.)
  Uint8List? peek(String url) {
    final b = _bytes.remove(url);
    if (b != null) _bytes[url] = b;
    return b;
  }

  void put(String url, Uint8List bytes) {
    remove(url);
    _bytes[url] = bytes;
    _total += bytes.length;
    while (_bytes.length > _maxEntries || _total > _maxBytes) {
      if (_bytes.isEmpty) break;
      final oldest = _bytes.keys.first;
      _total -= _bytes[oldest]!.length;
      _bytes.remove(oldest);
    }
  }

  void remove(String url) {
    final b = _bytes.remove(url);
    if (b != null) _total -= b.length;
    _inflight.remove(url);
  }

  void clear() {
    _bytes.clear();
    _inflight.clear();
    _total = 0;
  }

  /// From memory when we have it; otherwise one download (shared by everybody
  /// asking for the same picture at the same time).
  Future<Uint8List?> fetch(ApiService api, String url) {
    final cached = peek(url);
    if (cached != null) return Future.value(cached);
    final running = _inflight[url];
    if (running != null) return running;
    final f = () async {
      try {
        final headers = await api.getHeaders();
        final response = await http.get(Uri.parse(url), headers: headers);
        if (response.statusCode == 200) {
          put(url, response.bodyBytes);
          return response.bodyBytes;
        }
      } catch (_) {}
      return null;
    }();
    _inflight[url] = f;
    f.whenComplete(() => _inflight.remove(url));
    return f;
  }
}

/// Result of a successful upload. [proofs] is the expense's full proof list
/// straight from the server's reply — null when the server is an older version
/// whose reply has no list (the caller then asks for the list once).
class ProofUploadResult {
  final List<ProofFile>? proofs;
  const ProofUploadResult(this.proofs);
}

/// One light request: the current proofs of a single expense (no spinner page,
/// no reload of the whole expense or of the list).
Future<List<ProofFile>?> fetchExpenseProofs(
    ApiService api, String expenseId) async {
  try {
    final headers = await api.getHeaders();
    final response = await http.get(
        Uri.parse('${api.baseUrl}/api/finance/expenses/$expenseId'),
        headers: headers);
    if (response.statusCode != 200) return null;
    final data = json.decode(response.body)['data'];
    if (data is! Map) return null;
    return Expense.fromJson(Map<String, dynamic>.from(data)).proofFiles;
  } catch (_) {
    return null;
  }
}

// -----------------------------------------------------------------------------
// ADD — choose camera or files, check, upload (all files in one request).
// Returns the result of the upload, or null when nothing was uploaded.
// -----------------------------------------------------------------------------
Future<ProofUploadResult?> pickAndUploadProofs(
  BuildContext context, {
  required ApiService api,
  required String expenseId,
  required int existingCount,
  required void Function(String) onError,
  required void Function(String) onSuccess,
}) async {
  final room = kMaxProofsPerExpense - existingCount;
  if (room <= 0) {
    onError('This expense already has $kMaxProofsPerExpense proofs (the '
        'maximum). Delete one to add another.');
    return null;
  }

  final source = await showDialog<String>(
    context: context,
    builder: (_) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: _ProofSourceSheet(existingCount: existingCount),
    ),
  );
  if (source == null) return null;

  // every chosen file: name → bytes
  final picked = <MapEntry<String, Uint8List>>[];

  if (source == 'camera') {
    Uint8List? bytes;
    String? fileName;
    if (kIsWeb) {
      final completer = Completer<void>();
      final input = html.FileUploadInputElement()
        ..accept = 'image/*'
        ..setAttribute('capture', 'environment');
      input.click();
      input.onChange.listen((e) {
        final file = input.files?.first;
        if (file == null) {
          completer.complete();
          return;
        }
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        reader.onLoad.listen((_) {
          bytes = Uint8List.fromList(reader.result as List<int>);
          fileName = file.name.isNotEmpty
              ? file.name
              : 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
          completer.complete();
        });
        reader.onError.listen((_) => completer.complete());
      });
      await completer.future;
    } else {
      try {
        final shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
          maxWidth: 2048,
          maxHeight: 2048,
        );
        if (shot == null) return null;
        bytes = await shot.readAsBytes();
        fileName = shot.name.isNotEmpty
            ? shot.name
            : 'proof_${DateTime.now().millisecondsSinceEpoch}.jpg';
      } catch (e) {
        onError('Could not open camera: $e');
        return null;
      }
    }
    if (bytes == null) return null;
    picked.add(MapEntry(fileName ?? 'proof.jpg', bytes!));
  } else {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'pdf'],
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      for (final f in result.files) {
        if (f.bytes == null) {
          onError('Could not read "${f.name}"');
          return null;
        }
        picked.add(MapEntry(f.name, f.bytes!));
      }
    } catch (e) {
      onError('File picker error: $e');
      return null;
    }
  }

  if (picked.length > room) {
    onError('You can add only $room more file${room == 1 ? '' : 's'} to this '
        'expense (maximum $kMaxProofsPerExpense). You selected ${picked.length}.');
    return null;
  }
  for (final f in picked) {
    if (f.value.length > _kMaxProofBytes) {
      onError('"${f.key}" is too large '
          '(${(f.value.length / 1024 / 1024).toStringAsFixed(1)} MB). '
          'Maximum allowed is 10 MB per file.');
      return null;
    }
  }

  // progress while uploading
  var progressOpen = false;
  if (context.mounted) {
    progressOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }
  void closeProgress() {
    if (progressOpen && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      progressOpen = false;
    }
  }

  try {
    final headers = await api.getHeaders();
    final request =
        http.MultipartRequest('POST', Uri.parse(_proofUrl(api, expenseId)));
    headers.forEach((k, v) {
      if (k.toLowerCase() != 'content-type') request.headers[k] = v;
    });
    for (final f in picked) {
      request.files
          .add(http.MultipartFile.fromBytes('proof', f.value, filename: f.key));
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    closeProgress();

    final body = json.decode(response.body);
    if (response.statusCode == 200) {
      onSuccess(picked.length == 1
          ? '✅ Proof uploaded'
          : '✅ ${picked.length} proofs uploaded');

      // The photos just sent are already on the phone: keep them so they show
      // instantly and are never downloaded again.
      final data = body['data'];
      final added = (data is Map ? data['added'] : null) as List?;
      if (added != null) {
        for (var i = 0; i < added.length && i < picked.length; i++) {
          final a = added[i] as Map;
          final fname = a['filename']?.toString();
          final isImage = '${a['mimetype'] ?? ''}'.startsWith('image/') ||
              RegExp(r'\.(jpe?g|png|gif|webp)$', caseSensitive: false)
                  .hasMatch(picked[i].key);
          if (fname != null && isImage) {
            ProofImageCache.instance
                .put(_proofUrl(api, expenseId, fname), picked[i].value);
          }
        }
      }
      return ProofUploadResult(
          (data is Map && data['proofFiles'] is List)
              ? _proofsFromResponse(data)
              : null);
    }
    onError('Upload failed: ${body['message'] ?? response.statusCode}');
    return null;
  } catch (e) {
    closeProgress();
    onError('Upload error: $e');
    return null;
  }
}

class _ProofSourceSheet extends StatelessWidget {
  final int existingCount;
  const _ProofSourceSheet({required this.existingCount});

  @override
  Widget build(BuildContext context) {
    final room = kMaxProofsPerExpense - existingCount;
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: const [
          Icon(Icons.verified_outlined, color: _pmTeal, size: 22),
          SizedBox(width: 10),
          Text('Add Proofs',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A202C))),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'You can add $room more (maximum $kMaxProofsPerExpense per expense).',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
        const SizedBox(height: 20),
        _SourceTile(
          icon: Icons.camera_alt_rounded,
          color: _pmNavy,
          title: 'Take Photo',
          subtitle: 'Capture one receipt (repeat to add more)',
          onTap: () => Navigator.pop(context, 'camera'),
        ),
        const SizedBox(height: 10),
        _SourceTile(
          icon: Icons.folder_open_rounded,
          color: _pmPurple,
          title: 'Choose Files',
          subtitle: 'Select one or many — images (JPG, PNG, WEBP) or PDF, max 10 MB each',
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

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _SourceTile(
      {required this.icon,
      required this.color,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ])),
          Icon(Icons.chevron_right, color: Colors.grey[400]),
        ]),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// MANAGE — list every proof of an expense; view, delete, add more.
// Closes with the final list (or null if nothing changed is not tracked — the
// caller simply reloads its data after the dialog closes).
// -----------------------------------------------------------------------------
class ExpenseProofManagerDialog extends StatefulWidget {
  final ApiService api;
  final String expenseId;
  final String title;
  final List<ProofFile> initialProofs;
  final void Function(String) onError;
  final void Function(String) onSuccess;

  const ExpenseProofManagerDialog({
    Key? key,
    required this.api,
    required this.expenseId,
    required this.title,
    required this.initialProofs,
    required this.onError,
    required this.onSuccess,
  }) : super(key: key);

  @override
  State<ExpenseProofManagerDialog> createState() =>
      _ExpenseProofManagerDialogState();
}

class _ExpenseProofManagerDialogState extends State<ExpenseProofManagerDialog> {
  late List<ProofFile> _proofs;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _proofs = List<ProofFile>.from(widget.initialProofs);
  }

  Future<void> _add() async {
    final result = await pickAndUploadProofs(
      context,
      api: widget.api,
      expenseId: widget.expenseId,
      existingCount: _proofs.length,
      onError: widget.onError,
      onSuccess: widget.onSuccess,
    );
    if (result == null) return;
    final list = result.proofs ??
        await fetchExpenseProofs(widget.api, widget.expenseId);
    if (list != null && mounted) setState(() => _proofs = list);
  }

  Future<void> _delete(ProofFile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this proof?'),
        content: Text('"${p.originalName}" will be permanently deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _pmRed),
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Delete', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final headers = await widget.api.getHeaders();
      final response = await http.delete(
          Uri.parse(_proofUrl(widget.api, widget.expenseId, p.filename)),
          headers: headers);
      final body = json.decode(response.body);
      if (response.statusCode == 200) {
        ProofImageCache.instance
            .remove(_proofUrl(widget.api, widget.expenseId, p.filename));
        if (mounted) setState(() => _proofs = _proofsFromResponse(body['data']));
        widget.onSuccess('Proof deleted');
      } else {
        widget.onError('Could not delete: ${body['message'] ?? response.statusCode}');
      }
    } catch (e) {
      widget.onError('Could not delete: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _view(ProofFile p) async {
    final url = _proofUrl(widget.api, widget.expenseId, p.filename);
    if (p.isImage) {
      await showDialog(
        context: context,
        builder: (_) => _ProofImageViewer(
            url: url, name: p.originalName, api: widget.api),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final headers = await widget.api.getHeaders();
      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode == 200) {
        if (kIsWeb) {
          final blob = html.Blob([response.bodyBytes], 'application/pdf');
          final blobUrl = html.Url.createObjectUrlFromBlob(blob);
          html.window.open(blobUrl, '_blank');
          Future.delayed(const Duration(seconds: 30),
              () => html.Url.revokeObjectUrl(blobUrl));
        } else {
          // The file is already downloaded (with the login token). Save it and
          // open it in the phone's own viewer — opening the plain web address
          // in a browser has no token and the server refuses it.
          final dir = await getTemporaryDirectory();
          var safe = p.originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
          if (safe.isEmpty) safe = 'proof';
          // the phone picks the viewer from the extension, so make sure it has one
          final ext = RegExp(r'\.[A-Za-z0-9]{2,5}$').firstMatch(p.filename)?.group(0);
          if (ext != null && !safe.toLowerCase().endsWith(ext.toLowerCase())) {
            safe = '$safe$ext';
          }
          final file = File('${dir.path}/$safe');
          await file.writeAsBytes(response.bodyBytes);
          final result = await OpenFile.open(file.path);
          if (result.type != ResultType.done) {
            widget.onError('No app found to open this file');
          }
        }
      } else {
        widget.onError('Could not open proof (${response.statusCode})');
      }
    } catch (e) {
      widget.onError('Could not open proof: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  String _meta(ProofFile p) {
    final kb = '${(p.size / 1024).toStringAsFixed(1)} KB';
    String when = '';
    if (p.uploadedAt != null) {
      try {
        when = ' • ${DateFormat('dd MMM yyyy').format(DateTime.parse(p.uploadedAt!).toLocal())}';
      } catch (_) {}
    }
    return '$kb • ${p.isImage ? 'Image' : 'PDF'}$when';
  }

  @override
  Widget build(BuildContext context) {
    final full = _proofs.length >= kMaxProofsPerExpense;
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _proofs);
        return false;
      },
      child: Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_pmTeal, Color(0xFF1ABC9C)]),
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Row(children: [
              const Icon(Icons.verified_outlined, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Expense Proofs (${_proofs.length}/$kMaxProofsPerExpense)',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    if (widget.title.isNotEmpty)
                      Text(widget.title,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                  ])),
              IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context, _proofs)),
            ]),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Flexible(
            child: _proofs.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('No proofs attached yet.',
                        style: TextStyle(color: Colors.grey[600])))
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _proofs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = _proofs[i];
                      return ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: (p.isImage ? _pmPurple : _pmRed)
                                  .withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10)),
                          child: Icon(
                              p.isImage
                                  ? Icons.image_outlined
                                  : Icons.picture_as_pdf_outlined,
                              color: p.isImage ? _pmPurple : _pmRed),
                        ),
                        title: Text(p.originalName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(_meta(p),
                            style: const TextStyle(fontSize: 12)),
                        onTap: _busy ? null : () => _view(p),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              tooltip: 'View',
                              icon: const Icon(Icons.visibility_outlined,
                                  size: 20, color: _pmNavy),
                              onPressed: _busy ? null : () => _view(p)),
                          IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline,
                                  size: 20, color: _pmRed),
                              onPressed: _busy ? null : () => _delete(p)),
                        ]),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
                color: Color(0xFFF7F9FC),
                border: Border(top: BorderSide(color: Color(0xFFEEF2F7)))),
            child: Row(children: [
              Expanded(
                  child: OutlinedButton.icon(
                onPressed: (_busy || full) ? null : _add,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(full ? 'Maximum reached' : 'Add proofs'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: _pmTeal,
                    side: BorderSide(color: full ? Colors.grey : _pmTeal),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              )),
              const SizedBox(width: 12),
              Expanded(
                  child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, _proofs),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Done'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _pmNavy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              )),
            ]),
          ),
        ]),
      ),
    ));
  }
}

// image viewer (fetched with the login header, zoomable)
class _ProofImageViewer extends StatefulWidget {
  final String url;
  final String name;
  final ApiService api;
  const _ProofImageViewer(
      {required this.url, required this.name, required this.api});

  @override
  State<_ProofImageViewer> createState() => _ProofImageViewerState();
}

class _ProofImageViewerState extends State<_ProofImageViewer> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = ProofImageCache.instance.peek(widget.url);
    if (cached != null) {
      _bytes = cached; // already downloaded (or just uploaded) — show at once
      return;
    }
    final bytes = await ProofImageCache.instance.fetch(widget.api, widget.url);
    if (!mounted) return;
    setState(() {
      if (bytes != null) {
        _bytes = bytes;
      } else {
        _error = 'Could not load the image';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(children: [
              Expanded(
                  child: Text(widget.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600))),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Flexible(
            child: _error != null
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(_error!, textAlign: TextAlign.center))
                : _bytes == null
                    ? const Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator())
                    : InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4,
                        child: Image.memory(_bytes!, fit: BoxFit.contain)),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
