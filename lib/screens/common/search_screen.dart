import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/academics.dart';
import '../../models/activity_log.dart';
import '../../models/app_user.dart';
import '../../models/application.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../router/app_router.dart';
import '../../services/activity_service.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// One search result, whatever it points at.
class _Hit {
  const _Hit(this.icon, this.title, this.subtitle, this.group, {this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final String group;
  final VoidCallback? onTap;
}

/// Role-scoped search — one box that finds whatever the signed-in user is
/// allowed to see:
///  * **Super Admin** — schools across the platform;
///  * **School admin / principal** — learners, classes, subjects, staff,
///    parents, applications;
///  * **Teacher** — their own classes, subjects and the learners in them.
///
/// Everything is matched client-side over the school's live streams, so
/// results update as data changes and partial names match anywhere in the
/// string (Firestore itself has no substring search).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _matches(String? value) =>
      value != null && value.toLowerCase().contains(_query);

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.appUser;
    if (user == null) return const AppShell(title: 'Search', body: SizedBox());

    return AppShell(
      title: 'Search',
      body: ContentContainer(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Search',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                auth.isSuperAdmin
                    ? 'Find any school on the platform.'
                    : user.isStaff && !user.isManager
                        ? 'Find your classes, subjects and learners.'
                        : 'Find learners, classes, subjects, staff, parents '
                            'and applications at '
                            '${auth.activeSchoolName.isEmpty ? 'your school' : auth.activeSchoolName}.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Type a name…',
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
              // Logged on submit only, so the audit trail records intent
              // rather than every keystroke.
              onSubmitted: (v) => context
                  .read<ActivityService>()
                  .log(ActivityAction.searchPerformed, target: v.trim()),
            ),
            const SizedBox(height: 16),
            if (_query.isEmpty)
              const EmptyState('Start typing to search.',
                  icon: Icons.search)
            else if (auth.isSuperAdmin)
              _SuperResults(query: _query, matches: _matches)
            else
              _SchoolResults(
                  query: _query, matches: _matches, user: user),
          ],
        ),
      ),
    );
  }
}

/// Super Admin: every school on the platform.
class _SuperResults extends StatelessWidget {
  const _SuperResults({required this.query, required this.matches});
  final String query;
  final bool Function(String?) matches;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    return StreamBuilder<List<School>>(
      stream: db.watchSchools(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final hits = snap.data!
            .where((s) =>
                matches(s.name) || matches(s.address) || matches(s.email))
            .map((s) => _Hit(Icons.school, s.name,
                [s.address, s.phone].where((e) => e.isNotEmpty).join(' · '),
                'Schools',
                onTap: () => context.go(Routes.superSchoolDetail(s.id))))
            .toList();
        return _ResultList(hits: hits);
      },
    );
  }
}

/// Staff: everything inside the active school that their role may see.
class _SchoolResults extends StatelessWidget {
  const _SchoolResults({
    required this.query,
    required this.matches,
    required this.user,
  });

  final String query;
  final bool Function(String?) matches;
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final isManager = user.isManager;

