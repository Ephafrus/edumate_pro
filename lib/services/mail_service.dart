import 'package:flutter/foundation.dart';

import '../models/application.dart';
import '../models/enums.dart';
import '../models/mail_settings.dart';
import 'firestore_service.dart';
import 'mail_relay.dart';
import 'smtp/smtp_sender_stub.dart'
    if (dart.library.io) 'smtp/smtp_sender_io.dart';

/// Outcome of a send attempt, surfaced to the acting staff member.
enum MailOutcome {
  sent,

  /// SMTP isn't configured yet — the message sits in the outbox until an
  /// admin completes Email settings.
  notConfigured,

  /// Composed in a browser with only SMTP configured: queued to the outbox
  /// and delivered when a staff member opens the app on a platform that can
  /// speak SMTP. Configure an HTTPS relay to send from the web instead.
  queuedOnWeb,
  failed;

  String get label {
    switch (this) {
      case MailOutcome.sent:
        return 'email sent';
      case MailOutcome.notConfigured:
        return 'email queued (email is not configured yet)';
      case MailOutcome.queuedOnWeb:
        return 'email queued — the web portal cannot speak SMTP; set up an '
            'HTTPS relay under Email settings to send from here';
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
    // A browser can never open an SMTP socket, but it can make an HTTPS
    // request — so the relay is what makes the web portal able to send.
    final canSendHere = settings.usesRelay || (!kIsWeb && smtpSupported);
    if (!canSendHere) {
      await _db.logMail(
          to: to, subject: subject, text: text, html: html, status: 'pending');
      return MailOutcome.queuedOnWeb;
    }
    try {
      await _deliver(settings,
          to: to, subject: subject, text: text, html: html);
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

  Future<void> _deliver(
    MailSettings settings, {
    required String to,
    required String subject,
    required String text,
    String? html,
  }) =>
      settings.usesRelay
          ? MailRelay.send(settings,
              to: to, subject: subject, text: text, html: html)
          : smtpSend(settings,
              to: to, subject: subject, text: text, html: html);

  /// Sends a test message and reports the **actual** reason it failed.
  ///
  /// [send] deliberately swallows the error into an outcome so a status
  /// change is never blocked by mail. When an admin is deliberately testing
  /// their settings, the opposite is true: the provider's own words are the
  /// entire point.
  Future<({bool ok, String message})> verify(String to) async {
    if (to.trim().isEmpty) {
      return (ok: false, message: 'Enter an address to send the test to.');
    }
    final settings = await _db.getMailSettings();
    if (settings == null || !settings.isComplete) {
      return (
        ok: false,
        message: 'Email is not configured yet — fill in the settings below '
            'and save before testing.'
      );
    }
    if (!settings.usesRelay && (kIsWeb || !smtpSupported)) {
      return (
        ok: false,
        message: 'This is the web portal, which cannot open an SMTP '
            'connection — no browser can. Switch the transport to HTTPS '
            'relay to send from here, or test from the mobile/desktop app.'
      );
    }
    try {
      await _deliver(settings,
          to: to,
          subject: 'EduMate Pro — test email',
          text: 'Your school email settings are working. This is a test '
              'message from EduMate Pro.');
      await _db.logMail(
          to: to,
          subject: 'EduMate Pro — test email',
          text: 'Test message',
          status: 'sent');
      return (ok: true, message: 'Test email sent to $to.');
    } catch (e) {
      final reason = e is MailRelayException ? e.message : '$e';
      await _db.logMail(
          to: to,
          subject: 'EduMate Pro — test email',
          text: 'Test message',
          status: 'error',
          error: reason);
      return (ok: false, message: reason);
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
    if (_flushing) return 0;
    final settings = await _db.getMailSettings();
    if (settings == null || !settings.isComplete) return 0;
    // With a relay the web portal can clear the backlog too — which is the
    // point of having one.
    if (!settings.usesRelay && (kIsWeb || !smtpSupported)) return 0;
    _flushing = true;
    var sent = 0;
    try {
      final pending = await _db.getUnsentMail(limit: 25);
      for (final m in pending) {
        try {
          await _deliver(settings,
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
  /// A message the review team wrote to an applicant, wrapped so it reads as
  /// a letter from the school rather than a bare comment.
  static ({String subject, String text}) applicantMessageEmail({
    required String guardianFirstName,
    required String learnerName,
    required String message,
    String fromName = '',
    String schoolName = '',
  }) {
    final learner = learnerName.isEmpty ? 'your child' : learnerName;
    final greeting =
        guardianFirstName.isEmpty ? 'Good day' : 'Dear $guardianFirstName';
    final signOff = [
      if (fromName.isNotEmpty) fromName,
      if (schoolName.isNotEmpty) schoolName,
    ].join('\n');
    return (
      subject: 'About your application for $learner',
      text: '$greeting,\n\n'
          '$message\n\n'
          'You can also see this message on your application in EduMate '
          'Pro.\n\n'
          '${signOff.isEmpty ? 'The admissions team' : signOff}',
    );
  }

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
