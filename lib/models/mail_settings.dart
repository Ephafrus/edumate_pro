import 'package:cloud_firestore/cloud_firestore.dart';

/// The school's outgoing SMTP email settings, configured by an admin at
/// `settings/smtp` (Email settings screen). All notification email — the
/// application/payment/attendance notices and broadcasts — is sent directly
/// from the app over SMTP using these details; there is no server component.
///
/// Staff can read the settings (teachers' attendance scans send email too);
/// only admins may change them.
/// How the school's mail actually leaves the building.
enum MailTransport {
  /// A direct SMTP connection. Works on mobile and desktop only — a browser
  /// cannot open a socket to port 587, and no setting changes that.
  smtp,

  /// An HTTPS endpoint the school owns that accepts a JSON message and sends
  /// it. This is what lets the **web portal** send mail: the browser can make
  /// an ordinary HTTPS request even though it can never speak SMTP.
  relay;

  static MailTransport fromString(String? s) =>
      s == 'relay' ? MailTransport.relay : MailTransport.smtp;

  String get label =>
      this == MailTransport.relay ? 'HTTPS relay (works on the web)' : 'SMTP';
}

class MailSettings {
  const MailSettings({
    this.host = '',
    this.port = 587,
    this.username = '',
    this.password = '',
    this.fromName = '',
    this.fromAddress = '',
    this.transport = MailTransport.smtp,
    this.relayUrl = '',
    this.relayToken = '',
  });

  final String host;

  /// 465 is treated as SMTPS; anything else uses STARTTLS.
  final int port;
  final String username;
  final String password;
  final String fromName;
  final String fromAddress;

  final MailTransport transport;

  /// Endpoint that receives `{to, subject, text, html, fromName, fromAddress}`
  /// as JSON and sends the message.
  final String relayUrl;

  /// Sent as `Authorization: Bearer <token>` when set, so the school's relay
  /// is not left open to anyone who finds the URL.
  final String relayToken;

  bool get usesRelay => transport == MailTransport.relay;

  bool get isComplete => usesRelay
      ? relayUrl.isNotEmpty && fromAddress.isNotEmpty
      : host.isNotEmpty &&
          username.isNotEmpty &&
          password.isNotEmpty &&
          fromAddress.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'host': host.trim(),
        'port': port,
        'username': username.trim(),
        'password': password,
        'fromName': fromName.trim(),
        'fromAddress': fromAddress.trim(),
        'transport': transport.name,
        'relayUrl': relayUrl.trim(),
        'relayToken': relayToken.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory MailSettings.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return MailSettings(
      host: (m['host'] ?? '') as String,
      port: (m['port'] as num?)?.toInt() ?? 587,
      username: (m['username'] ?? '') as String,
      password: (m['password'] ?? '') as String,
      fromName: (m['fromName'] ?? '') as String,
      fromAddress: (m['fromAddress'] ?? '') as String,
      transport: MailTransport.fromString(m['transport'] as String?),
      relayUrl: (m['relayUrl'] ?? '') as String,
      relayToken: (m['relayToken'] ?? '') as String,
    );
  }
}

/// One message in the `mailQueue` audit trail / outbox. Status `sent` is the
/// audit record; `pending` (queued from web or before SMTP was configured)
/// and `error` are retried by MailService.flushOutbox.
class QueuedMail {
  const QueuedMail({
    required this.id,
    required this.to,
    required this.subject,
    required this.text,
    this.html,
    this.status = 'pending',
    this.error = '',
    this.createdAt,
  });

  final String id;
  final String to;
  final String subject;
  final String text;
  final String? html;
  final String status;
  final String error;
  final DateTime? createdAt;

  factory QueuedMail.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return QueuedMail(
      id: doc.id,
      to: (m['to'] ?? '') as String,
      subject: (m['subject'] ?? '') as String,
      text: (m['text'] ?? '') as String,
      html: m['html'] as String?,
      status: (m['status'] ?? 'pending') as String,
      error: (m['error'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
