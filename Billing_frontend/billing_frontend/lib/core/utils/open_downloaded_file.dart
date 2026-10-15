// Saves a file that the app has ALREADY downloaded (with the login token) into
// the phone's temporary folder and opens it with the phone's own viewer.
//
// Opening the plain web address in a browser instead does not work: the browser
// has no login token, so the server answers "No token provided".
// Only for the phone app — the web app opens downloads through the browser.

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

/// Returns true when a viewer was found and opened.
Future<bool> openDownloadedFile(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  var safe = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (safe.isEmpty) safe = 'download';
  final file = File('${dir.path}/$safe');
  await file.writeAsBytes(bytes);
  final result = await OpenFile.open(file.path);
  return result.type == ResultType.done;
}
