// ============================================================================
// DETAIL PAGE ACTIONS — shared Download PDF + Share helpers
// Used by all detail pages (invoice, bill, quote, etc.)
// ============================================================================
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import '../services/api_service.dart';

/// Fetches a URL with auth headers, creates a blob, then opens or downloads it.
Future<void> fetchAndHandleFile(
  BuildContext context,
  String url,
  String filename, {
  bool download = false,
  ApiService? apiService,
}) async {
  final api = apiService ?? ApiService();
  _snack(context, 'Preparing file…', Colors.blue);
  try {
    final headers = await api.getHeaders();
    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }
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
        _snack(context, '✅ Download started', Colors.green);
      } else {
        html.window.open(blobUrl, '_blank');
        _snack(context, '✅ File opened', Colors.green);
      }
      Future.delayed(const Duration(seconds: 5), () => html.Url.revokeObjectUrl(blobUrl));
    } else {
      // Mobile — save to temp directory and open with system viewer
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      final result = await OpenFile.open(file.path);
      if (result.type == ResultType.done) {
        _snack(context, '✅ File opened', Colors.green);
      } else {
        _snack(context, 'No app found to open this file', Colors.orange);
      }
    }
  } catch (e) {
    _snack(context, 'Failed: $e', Colors.red);
  }
}

/// Share plain text summary of a document.
Future<void> shareText(BuildContext context, String text, String subject) async {
  try {
    await Share.share(text, subject: subject);
  } catch (e) {
    _snack(context, 'Share failed: $e', Colors.red);
  }
}

void _snack(BuildContext context, String msg, Color color) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: color,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 2),
  ));
}
