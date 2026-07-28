import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/responsive.dart';
import '../../models/application.dart';
import '../../models/enums.dart';
import '../../services/firestore_service.dart';
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
    } else {
      await db.setApplicationStatus(app, status, note: note, byName: byName);
    }
    if (context.mounted) {
      showSnack(context,
          'Marked as ${status.label.toLowerCase()} — the guardian will be '
          'emailed.');
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
