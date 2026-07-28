import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../models/academics.dart';
import '../../models/school.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/progress_report.dart';

/// A parent's view of one child: progress (marks per subject), the homework
/// they have been set, and what they are doing in class (lesson plans).
class ChildProgressScreen extends StatelessWidget {
  const ChildProgressScreen({super.key, required this.learnerId});
  final String learnerId;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final uid = context.watch<AuthController>().appUser?.uid ?? '';
    final scheme = Theme.of(context).colorScheme;

    return AppShell(
      title: 'Progress',
      breadcrumb: 'Home > My child',
      body: ContentContainer(
        maxWidth: 820,
        child: StreamBuilder<List<Learner>>(
          stream: db.watchLearnersForParent(uid),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final learner =
                snap.data!.where((l) => l.id == learnerId).firstOrNull;
            if (learner == null) {
              return const EmptyState(
                  'That learner is not linked to your account.');
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: scheme.heroGradient,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.25),
                        child: Text(
                          learner.firstName.isEmpty
                              ? '?'
                              : learner.firstName[0],
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(learner.fullName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800)),
                            Text(
                              [
                                if (learner.grade.isNotEmpty) learner.grade,
                                learner.className.isEmpty
                                    ? 'No class yet'
                                    : learner.className,
                                if (learner.attendanceStatus != null)
                                  learner.attendanceStatus!.stateLabel,
                              ].join(' · '),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Progress',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ProgressReport(learnerId: learner.id),
                const SizedBox(height: 16),
                if (learner.classId != null &&
                    learner.classId!.isNotEmpty) ...[
                  SectionCard(
                    title: 'Homework',
                    child: StreamBuilder<List<Homework>>(
                      stream: db.watchHomeworkForClass(learner.classId!),
                      builder: (context, hwSnap) {
                        final items = hwSnap.data ?? [];
                        if (items.isEmpty) {
                          return const Text('No homework set',
                              style: TextStyle(color: Colors.grey));
                        }
                        return Column(
                          children: items
                              .take(10)
                              .map((h) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons
                                        .assignment_turned_in_outlined),
                                    title: Text(h.title),
                                    subtitle: Text([
                                      h.subjectName,
                                      'Due ${formatDate(h.dueDate)}',
                                      if (h.instructions.isNotEmpty)
                                        h.instructions,
                                    ].join(' · ')),
                                    trailing: h.attachmentUrl.isEmpty
                                        ? StatusChip(
                                            h.isOverdue
                                                ? 'Past due'
                                                : 'In ${h.daysUntilDue}d',
                                            h.isOverdue
                                                ? Colors.grey
                                                : Colors.blue,
                                          )
                                        : IconButton(
                                            tooltip: 'Open worksheet',
                                            icon: const Icon(
                                                Icons.attach_file),
                                            onPressed: () => launchUrl(
                                                Uri.parse(
                                                    h.attachmentUrl),
                                                mode: LaunchMode
                                                    .externalApplication),
                                          ),
                                  ))
                              .toList(),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'What they are doing in class',
                    child: StreamBuilder<List<LessonPlan>>(
                      stream:
                          db.watchLessonPlansForClass(learner.classId!),
                      builder: (context, planSnap) {
                        final plans = planSnap.data ?? [];
                        if (plans.isEmpty) {
                          return const Text('No lesson plans published yet',
                              style: TextStyle(color: Colors.grey));
                        }
                        return Column(
                          children: plans
                              .take(10)
                              .map((p) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                        Icons.menu_book_outlined),
                                    title: Text(p.title),
                                    subtitle: Text([
                                      p.subjectName,
                                      p.endDate == null
                                          ? formatDate(p.date)
                                          : '${formatDate(p.date)} – ${formatDate(p.endDate)}',
                                      if (p.content.isNotEmpty) p.content,
                                    ].join(' · ')),
                                    isThreeLine: p.content.isNotEmpty,
                                  ))
                              .toList(),
                        );
                      },
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
