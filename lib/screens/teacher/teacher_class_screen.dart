import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/academics.dart';
import '../../models/school.dart';
import '../../router/app_router.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// A teacher's view of one class: the learner register.
class TeacherClassScreen extends StatelessWidget {
  const TeacherClassScreen({super.key, required this.classId});
  final String classId;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Class',
      breadcrumb: 'My classes > Class register',
      body: ContentContainer(
        maxWidth: 760,
        child: StreamBuilder<List<SchoolClass>>(
          stream: db.watchClasses(),
          builder: (context, classSnap) {
            final cls = (classSnap.data ?? [])
                .where((c) => c.id == classId)
                .firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(cls?.name ?? 'Class',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (cls != null)
                  Text([cls.grade, if (cls.year != null) '${cls.year}']
                          .join(' · '),
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Subjects I teach in this class',
                  child: StreamBuilder<List<Subject>>(
                    stream: db.watchSubjectsForClass(classId),
                    builder: (context, snap) {
                      final subjects = snap.data ?? [];
                      if (subjects.isEmpty) {
                        return const Text(
                            'No subjects added to this class yet — the '
                            'school admin sets these up.',
                            style: TextStyle(color: Colors.grey));
                      }
                      return Column(
                        children: subjects
                            .map((s) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                      Icons.menu_book_outlined),
                                  title: Text(s.name),
                                  subtitle: Text(s.teacherName.isEmpty
                                      ? 'No teacher assigned'
                                      : s.teacherName),
                                  trailing:
                                      const Icon(Icons.chevron_right),
                                  onTap: () => context
                                      .go(Routes.teacherSubject(s.id)),
                                ))
                            .toList(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Learners',
                  child: StreamBuilder<List<Learner>>(
                    stream: db.watchLearnersInClass(classId),
                    builder: (context, snap) {
                      if (!snap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final learners = snap.data!;
                      if (learners.isEmpty) {
                        return const EmptyState(
                            'No learners assigned to this class yet.',
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
                                    if (l.dateOfBirth != null)
                                      'Born ${formatDate(l.dateOfBirth)}',
                                    if (l.gender != null) l.gender!.label,
                                  ].join(' · ')),
                                ))
                            .toList(),
                      );
                    },
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
