import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Hands the browser a file the way any download link would: a blob URL on an
/// anchor with a `download` attribute, clicked and revoked.
///
/// Uses `package:web` rather than the old `dart:html` so the app still builds
/// for WebAssembly.
Future<bool> downloadText(String filename, String content,
    {String mimeType = 'text/csv'}) async {
  final bytes = utf8.encode(content).toJS;
  final blob = web.Blob(
    [bytes].toJS,
    web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
}

const bool canDownloadFiles = true;
