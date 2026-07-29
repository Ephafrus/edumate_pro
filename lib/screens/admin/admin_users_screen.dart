import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/activity_log.dart';
import '../../models/application.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../services/activity_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Everybody who belongs to this school, in one directory.
///
/// A school's people arrive from two directions — staff are invited by the
/// office, parents join the school themselves to apply for a child — so the
/// list is grouped by what they actually are:
///
///  * **Staff** — admins, principals and teachers,
///  * **Parents** — those with a child on the school's roll, and
///  * **Applicants** — parents who have joined but have no enrolled child
///    yet, whether they have an application in flight or have not started
///    one.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

/// Which group a member falls into.
enum _Group { staff, parents, applicants }

extension on _Group {
  String get label => switch (this) {
        _Group.staff => 'Staff',
        _Group.parents => 'Parents',
        _Group.applicants => 'Applicants',
      };

  String get blurb => switch (this) {
        _Group.staff => 'Admins, principals and teachers',
        _Group.parents => 'Parents with a child on the roll',
        _Group.applicants => 'Joined the school, no enrolled child yet',
      };

  IconData get icon => switch (this) {
        _Group.staff => Icons.badge_outlined,
        _Group.parents => Icons.family_restroom_outlined,
        _Group.applicants => Icons.person_search_outlined,
      };

  Color get colour => switch (this) {
        _Group.staff => Colors.deepPurple,
        _Group.parents => Colors.indigo,
        _Group.applicants => Colors.orange,
      };
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  String _query = '';
  _Group? _only;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Users',
      breadcrumb: 'Overview > Users',
      body: ContentContainer(
        maxWidth: 900,
        child: StreamBuilder<List<SchoolMembership>>(
          stream: db.watchSchoolMembers(),
          builder: (context, memberSnap) {
            if (memberSnap.hasError) {
              return const EmptyState(
                  'Could not load the directory. Deploy the latest Firestore '
                  'rules and try again.',
                  icon: Icons.error_outline);
            }
            if (!memberSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final members = memberSnap.data!;

            return StreamBuilder<List<Learner>>(
              stream: db.watchLearners(),
              builder: (context, learnerSnap) {
                final learners = learnerSnap.data ?? const <Learner>[];

                // uid -> the children of theirs who are actually enrolled.
                final childrenByParent = <String, List<Learner>>{};
                for (final l in learners) {
                  for (final uid in l.parentUids) {
                    childrenByParent.putIfAbsent(uid, () => []).add(l);
                  }
                }

                return StreamBuilder<List<EnrollmentApplication>>(
                  stream: db.watchApplications(),
                  builder: (context, appSnap) {
                    final applications =
                        appSnap.data ?? const <EnrollmentApplication>[];
                    final openApplications = <String, int>{};
                    for (final a in applications) {
                      if (a.status == ApplicationStatus.enrolled) continue;
                      openApplications[a.parentUid] =
                          (openApplications[a.parentUid] ?? 0) + 1;
                    }

                    _Group groupOf(SchoolMembership m) {
                      if (m.role.isStaff) return _Group.staff;
                      final enrolled = (childrenByParent[m.uid] ?? const [])
                          .where((l) => l.status == LearnerStatus.active);
                      return enrolled.isEmpty
                          ? _Group.applicants
                          : _Group.parents;
                    }

                    final grouped = <_Group, List<SchoolMembership>>{
                      for (final g in _Group.values) g: <SchoolMembership>[],
                    };
                    for (final m in members) {
                      grouped[groupOf(m)]!.add(m);
                    }

                    bool matches(SchoolMembership m) {
                      if (_query.isEmpty) return true;
                      return m.fullName.toLowerCase().contains(_query) ||
                          (m.phone ?? '').toLowerCase().contains(_query) ||
                          (m.email ?? '').toLowerCase().contains(_query) ||
                          m.role.label.toLowerCase().contains(_query);
                    }

                    final recent = [...members]..sort((a, b) =>
                        (b.joinedAt ?? DateTime(0))
                            .compareTo(a.joinedAt ?? DateTime(0)));

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Users',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                            '${members.length} '
                            '${members.length == 1 ? 'person has' : 'people have'} '
                            'joined this school.',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Search name, phone, email or role…',
                          ),
                          onChanged: (v) =>
                              setState(() => _query = v.trim().toLowerCase()),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text('Everyone (${members.length})'),
                                  selected: _only == null,
                                  onSelected: (_) =>
                                      setState(() => _only = null),
                                ),
                              ),
                              ..._Group.values.map((g) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      avatar: Icon(g.icon, size: 16),
                                      label: Text(
                                          '${g.label} (${grouped[g]!.length})'),
                                      selected: _only == g,
                                      onSelected: (_) =>
                                          setState(() => _only = g),
                                    ),
                                  )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_only == null && _query.isEmpty && recent.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: SectionCard(
                              title: 'Recently joined',
                              child: Column(
                                children: recent
                                    .take(5)
                                    .map((m) => ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          leading: CircleAvatar(
                                              radius: 16,
                                              child: Text(_initial(m))),
                                          title: Text(m.fullName),
                                          subtitle: Text([
                                            m.role.label,
                                            if (m.joinedAt != null)
                                              'joined ${formatDate(m.joinedAt)}',
                                          ].join(' · ')),
                                        ))
                                    .toList(),
                              ),
                            ),
                          ),
                        for (final g in _Group.values)
                          if (_only == null || _only == g)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _GroupCard(
                                group: g,
                                members:
                                    grouped[g]!.where(matches).toList(),
                                childrenByParent: childrenByParent,
                                openApplications: openApplications,
                              ),
                            ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

String _initial(SchoolMembership m) =>
    m.fullName.isEmpty ? '?' : m.fullName[0].toUpperCase();

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.members,
    required this.childrenByParent,
    required this.openApplications,
  });

