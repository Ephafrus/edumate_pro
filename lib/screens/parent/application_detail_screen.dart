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

/// Parent's view of a submitted application: the captured details plus a
/// status timeline that tracks it from submission to enrollment.
class ApplicationDetailScreen extends StatelessWidget {
  const ApplicationDetailScreen({super.key, required this.applicationId});
  final String applicationId;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final uid = context.watch<AuthController>().appUser?.uid;

    return AppShell(
      title: 'Application',
      breadcrumb: 'Home > My applications',
      body: ContentContainer(
        maxWidth: 760,
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
            if (app == null || app.parentUid != uid) {
              return const EmptyState('Application not found');
            }
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
                const SizedBox(height: 16),
                if (app.status == ApplicationStatus.rejected &&
                    app.rejectionReason.isNotEmpty) ...[
                  Card(
                    color: Theme.of(context)
                        .colorScheme
                        .errorContainer
                        .withValues(alpha: 0.5),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Reason',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(app.rejectionReason),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SectionCard(
                  title: 'Progress',
                  child: _Timeline(events: app.events),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Messages from the school',
                  child: StreamBuilder<List<ApplicationComment>>(
                    stream: db.watchApplicationComments(applicationId,
                        visibleOnly: true),
                    builder: (context, snap) {
                      final messages =
                          snap.data ?? const <ApplicationComment>[];
                      if (messages.isEmpty) {
                        return const Text(
                            'Nothing yet. The school will write here if they '
                            'need anything from you.',
                            style: TextStyle(color: Colors.grey));
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: messages
                            .map((m) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(m.text),
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          formatDateTime(m.at),
                                          if (m.byName.isNotEmpty)
                                            'from ${m.byName}',
                                        ].join(' · '),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Learner',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoLine('Name', app.learnerFullName),
                      InfoLine('Date of birth', formatDate(app.learnerDob)),
                      InfoLine('Gender', app.learnerGender?.label ?? '—'),
                      InfoLine('Grade applying for', app.gradeApplyingFor),
                      if (app.homeLanguage.isNotEmpty)
                        InfoLine('Home language', app.homeLanguage),
                      if (app.previousSchool.isNotEmpty)
                        InfoLine('Previous school', app.previousSchool),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Parent / guardian',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoLine('Name', app.guardianFullName),
                      InfoLine('Relationship', app.guardianRelationship),
                      InfoLine('Phone', app.guardianPhone),
                      InfoLine('Email', app.guardianEmail),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                                    trailing:
                                        const Icon(Icons.open_in_new, size: 18),
                                    onTap: () => launchUrl(Uri.parse(e.value),
                                        mode: LaunchMode.externalApplication),
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

/// Vertical status timeline of the application's tracking events.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.events});
  final List<ApplicationEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Text('No updates yet — the school will review your '
          'application soon.');
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  children: [
                    Icon(
                      i == events.length - 1
                          ? Icons.radio_button_checked
                          : Icons.check_circle,
                      size: 18,
                      color: scheme.primary,
                    ),
                    if (i != events.length - 1)
                      Expanded(
                        child: Container(
                            width: 2,
                            color: scheme.primary.withValues(alpha: 0.3)),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(events[i].status.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                        if (events[i].note.isNotEmpty) Text(events[i].note),
                        Text(
                          [
                            formatDateTime(events[i].at),
                            if (events[i].byName.isNotEmpty)
                              'by ${events[i].byName}',
                          ].join(' · '),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
