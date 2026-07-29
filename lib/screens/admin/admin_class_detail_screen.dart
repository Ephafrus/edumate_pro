import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/academics.dart';
import '../../models/school.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/progress_report.dart';

/// A class, opened from the classes list: who teaches it, what subjects are
/// taught in it (and by whom), and the learners on its register — each
/// expandable to their progress report.
///
/// Available to school admins and principals; teachers get the equivalent
/// view for the classes they teach.
class AdminClassDetailScreen extends StatelessWidget {
  const AdminClassDetailScreen({super.key, required this.classId});
  final String classId;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Class',
      breadcrumb: 'Overview > Classes > Class',
      body: ContentContainer(
        maxWidth: 860,
        child: StreamBuilder<List<SchoolClass>>(
          stream: db.watchClasses(),
          builder: (context, classSnap) {
            if (!classSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final cls =
                classSnap.data!.where((c) => c.id == classId).firstOrNull;
            if (cls == null) {
              return const EmptyState('Class not found.');
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(cls.name,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                    [
                      cls.grade,
                      if (cls.year != null) '${cls.year}',
                      cls.teacherName.isEmpty
                          ? 'No class teacher assigned'
                          : 'Class teacher: ${cls.teacherName}',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),

                // ---- Subjects ------------------------------------------
                SectionCard(
                  title: 'Subjects',
                  child: StreamBuilder<List<Subject>>(
                    stream: db.watchSubjectsForClass(classId),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final subjects = snap.data!;
                      if (subjects.isEmpty) {
                        return const EmptyState(
                            'No subjects yet — add them from the Classes '
                            'list, then assign a teacher to each.',
                            icon: Icons.menu_book_outlined);
                      }
                      return Column(
                        children: subjects
                            .map((s) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(
                                      child: Icon(
                                          Icons.menu_book_outlined,
                                          size: 18)),
                                  title: Text(s.name),
                                  subtitle: Text(s.teacherName.isEmpty
                                      ? 'No teacher assigned'
                                      : s.teacherName),
                                  trailing: s.teacherName.isEmpty
                                      ? const StatusChip(
                                          'Unassigned', Colors.orange)
                                      : null,
                                ))
                            .toList(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // ---- Learners ------------------------------------------
                StreamBuilder<List<Learner>>(
                  stream: db.watchLearnersInClass(classId),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    final learners = snap.data!;
                    return SectionCard(
                      title: 'Learners',
                      trailing: Text('${learners.length} on register',
                          style: Theme.of(context).textTheme.bodySmall),
                      child: learners.isEmpty
                          ? const EmptyState(
                              'No learners assigned to this class yet — '
                              'assign them from the Learners page.',
                              icon: Icons.child_care_outlined)
                          : Column(
                              children: learners
                                  .map((l) => ExpansionTile(
                                        tilePadding: EdgeInsets.zero,
                                        childrenPadding:
                                            const EdgeInsets.only(
                                                bottom: 12),
                                        leading: CircleAvatar(
                                            child: Text(l.firstName.isEmpty
                                                ? '?'
                                                : l.firstName[0])),
                                        title: Text(l.fullName),
                                        subtitle: Text([
                                          if (l.grade.isNotEmpty) l.grade,
                                          l.status.label,
                                          if (l.attendanceStatus != null)
                                            l.attendanceStatus!.stateLabel,
                                        ].join(' · ')),
                                        trailing: l.attendanceStatus != null
                                            ? StatusChip(
                                                l.attendanceStatus!
                                                    .stateLabel,
                                                l.isInSchool
                                                    ? Colors.green
                                                    : Colors.orange,
                                              )
                                            : null,
                                        children: [
                                          ProgressReport(
                                              learnerId: l.id,
                                              showEmptyHint: false),
                                        ],
                                      ))
                                  .toList(),
                            ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
