import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/application.dart';
import '../../models/enums.dart';
import '../../router/app_router.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Admin queue of enrollment applications, filterable by status.
class AdminApplicationsScreen extends StatefulWidget {
  const AdminApplicationsScreen({super.key});

  @override
  State<AdminApplicationsScreen> createState() =>
      _AdminApplicationsScreenState();
}

class _AdminApplicationsScreenState extends State<AdminApplicationsScreen> {
  ApplicationStatus? _filter = ApplicationStatus.submitted;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Applications',
      breadcrumb: 'Dashboard > Applications',
      body: ContentContainer(
        maxWidth: 860,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enrollment applications',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  const SizedBox(width: 8),
                  ...ApplicationStatus.values
                      .where((s) => s != ApplicationStatus.draft)
                      .map((s) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(s.label),
                              selected: _filter == s,
                              onSelected: (_) =>
                                  setState(() => _filter = s),
                            ),
                          )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<EnrollmentApplication>>(
              stream: db.watchApplications(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final apps = snap.data!
                    .where((a) => a.status != ApplicationStatus.draft)
                    .where((a) => _filter == null || a.status == _filter)
                    .toList();
                if (apps.isEmpty) {
                  return const EmptyState('No applications in this view.',
                      icon: Icons.assignment_outlined);
                }
                return Column(
                  children: apps
                      .map((a) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(a.learnerFullName),
                              subtitle: Text([
                                a.gradeApplyingFor,
                                'Guardian: ${a.guardianFullName}',
                                'Submitted ${formatDate(a.submittedAt ?? a.createdAt)}',
                              ].join(' · ')),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StatusChip.application(a.status),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () => context
                                  .go(Routes.adminApplicationDetail(a.id)),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
