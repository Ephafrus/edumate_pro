import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/application.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../router/app_router.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Parent dashboard: linked children, enrollment applications with live
/// status, and quick actions (apply, payments, messages).
class ParentHomeScreen extends StatelessWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final user = context.watch<AuthController>().appUser;
    if (user == null) return const AppShell(title: 'Home', body: SizedBox());

    return AppShell(
      title: 'Home',
      body: ContentContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Welcome, ${user.firstName.isEmpty ? 'there' : user.firstName}',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DashboardTile(
              icon: Icons.assignment_add,
              title: 'Apply for a child',
              subtitle:
                  'Start a step-by-step enrollment application for your child',
              onTap: () => context.go(Routes.apply),
            ),
            const SizedBox(height: 8),
            DashboardTile(
              icon: Icons.receipt_long_outlined,
              title: 'Payments',
              subtitle: 'Submit a payment with proof of payment and track '
                  'approval',
              onTap: () => context.go(Routes.parentPayments),
            ),
            const SizedBox(height: 8),
            DashboardTile(
              icon: Icons.chat_outlined,
              title: 'Messages',
              subtitle: "Request a chat with your child's teacher",
              onTap: () => context.go(Routes.chats),
            ),
            const SizedBox(height: 20),
            SectionCard(
              title: 'My children',
              child: StreamBuilder<List<Learner>>(
                stream: db.watchLearnersForParent(user.uid),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final learners = snap.data!;
                  if (learners.isEmpty) {
                    return const EmptyState(
                        'No enrolled children linked to your account yet. '
                        'Once an application is enrolled (or admin links a '
                        'learner to you) they appear here.',
                        icon: Icons.child_care_outlined);
                  }
                  return Column(
                    children: learners
                        .map((l) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                  child: Text(l.firstName.isEmpty
                                      ? '?'
                                      : l.firstName[0])),
                              title: Text(l.fullName),
                              subtitle: Text([
                                if (l.grade.isNotEmpty) l.grade,
                                l.className.isEmpty
                                    ? 'No class assigned yet'
                                    : 'Class: ${l.className}',
                              ].join(' · ')),
                              trailing: StatusChip(
                                l.status.label,
                                l.status == LearnerStatus.active
                                    ? Colors.green
                                    : Colors.blueGrey,
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'My applications',
              child: StreamBuilder<List<EnrollmentApplication>>(
                stream: db.watchApplicationsForParent(user.uid),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final apps = snap.data!;
                  if (apps.isEmpty) {
                    return const EmptyState(
                        'No applications yet — tap "Apply for a child" to '
                        'get started.',
                        icon: Icons.assignment_outlined);
                  }
                  return Column(
                    children: apps
                        .map((a) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(a.learnerFullName.isEmpty
                                  ? 'New application'
                                  : a.learnerFullName),
                              subtitle: Text([
                                if (a.gradeApplyingFor.isNotEmpty)
                                  a.gradeApplyingFor,
                                'Updated ${formatDate(a.updatedAt ?? a.createdAt)}',
                              ].join(' · ')),
                              trailing: StatusChip.application(a.status),
                              onTap: () => context.go(a.isDraft
                                  ? '${Routes.apply}?id=${a.id}'
                                  : Routes.applicationDetail(a.id)),
                            ))
                        .toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
