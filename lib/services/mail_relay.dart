import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/mail_settings.dart';

/// Sends mail over HTTPS instead of SMTP.
///
/// A browser cannot open a socket to port 587, so the web portal could never
/// send mail directly and every message queued in the outbox until somebody
/// opened the app on a phone. That is a poor answer for a school that runs
/// on the web portal.
///
/// The relay closes that gap: the school points this at an HTTPS endpoint
/// they own — a Google Apps Script web app sending through the school's own
/// Gmail is the cheapest version, but any function or automation that accepts
/// a POST works — and the browser makes an ordinary HTTPS request.
///
/// The endpoint receives:
/// ```json
/// { "to": "…", "subject": "…", "text": "…", "html": "…",
///   "fromName": "…", "fromAddress": "…" }
/// ```
/// and should answer 2xx once the message is away. Anything else is treated
/// as a failure and the message stays in the outbox to be retried.
class MailRelay {
  const MailRelay._();

  /// Throws [MailRelayException] with the endpoint's own words on failure —
  /// a relay that rejects a message usually explains why, and that
  /// explanation is worth far more to an admin than "sending failed".
  static Future<void> send(
    MailSettings settings, {
    required String to,
    required String subject,
    required String text,
    String? html,
    http.Client? client,
  }) async {
    final url = Uri.tryParse(settings.relayUrl);
    if (url == null || !url.isScheme('https')) {
      throw const MailRelayException(
          'The relay URL must be a full https:// address.');
    }

    final owned = client == null;
    final send = client ?? http.Client();
    try {
      final response = await send
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              if (settings.relayToken.isNotEmpty)
                'Authorization': 'Bearer ${settings.relayToken}',
            },
            body: jsonEncode({
              'to': to,
              'subject': subject,
              'text': text,
              if (html != null && html.isNotEmpty) 'html': html,
              'fromName': settings.fromName,
              'fromAddress': settings.fromAddress,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MailRelayException(
          'The relay answered ${response.statusCode}'
          '${_detail(response.body)}',
        );
      }
    } on MailRelayException {
      rethrow;
    } catch (e) {
      throw MailRelayException(_readable(e));
    } finally {
      if (owned) send.close();
    }
  }

  static String _detail(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '.';
    return ': ${trimmed.length > 200 ? '${trimmed.substring(0, 200)}…' : trimmed}';
  }

  /// Turns the usual transport failures into something an administrator can
  /// act on, rather than a stack trace.
  static String _readable(Object e) {
    final text = e.toString();
    if (text.contains('TimeoutException')) {
      return 'The relay did not answer within 30 seconds.';
    }
    if (text.contains('XMLHttpRequest') || text.contains('ClientException')) {
      return 'The browser could not reach the relay. If the URL is right, '
          'the endpoint is most likely refusing cross-origin requests — it '
          'needs to allow this site (CORS).';
    }
    return text;
  }
}

class MailRelayException implements Exception {
  const MailRelayException(this.message);
  final String message;

  @override
  String toString() => message;
}
