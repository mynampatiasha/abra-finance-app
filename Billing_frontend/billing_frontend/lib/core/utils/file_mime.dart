// Picks the file type a downloaded file should be opened with.
//
// A server may report a file as "application/octet-stream" (= unknown) — the
// phone and web apps used to upload proofs without saying what they were. A
// browser SAVES a file of unknown type instead of showing it, so a PDF or a
// picture would download rather than open. When the reported type is unknown,
// the file name's extension decides.

const Map<String, String> _mimeByExtension = {
  'pdf': 'application/pdf',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'gif': 'image/gif',
  'webp': 'image/webp',
};

/// [headerType] is the Content-Type the server sent (may include "; charset=…").
String mimeForDownload(String? headerType, String filename) {
  final reported = (headerType ?? '').split(';').first.trim().toLowerCase();
  if (reported.isNotEmpty && reported != 'application/octet-stream') {
    return reported; // a clear type from the server is always kept
  }
  final m = RegExp(r'\.([A-Za-z0-9]{2,5})$').firstMatch(filename);
  final fromName = m == null ? null : _mimeByExtension[m.group(1)!.toLowerCase()];
  return fromName ?? (reported.isEmpty ? 'application/octet-stream' : reported);
}
