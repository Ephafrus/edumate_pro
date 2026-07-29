import 'package:flutter/services.dart';

/// Native builds have no browser download. Rather than pretend, the text is
/// put on the clipboard so it can be pasted into a spreadsheet or an email —
/// and the caller tells the user that is what happened.
Future<bool> downloadText(String filename, String content,
    {String mimeType = 'text/csv'}) async {
  await Clipboard.setData(ClipboardData(text: content));
  return false;
}

/// Whether this platform can hand the user a file directly.
const bool canDownloadFiles = false;
