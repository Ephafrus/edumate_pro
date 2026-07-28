import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/app_user.dart';
import '../../models/application.dart';
import '../../models/chat.dart';
import '../../models/enums.dart';
import '../../models/payment.dart';
import '../../models/school.dart';
import '../../router/app_router.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Admin dashboard: live counts with pending-work badges linking into each
/// management area.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final user = context.watch<AuthController>().appUser;

    return AppShell(
      title: 'Dashboard',
      body: ContentContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Welcome, ${user?.firstName ?? 'Admin'}',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Everything that needs your attention, in one place.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            DashboardTile(
              icon: Icons.qr_code_scanner,
              title: 'Scan attendance QR',
              subtitle: 'Mark learners in at drop-off and out at pick-up',
              onTap: () => context.go(Routes.scan),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<EnrollmentApplication>>(
              stream: db.watchApplications(),
              builder: (context, snap) {
                final apps = snap.data ?? [];
                final open = apps
                    .where((a) =>
                        a.status == ApplicationStatus.submitted ||
                        a.status == ApplicationStatus.underReview)
                    .length;
                return DashboardTile(
                  icon: Icons.assignment_outlined,
                  title: 'Enrollment applications',
                  subtitle: '${apps.length} total',
                  badge: open > 0 ? '$open to review' : null,
                  onTap: () => context.go(Routes.adminApplications),
                );
              },
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<PaymentRecord>>(
              stream: db.watchPayments(),
              builder: (context, snap) {
                final payments = snap.data ?? [];
                final pending = payments
                    .where((p) => p.status == PaymentStatus.pending)
                    .length;
                return DashboardTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Payments',
                  subtitle: '${payments.length} submitted',
                  badge: pending > 0 ? '$pending pending' : null,
                  onTap: () => context.go(Routes.adminPayments),
                );
              },
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<ChatThread>>(
              stream: db.watchPendingChatRequests(),
              builder: (context, snap) {
                final requests = snap.data ?? [];
                return DashboardTile(
                  icon: Icons.mark_chat_unread_outlined,
                  title: 'Parent chat requests',
                  subtitle: 'Parents asking to chat with a teacher',
                  badge: requests.isNotEmpty ? '${requests.length}' : null,
                  onTap: () => context.go(Routes.adminChatRequests),
                );
              },
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Learner>>(
              stream: db.watchLearners(),
              builder: (context, snap) {
                final learners = snap.data ?? [];
                final unassigned = learners
                    .where((l) =>
                        l.status == LearnerStatus.active &&
                        (l.classId == null || l.classId!.isEmpty))
                    .length;
                return DashboardTile(
                  icon: Icons.child_care_outlined,
                  title: 'Learners',
                  subtitle: '${learners.length} on record',
                  badge: unassigned > 0 ? '$unassigned need a class' : null,
                  onTap: () => context.go(Routes.adminLearners),
                );
              },
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<SchoolClass>>(
              stream: db.watchClasses(),
              builder: (context, snap) => DashboardTile(
                icon: Icons.meeting_room_outlined,
                title: 'Classes',
                subtitle: '${snap.data?.length ?? 0} classes',
                onTap: () => context.go(Routes.adminClasses),
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<AppUser>>(
              stream: db.watchUsersByRole(UserRole.teacher),
              builder: (context, snap) => DashboardTile(
                icon: Icons.badge_outlined,
                title: 'Teachers & staff',
                subtitle: '${snap.data?.length ?? 0} teachers on the team',
                onTap: () => context.go(Routes.adminStaff),
              ),
            ),
            const SizedBox(height: 8),
            DashboardTile(
              icon: Icons.chat_outlined,
              title: 'Messages',
              subtitle: 'Staff chat',
              onTap: () => context.go(Routes.chats),
            ),
          ],
        ),
      ),
    );
  }
}
