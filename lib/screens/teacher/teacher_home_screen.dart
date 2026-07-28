import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/academics.dart';
import '../../models/school.dart';
import '../../router/app_router.dart';
import '../../services/firestore_service.dart';
import '../../services/mail_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/home_banner.dart';

/// Teacher home: the classes assigned to this teacher, plus quick links to
/// messages.
class TeacherHomeScreen extends StatelessWidget {
  const TeacherHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final user = context.watch<AuthController>().appUser;
    if (user == null) {
      return const AppShell(title: 'My classes', body: SizedBox());
    }
    // Deliver any email queued from web sessions / SMTP hiccups.
    context.read<MailService>().flushOutboxSoon();

    return AppShell(
      title: 'My classes',
      body: ContentContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HomeBanner(),
            DashboardTile(
              icon: Icons.qr_code_scanner,
              title: 'Scan attendance QR',
              subtitle: 'Mark learners in at drop-off and out at pick-up — '
                  'parents are notified',
              onTap: () => context.go(Routes.scan),
            ),
            const SizedBox(height: 8),
            DashboardTile(
              icon: Icons.chat_outlined,
              title: 'Messages',
              subtitle:
                  'Chat with colleagues, and with parents once admin approves',
              onTap: () => context.go(Routes.chats),
            ),
            const SizedBox(height: 20),
            SectionCard(
              title: 'My subjects',
              child: StreamBuilder<List<Subject>>(
                stream: db.watchSubjectsForTeacher(user.uid),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final subjects = snap.data!;
                  if (subjects.isEmpty) {
                    return const EmptyState(
                        'No subjects assigned to you yet — the school admin '
                        'adds subjects to a class and assigns the teacher.',
                        icon: Icons.menu_book_outlined);
                  }
                  return Column(
                    children: subjects
                        .map((s) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.menu_book_outlined),
                              title: Text(s.name),
                              subtitle: Text(s.className),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  context.go(Routes.teacherSubject(s.id)),
                            ))
                        .toList(),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'My classes',
              child: StreamBuilder<List<SchoolClass>>(
                stream: db.watchClassesForTeacher(user.uid),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final classes = snap.data!;
                  if (classes.isEmpty) {
                    return const EmptyState(
                        'No classes assigned to you yet — the school admin '
                        'assigns classes.',
                        icon: Icons.meeting_room_outlined);
                  }
                  return Column(
                    children: classes
                        .map((c) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading:
                                  const Icon(Icons.meeting_room_outlined),
                              title: Text(c.name),
                              subtitle: Text([
                                c.grade,
                                if (c.year != null) '${c.year}',
                              ].join(' · ')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  context.go(Routes.teacherClass(c.id)),
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
