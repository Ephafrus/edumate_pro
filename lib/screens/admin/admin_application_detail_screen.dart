import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/responsive.dart';
import '../../models/application.dart';
import '../../models/enums.dart';
import '../../models/activity_log.dart';
import '../../services/activity_service.dart';
import '../../services/firestore_service.dart';
import '../../services/mail_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Admin review of one application: full captured detail + documents, with
/// actions to move it through the pipeline (review → accept/reject → enroll).
/// Status changes append tracking events and trigger the notification email
/// to the guardian (via the Cloud Function watching the document).
class AdminApplicationDetailScreen extends StatelessWidget {
  const AdminApplicationDetailScreen(
      {super.key, required this.applicationId});
  final String applicationId;

  Future<void> _setStatus(BuildContext context, EnrollmentApplication app,
      ApplicationStatus status) async {
    final db = context.read<FirestoreService>();
    final mail = context.read<MailService>();
    final activity = context.read<ActivityService>();
    final byName = context.read<AuthController>().appUser?.fullName ?? '';

    String note = '';
    if (status == ApplicationStatus.rejected) {
      final reason = await _promptReason(context);
      if (reason == null) return; // cancelled
      note = reason;
    }

    if (status == ApplicationStatus.enrolled) {
      if (!context.mounted) return;
      final ok = await confirmDialog(
        context,
        'Enroll ${app.learnerFullName}?',
        'This creates the learner record and links it to the applying '
            'parent. You can then assign a class under Learners.',
        confirmLabel: 'Enroll',
      );
      if (!ok) return;
      await db.enrollApplication(app, byName: byName);
      activity.log(ActivityAction.learnerEnrolled,
          target: app.learnerFullName, details: app.gradeApplyingFor);
    } else {
      await db.setApplicationStatus(app, status, note: note, byName: byName);
      activity.log(ActivityAction.applicationStatusChanged,
          target: app.learnerFullName, details: status.label);
    }

    // Notify the guardian over the school's SMTP.
    final updated = await db.watchApplication(app.id).first;
    var mailNote = '';
    if (updated != null) {
      final email = MailService.applicationEmail(updated);
      if (email != null && updated.guardianEmail.isNotEmpty) {
        final outcome = await mail.send(
          to: updated.guardianEmail,
          subject: email.subject,
          text: email.text,
        );
        mailNote = ' — ${outcome.label}';
      }
    }
    if (context.mounted) {
      showSnack(
          context, 'Marked as ${status.label.toLowerCase()}$mailNote.');
    }
  }

