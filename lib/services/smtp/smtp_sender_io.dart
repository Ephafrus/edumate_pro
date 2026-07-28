import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../../models/mail_settings.dart';

/// Native (Android/iOS/desktop) SMTP sender using `mailer`. Port 465 is
/// treated as SMTPS; anything else negotiates STARTTLS.
Future<void> smtpSend(
  MailSettings settings, {
  required String to,
  required String subject,
  required String text,
  String? html,
}) async {
  final server = SmtpServer(
    settings.host,
    port: settings.port,
    username: settings.username,
    password: settings.password,
    ssl: settings.port == 465,
  );
  final message = Message()
    ..from = Address(settings.fromAddress,
        settings.fromName.isEmpty ? null : settings.fromName)
    ..recipients.add(to)
    ..subject = subject
    ..text = text;
  if (html != null && html.isNotEmpty) message.html = html;
  await send(message, server);
}

/// Whether this platform can send SMTP directly.
const bool smtpSupported = true;
