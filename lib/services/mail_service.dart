import 'package:flutter/foundation.dart';

import '../models/application.dart';
import '../models/enums.dart';
import 'firestore_service.dart';
import 'smtp/smtp_sender_stub.dart'
    if (dart.library.io) 'smtp/smtp_sender_io.dart';

/// Outcome of a send attempt, surfaced to the acting staff member.
enum MailOutcome {
  sent,

  /// SMTP isn't configured yet — the message sits in the outbox until an
  /// admin completes Email settings.
  notConfigured,

  /// Sent from a browser: queued to the outbox, delivered when a staff
  /// member opens the app on a platform that can speak SMTP.
  queuedOnWeb,
  failed;

  String get label {
    switch (this) {
      case MailOutcome.sent:
        return 'email sent';
      case MailOutcome.notConfigured:
        return 'email queued (SMTP not configured yet)';
      case MailOutcome.queuedOnWeb:
        return 'email queued (sends from the mobile/desktop app)';
      case MailOutcome.failed:
        return 'email failed — see the outbox';
    }
  }
}

/// All outgoing school email, sent **directly from the app over SMTP** using
/// the settings an admin captured under Email settings (`settings/smtp`).
/// There is no server component.
///
/// Every message is also logged to `mailQueue` (status sent/pending/error)
/// as an audit trail and outbox: messages that could not be sent (web
/// build, missing settings, SMTP hiccup) stay `pending` and are retried by
/// [flushOutbox], which staff dashboards trigger on load.
class MailService {
  MailService(this._db);

  final FirestoreService _db;
  bool _flushing = false;

  /// Sends one email now if this platform can, otherwise queues it.
  Future<MailOutcome> send({
    required String to,
    required String subject,
    required String text,
    String? html,
  }) async {
    if (to.trim().isEmpty) return MailOutcome.failed;
    final settings = await _db.getMailSettings();
    if (settings == null || !settings.isComplete) {
      await _db.logMail(
          to: to, subject: subject, text: text, html: html, status: 'pending');
      return MailOutcome.notConfigured;
    }
    if (kIsWeb || !smtpSupported) {
      await _db.logMail(
          to: to, subject: subject, text: text, html: html, status: 'pending');
      return MailOutcome.queuedOnWeb;
    }
    try {
      await smtpSend(settings, to: to, subject: subject, text: text, html: html);
      await _db.logMail(
          to: to, subject: subject, text: text, html: html, status: 'sent');
      return MailOutcome.sent;
    } catch (e) {
      await _db.logMail(
          to: to,
          subject: subject,
          text: text,
          html: html,
          status: 'error',
          error: '$e');
      return MailOutcome.failed;
    }
  }

  /// Sends a test message to verify the captured SMTP settings.
  Future<MailOutcome> sendTest(String to) => send(
        to: to,
        subject: 'EduMate Pro — test email',
        text: 'Your school SMTP settings are working. This is a test '
            'message from EduMate Pro.',
      );