    return StreamBuilder<List<Learner>>(
      stream: db.watchLearners(),
      builder: (context, learnerSnap) {
        return StreamBuilder<List<SchoolClass>>(
          stream: isManager
              ? db.watchClasses()
              : db.watchClassesForTeacher(user.uid),
          builder: (context, classSnap) {
            return StreamBuilder<List<Subject>>(
              stream: isManager
                  ? db.watchSubjects()
                  : db.watchSubjectsForTeacher(user.uid),
              builder: (context, subjectSnap) {
                if (!learnerSnap.hasData || !classSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final classes = classSnap.data!;
                final subjects = subjectSnap.data ?? [];
                final myClassIds = classes.map((c) => c.id).toSet();

                // Teachers only see learners in the classes they teach.
                final learners = learnerSnap.data!.where((l) {
                  if (isManager) return true;
                  return l.classId != null &&
                      myClassIds.contains(l.classId);
                });

                final hits = <_Hit>[
                  ...learners
                      .where((l) =>
                          matches(l.fullName) || matches(l.idNumber))
                      .map((l) => _Hit(
                            Icons.child_care_outlined,
                            l.fullName,
                            [
                              if (l.grade.isNotEmpty) l.grade,
                              l.className.isEmpty ? 'No class' : l.className,
                              l.status.label,
                            ].join(' · '),
                            'Learners',
                            onTap: isManager
                                ? () => context.go(Routes.adminLearners)
                                : null,
                          )),
                  ...classes
                      .where((c) =>
                          matches(c.name) ||
                          matches(c.grade) ||
                          matches(c.teacherName))
                      .map((c) => _Hit(
                            Icons.meeting_room_outlined,
                            c.name,
                            [
                              c.grade,
                              if (c.teacherName.isNotEmpty)
                                'Teacher: ${c.teacherName}',
                            ].join(' · '),
                            'Classes',
                            onTap: () => context.go(isManager
                                ? Routes.adminClasses
                                : Routes.teacherClass(c.id)),
                          )),
                  ...subjects
                      .where((s) =>
                          matches(s.name) || matches(s.teacherName))
                      .map((s) => _Hit(
                            Icons.menu_book_outlined,
                            s.name,
                            [
                              s.className,
                              if (s.teacherName.isNotEmpty) s.teacherName,
                            ].join(' · '),
                            'Subjects',
                            onTap: () => context.go(isManager
                                ? Routes.adminClasses
                                : Routes.teacherSubject(s.id)),
                          )),
                ];

                if (!isManager) return _ResultList(hits: hits);

                // Managers additionally search people and applications.
                return StreamBuilder<List<SchoolMembership>>(
                  stream: db.watchSchoolMembers(),
                  builder: (context, memberSnap) {
                    return StreamBuilder<List<EnrollmentApplication>>(
                      stream: db.watchApplications(),
                      builder: (context, appSnap) {
                        final people = (memberSnap.data ?? []).where((m) =>
                            matches(m.fullName) ||
                            matches(m.phone) ||
                            matches(m.email));
                        final apps = (appSnap.data ?? []).where((a) =>
                            matches(a.learnerFullName) ||
                            matches(a.guardianFullName) ||
                            matches(a.guardianEmail));
                        return _ResultList(hits: [
                          ...hits,
                          ...people.map((m) => _Hit(
                                m.role == UserRole.parent
                                    ? Icons.family_restroom
                                    : Icons.badge_outlined,
                                m.fullName,
                                [
                                  m.role.label,
                                  if (m.phone != null) m.phone!,
                                  if (m.email != null && m.email!.isNotEmpty)
                                    m.email!,
                                ].join(' · '),
                                m.role == UserRole.parent
                                    ? 'Parents'
                                    : 'Staff',
                                onTap: m.role == UserRole.parent
                                    ? null
                                    : () => context.go(Routes.adminStaff),
                              )),
                          ...apps.map((a) => _Hit(
                                Icons.assignment_outlined,
                                a.learnerFullName,
                                '${a.gradeApplyingFor} · ${a.status.label} · '
                                    'guardian ${a.guardianFullName}',
                                'Applications',
                                onTap: () => context.go(
                                    Routes.adminApplicationDetail(a.id)),
                              )),
                        ]);
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Renders hits grouped by kind.
class _ResultList extends StatelessWidget {
  const _ResultList({required this.hits});
  final List<_Hit> hits;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return const EmptyState('No matches found.', icon: Icons.search_off);
    }
    final groups = <String, List<_Hit>>{};
    for (final h in hits) {
      groups.putIfAbsent(h.group, () => []).add(h);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${hits.length} result(s)',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        ...groups.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SectionCard(
                title: '${e.key} (${e.value.length})',
                child: Column(
                  children: e.value
                      .take(25)
                      .map((h) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(h.icon),
                            title: Text(h.title),
                            subtitle:
                                h.subtitle.isEmpty ? null : Text(h.subtitle),
                            trailing: h.onTap == null
                                ? null
                                : const Icon(Icons.chevron_right),
                            onTap: h.onTap,
                          ))
                      .toList(),
                ),
              ),
            )),
      ],
    );
  }
}