  final _Group group;
  final List<SchoolMembership> members;
  final Map<String, List<Learner>> childrenByParent;
  final Map<String, int> openApplications;

  String _subtitle(SchoolMembership m) {
    final children = childrenByParent[m.uid] ?? const <Learner>[];
    final enrolled =
        children.where((l) => l.status == LearnerStatus.active).toList();
    final open = openApplications[m.uid] ?? 0;
    return [
      m.role.label,
      if (m.phone != null && m.phone!.isNotEmpty) m.phone!,
      if (m.email != null && m.email!.isNotEmpty) m.email!,
      if (group != _Group.staff && enrolled.isNotEmpty)
        '${enrolled.length} enrolled: ${enrolled.map((l) => l.fullName).join(', ')}',
      if (group == _Group.applicants && open > 0)
        '$open application${open == 1 ? '' : 's'} in progress',
      if (group == _Group.applicants && open == 0 && children.isEmpty)
        'no application yet',
      if (m.joinedAt != null) 'joined ${formatDate(m.joinedAt)}',
      if (!m.active) 'deactivated',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: group.label,
      trailing: Text('${members.length}',
          style: Theme.of(context).textTheme.bodySmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(group.blurb,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          if (members.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Nobody here', style: TextStyle(color: Colors.grey)),
            )
          else
            ...members.map((m) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: group.colour.withValues(alpha: 0.15),
                    foregroundColor: group.colour,
                    child: Text(_initial(m)),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(m.fullName,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      StatusChip(m.role.label, group.colour),
                    ],
                  ),
                  subtitle: Text(_subtitle(m)),
                  trailing: _MemberMenu(member: m),
                )),
        ],
      ),
    );
  }
}

/// Per-person actions: change what they are at this school, suspend them, or
/// remove them from the school entirely.
class _MemberMenu extends StatelessWidget {
  const _MemberMenu({required this.member});
  final SchoolMembership member;

  Future<void> _changeRole(BuildContext context, UserRole role) async {
    if (role == member.role) return;
    final db = context.read<FirestoreService>();
    final activity = context.read<ActivityService>();
    final ok = await confirmDialog(
      context,
      'Make ${member.fullName} a ${role.label.toLowerCase()}?',
      role.isStaff
          ? 'They get ${role.label.toLowerCase()} access at this school the '
              'next time their app refreshes.'
          : 'They lose staff access at this school.',
      confirmLabel: 'Change role',
    );
    if (!ok) return;
    try {
      await db.setMembership(SchoolMembership(
        schoolId: member.schoolId,
        schoolName: member.schoolName,
        uid: member.uid,
        role: role,
        firstName: member.firstName,
        lastName: member.lastName,
        phone: member.phone,
        email: member.email,
        active: member.active,
        joinedAt: member.joinedAt,
      ));
      activity.log(ActivityAction.memberRoleChanged,
          target: member.fullName,
          details: '${member.role.label} → ${role.label}');
      if (context.mounted) {
        showSnack(context, '${member.fullName} is now a ${role.label}.');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not change role: $e');
    }
  }

  Future<void> _setActive(BuildContext context, bool active) async {
    final db = context.read<FirestoreService>();
    final activity = context.read<ActivityService>();
    if (!active) {
      final ok = await confirmDialog(
        context,
        'Deactivate ${member.fullName}?',
        'They keep their account but lose access to this school.',
        confirmLabel: 'Deactivate',
      );
      if (!ok) return;
    }
    try {
      await db.setMemberActive(member.schoolId, member.uid, active);
      if (!active) {
        activity.log(ActivityAction.memberDeactivated,
            target: member.fullName, details: member.role.label);
      }
      if (context.mounted) {
        showSnack(context,
            active ? '${member.fullName} reactivated.' : 'Deactivated.');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not update: $e');
    }
  }

  Future<void> _remove(BuildContext context) async {
    final db = context.read<FirestoreService>();
    final activity = context.read<ActivityService>();
    final ok = await confirmDialog(
      context,
      'Remove ${member.fullName} from this school?',
      'Their learner, payment and application records stay. They can join '
          'again as a parent.',
      confirmLabel: 'Remove',
    );
    if (!ok) return;
    try {
      await db.removeMembership(member.schoolId, member.uid);
      activity.log(ActivityAction.memberRemoved,
          target: member.fullName, details: member.role.label);
      if (context.mounted) showSnack(context, 'Removed from the school.');
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not remove: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Manage',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'activate':
            _setActive(context, true);
          case 'deactivate':
            _setActive(context, false);
          case 'remove':
            _remove(context);
          default:
            _changeRole(context, UserRole.fromString(value));
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
            enabled: false,
            child: Text('Role at this school',
                style: TextStyle(fontSize: 12, color: Colors.grey))),
        ...UserRole.values.map((r) => PopupMenuItem(
              value: r.name,
              child: Row(
                children: [
                  Icon(
                      r == member.role
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18),
                  const SizedBox(width: 8),
                  Text(r.label),
                ],
              ),
            )),
        const PopupMenuDivider(),
        if (member.active)
          const PopupMenuItem(value: 'deactivate', child: Text('Deactivate'))
        else
          const PopupMenuItem(value: 'activate', child: Text('Reactivate')),
        const PopupMenuItem(
            value: 'remove', child: Text('Remove from school')),
      ],
    );
  }
}