  /// Retries queued/errored outbox messages. No-op on web (can't send) and
  /// while another flush is running. Returns how many were sent.
  Future<int> flushOutbox() async {
    if (kIsWeb || !smtpSupported || _flushing) return 0;
    final settings = await _db.getMailSettings();
    if (settings == null || !settings.isComplete) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final pending = await _db.getUnsentMail(limit: 25);
      for (final m in pending) {
        try {
          await smtpSend(settings,
              to: m.to, subject: m.subject, text: m.text, html: m.html);
          await _db.markMail(m.id, 'sent');
          sent++;
        } catch (e) {
          await _db.markMail(m.id, 'error', error: '$e');
        }
      }
    } finally {
      _flushing = false;
    }
    return sent;
  }

  /// Fire-and-forget outbox retry, safe to call from a build/init path.
  void flushOutboxSoon() {
    // Errors are already recorded on the queue docs.
    flushOutbox().catchError((_) => 0);
  }

  // ---- Standard notification copy -----------------------------------------

  static const _signature = '\n\nKind regards\nThe School Office\n'
      '(sent by EduMate Pro — please do not reply to this address)';

  static String _greet(String firstName) =>
      firstName.isEmpty ? 'Dear parent/guardian,\n\n' : 'Dear $firstName,\n\n';

  /// Guardian-facing email for an application status change; null for
  /// statuses that don't notify (drafts).
  static ({String subject, String text})? applicationEmail(
      EnrollmentApplication app) {
    final learner =
        app.learnerFullName.isEmpty ? 'your child' : app.learnerFullName;
    final String subject;
    final String body;
    switch (app.status) {
      case ApplicationStatus.submitted:
        subject = 'Application received — $learner';
        body = 'We have received your enrollment application for $learner '
            '(${app.gradeApplyingFor.isEmpty ? 'grade not specified' : app.gradeApplyingFor}). '
            'We will email you as it progresses. You can also track it any '
            'time in the EduMate Pro app.';
        break;
      case ApplicationStatus.underReview:
        subject = 'Application under review — $learner';
        body = 'Your enrollment application for $learner is now under '
            'review. We will be in touch with the outcome soon.';
        break;
      case ApplicationStatus.accepted:
        subject = 'Application accepted — $learner';
        body = 'Great news — your enrollment application for $learner has '
            'been accepted! The school will finalise enrollment and let you '
            'know the next steps (including any registration payment).';
        break;
      case ApplicationStatus.rejected:
        subject = 'Application outcome — $learner';
        body = 'We are sorry — your enrollment application for $learner was '
            'not successful.'
            '${app.rejectionReason.isEmpty ? '' : '\n\nReason: ${app.rejectionReason}'}'
            '\n\nPlease contact the school office if you would like to '
            'discuss this.';
        break;
      case ApplicationStatus.enrolled:
        subject = 'Welcome! $learner is enrolled';
        body = '$learner is now enrolled! Their learner profile has been '
            'created and linked to your account in the EduMate Pro app, '
            'where you will see class placement, payments and messages.';
        break;
      case ApplicationStatus.draft:
        return null;
    }
    final greeting = _greet(app.guardianFirstName);
    return (subject: subject, text: '$greeting$body$_signature');
  }

  /// Parent-facing email for a payment approval/rejection.
  static ({String subject, String text}) paymentEmail({
    required String parentFirstName,
    required String purpose,
    required String amountLabel,
    required String learnerName,
    required bool approved,
    String reviewNote = '',
  }) {
    final forLine = learnerName.isEmpty ? '' : ' for $learnerName';
    final subject = approved
        ? 'Payment approved — $purpose ($amountLabel)'
        : 'Payment could not be verified — $purpose';
    final body = approved
        ? 'Your payment of $amountLabel$forLine ($purpose) has been '
            'reviewed and approved by the school. Thank you!'
        : 'Your submitted payment of $amountLabel$forLine ($purpose) could '
            'not be verified.'
            '${reviewNote.isEmpty ? '' : '\n\nNote from the school: $reviewNote'}'
            '\n\nPlease check the details and re-submit, or contact the '
            'school office.';
    return (
      subject: subject,
      text: '${_greet(parentFirstName)}$body$_signature'
    );
  }

  /// Parent-facing email for a QR attendance scan.
  static ({String subject, String text}) attendanceEmail({
    required String parentFirstName,
    required String learnerName,
    required AttendanceType type,
    required DateTime at,
    String byName = '',
  }) {
    final learner = learnerName.isEmpty ? 'Your child' : learnerName;
    final when = '${at.day}/${at.month}/${at.year} '
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final by = byName.isEmpty ? '' : ' (scanned by $byName)';
    final checkIn = type == AttendanceType.checkIn;
    final subject = checkIn
        ? '$learner arrived at school'
        : '$learner has left school';
    final body = checkIn
        ? '$learner was dropped off and marked present at school at '
            '$when$by.'
        : '$learner was signed out and has left school at $when$by.';
    return (
      subject: subject,
      text: '${_greet(parentFirstName)}$body$_signature'
    );
  }
}