  Future<String?> _promptReason(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reason for rejection'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
              hintText: 'Shared with the guardian in the notification email'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Reject application'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Application',
      breadcrumb: 'Dashboard > Applications > Review',
      body: ContentContainer(
        maxWidth: 820,
        child: StreamBuilder<EnrollmentApplication?>(
          stream: db.watchApplication(applicationId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final app = snap.data;
            if (app == null) return const EmptyState('Application not found');

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(app.learnerFullName,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    StatusChip.application(app.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                    '${app.gradeApplyingFor} · submitted '
                    '${formatDate(app.submittedAt ?? app.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                _Actions(app: app, onSet: (s) => _setStatus(context, app, s)),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Learner',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoLine('Name', app.learnerFullName),
                      InfoLine(app.learnerIdType?.label ?? 'ID',
                          app.learnerIdNumber),
                      InfoLine('Date of birth', formatDate(app.learnerDob)),
                      InfoLine('Gender', app.learnerGender?.label ?? '—'),
                      InfoLine('Grade applying for', app.gradeApplyingFor),
                      InfoLine('Home language',
                          app.homeLanguage.isEmpty ? '—' : app.homeLanguage),
                      InfoLine(
                          'Previous school',
                          app.previousSchool.isEmpty
                              ? '—'
                              : app.previousSchool),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Parent / guardian',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoLine('Name', app.guardianFullName),
                      InfoLine('Relationship', app.guardianRelationship),
                      InfoLine('Phone', app.guardianPhone),
                      InfoLine('Email', app.guardianEmail),
                      InfoLine('Address', app.guardianAddress),
                      InfoLine('Province',
                          app.guardianProvince.isEmpty
                              ? '—'
                              : app.guardianProvince),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Medical & emergency',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoLine(
                          'Medical conditions',
                          app.medicalConditions.isEmpty
                              ? 'None declared'
                              : app.medicalConditions),
                      if (app.doctorName.isNotEmpty)
                        InfoLine('Doctor',
                            '${app.doctorName} (${app.doctorPhone})'),
                      InfoLine(
                          'Emergency contact',
                          '${app.emergencyContactName} '
                              '(${app.emergencyContactPhone})'),
                      if (app.notes.isNotEmpty) InfoLine('Notes', app.notes),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'Documents',
                  child: app.documents.isEmpty
                      ? const Text('No documents uploaded',
                          style: TextStyle(color: Colors.grey))
                      : Column(
                          children: app.documents.entries
                              .map((e) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.description),
                                    title: Text(e.key),
                                    trailing: const Icon(Icons.open_in_new,
                                        size: 18),
                                    onTap: () => launchUrl(
                                        Uri.parse(e.value),
                                        mode:
                                            LaunchMode.externalApplication),
                                  ))
                              .toList(),
                        ),
                ),
                const SizedBox(height: 12),
                _ReviewThread(app: app),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'History',
                  child: app.events.isEmpty
                      ? const Text('No events yet',
                          style: TextStyle(color: Colors.grey))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: app.events
                              .map((e) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(e.status.label,
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.w600)),
                                        if (e.note.isNotEmpty) Text(e.note),
                                        Text(
                                          [
                                            formatDateTime(e.at),
                                            if (e.byName.isNotEmpty)
                                              'by ${e.byName}',
                                          ].join(' · '),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The status actions valid from the application's current state.
class _Actions extends StatelessWidget {
  const _Actions({required this.app, required this.onSet});
  final EnrollmentApplication app;
  final ValueChanged<ApplicationStatus> onSet;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];

    void add(String label, IconData icon, ApplicationStatus s,
        {bool filled = false}) {
      buttons.add(filled
          ? FilledButton.icon(
              onPressed: () => onSet(s),
              icon: Icon(icon, size: 18),
              label: Text(label))
          : OutlinedButton.icon(
              onPressed: () => onSet(s),
              icon: Icon(icon, size: 18),
              label: Text(label)));
    }

    switch (app.status) {
      case ApplicationStatus.submitted:
        add('Start review', Icons.playlist_add_check,
            ApplicationStatus.underReview,
            filled: true);
        add('Accept', Icons.check, ApplicationStatus.accepted);
        add('Reject', Icons.close, ApplicationStatus.rejected);
        break;
      case ApplicationStatus.underReview:
        add('Accept', Icons.check, ApplicationStatus.accepted, filled: true);
        add('Reject', Icons.close, ApplicationStatus.rejected);
        break;
      case ApplicationStatus.accepted:
        add('Enroll learner', Icons.school, ApplicationStatus.enrolled,
            filled: true);
        add('Reject', Icons.close, ApplicationStatus.rejected);
        break;
      case ApplicationStatus.rejected:
        add('Re-open for review', Icons.undo, ApplicationStatus.underReview);
        break;
      case ApplicationStatus.draft:
      case ApplicationStatus.enrolled:
        break;
    }

    if (buttons.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }
}

/// Notes and messages on an application.
///
/// An internal note stays with the review team; a message is shown to the
/// applicant on their own application page and can be emailed to them at the
/// same time — so a query like "we still need the birth certificate" reaches
/// the parent without leaving the review screen.
class _ReviewThread extends StatefulWidget {
  const _ReviewThread({required this.app});
  final EnrollmentApplication app;

  @override
  State<_ReviewThread> createState() => _ReviewThreadState();
}

class _ReviewThreadState extends State<_ReviewThread> {
  final _text = TextEditingController();
  bool _toApplicant = false;
  bool _alsoEmail = true;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      showSnack(context, 'Write something first');
      return;
    }
    final db = context.read<FirestoreService>();
    final mail = context.read<MailService>();
    final activity = context.read<ActivityService>();
    final auth = context.read<AuthController>();
    final me = auth.appUser;
    final app = widget.app;

    final wantsEmail = _toApplicant && _alsoEmail;
    final canEmail = wantsEmail && app.guardianEmail.isNotEmpty;

    setState(() => _sending = true);
    try {
      var emailedTo = '';
      var mailNote = '';
      if (canEmail) {
        final copy = MailService.applicantMessageEmail(
          guardianFirstName: app.guardianFirstName,
          learnerName: app.learnerFullName,
          message: text,
          fromName: me?.fullName ?? '',
          schoolName: auth.activeSchoolName,
        );
        final outcome = await mail.send(
          to: app.guardianEmail,
          subject: copy.subject,
          text: copy.text,
        );
        // Only claim it was emailed when the send actually succeeded.
        if (outcome == MailOutcome.sent) emailedTo = app.guardianEmail;
        mailNote = ' — ${outcome.label}';
      } else if (wantsEmail) {
        mailNote = ' — no email address on the application';
      }

      await db.addApplicationComment(
        app.id,
        ApplicationComment(
          id: '',
          text: text,
          byUid: me?.uid ?? '',
          byName: me?.fullName ?? '',
          internal: !_toApplicant,
          emailedTo: emailedTo,
        ),
      );
      activity.log(
          _toApplicant
              ? ActivityAction.applicationMessaged
              : ActivityAction.applicationCommented,
          target: app.learnerFullName,
          details: _toApplicant ? 'message to applicant' : 'internal note');

      _text.clear();
      if (!mounted) return;
      showSnack(
          context,
          _toApplicant
              ? 'Message sent to the applicant$mailNote.'
              : 'Note added.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not post: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final hasEmail = widget.app.guardianEmail.isNotEmpty;

    return SectionCard(
      title: 'Notes & messages',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StreamBuilder<List<ApplicationComment>>(
            stream: db.watchApplicationComments(widget.app.id),
            builder: (context, snap) {
              if (snap.hasError) {
                return const Text(
                    'Could not load the thread. Deploy the latest Firestore '
                    'rules and try again.',
                    style: TextStyle(color: Colors.grey));
              }
              final comments = snap.data ?? const <ApplicationComment>[];
              if (comments.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                      'No notes yet. Leave one for the review team, or write '
                      'to the applicant.',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return Column(
                children: comments.map((c) => _CommentRow(comment: c)).toList(),
              );
            },
          ),
          const Divider(height: 24),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: _toApplicant
                  ? 'Message the applicant will read…'
                  : 'Internal note for the review team…',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.lock_outline, size: 16),
                label: const Text('Internal note'),
                selected: !_toApplicant,
                onSelected: (_) => setState(() => _toApplicant = false),
              ),
              ChoiceChip(
                avatar: const Icon(Icons.forum_outlined, size: 16),
                label: const Text('Message the applicant'),
                selected: _toApplicant,
                onSelected: (_) => setState(() => _toApplicant = true),
              ),
              if (_toApplicant)
                FilterChip(
                  avatar: const Icon(Icons.mail_outline, size: 16),
                  label: Text(hasEmail
                      ? 'Also email ${widget.app.guardianEmail}'
                      : 'No email on file'),
                  selected: _alsoEmail && hasEmail,
                  onSelected: hasEmail
                      ? (v) => setState(() => _alsoEmail = v)
                      : null,
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _sending ? null : _post,
                icon: _sending
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send, size: 18),
                label: Text(_toApplicant ? 'Send' : 'Add note'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});
  final ApplicationComment comment;

  @override
  Widget build(BuildContext context) {
    final colour = comment.internal ? Colors.blueGrey : Colors.teal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: colour.withValues(alpha: 0.15),
            child: Icon(
                comment.internal ? Icons.lock_outline : Icons.forum_outlined,
                size: 16,
                color: colour),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                          comment.byName.isEmpty ? 'Staff' : comment.byName,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(
                        comment.internal ? 'Internal' : 'Applicant', colour),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text),
                const SizedBox(height: 2),
                Text(
                  [
                    formatDateTime(comment.at),
                    if (comment.emailed) 'emailed to ${comment.emailedTo}',
                  ].join(' · '),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
