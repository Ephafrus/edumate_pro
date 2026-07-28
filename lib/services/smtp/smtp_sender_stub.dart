import '../../models/mail_settings.dart';

/// Web build of the SMTP sender. Browsers cannot open SMTP sockets, so on
/// web every message is queued to the Firestore outbox instead (see
/// MailService) and delivered the next time a staff member opens the app on
/// Android/iOS/desktop.
Future<void> smtpSend(
  MailSettings settings, {
  required String to,
  required String subject,
  required String text,
  String? html,
}) async {
  throw UnsupportedError('SMTP is not available in the browser');
}

/// Whether this platform can send SMTP directly.
const bool smtpSupported = false;
