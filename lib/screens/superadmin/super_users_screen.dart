import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/activity_log.dart';
import '../../models/app_user.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../services/activity_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// The Super Admin's user directory: every account on the platform, with
/// search, the schools each person already belongs to, and one-tap
/// assignment to a school.
///
/// Assignment takes effect immediately — the person's app is watching their
/// memberships live, so a parent promoted to school admin sees that school
/// (and its admin dashboard) without signing out and back in.
class SuperUsersScreen extends StatefulWidget {
  const SuperUsersScreen({super.key});

  @override
  State<SuperUsersScreen> createState() => _SuperUsersScreenState();
}

class _SuperUsersScreenState extends State<SuperUsersScreen> {
  String _query = '';
  bool _onlyUnassigned = false;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Users',
      breadcrumb: 'Super Admin > Users',
      body: ContentContainer(
        maxWidth: 860,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('All users',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'Everyone who has signed in. Assign somebody to a school to '
                'make them its admin, principal or teacher — they see it '
                'straight away.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name, phone or email…',
              ),
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('Not in any school yet'),
                selected: _onlyUnassigned,
                onSelected: (v) => setState(() => _onlyUnassigned = v),
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<AppUser>>(
              stream: db.watchAllUsers(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final users = snap.data!.where((u) {
                  if (_query.isEmpty) return true;
                  return u.fullName.toLowerCase().contains(_query) ||
                      (u.phone ?? '').toLowerCase().contains(_query) ||
                      (u.email ?? '').toLowerCase().contains(_query);
                }).toList();
                if (users.isEmpty) {
                  return const EmptyState('No users match that search.',
                      icon: Icons.person_search);
                }
                return Column(
                  children: users
                      .map((u) => _UserCard(
                            user: u,
                            onlyUnassigned: _onlyUnassigned,
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

/// One person, with their memberships loaded live so the list always shows
/// where they currently belong.
class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.onlyUnassigned});
  final AppUser user;
  final bool onlyUnassigned;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return StreamBuilder<List<SchoolMembership>>(
      stream: db.watchMembershipsForUser(user.uid),
      builder: (context, snap) {
        final memberships = snap.data ?? const <SchoolMembership>[];
        if (onlyUnassigned && memberships.isNotEmpty) {
          return const SizedBox.shrink();
        }
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      child: Text(user.firstName.isEmpty
                          ? '?'
                          : user.firstName[0].toUpperCase()),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.fullName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          Text(
                            [
                              if (user.phone != null) user.phone!,
                              if (user.email != null &&
                                  user.email!.isNotEmpty)
                                user.email!,
                            ].join(' · '),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    if (user.superAdmin)
                      const StatusChip('Super Admin', Colors.purple),
                  ],
                ),
                const SizedBox(height: 10),
                if (memberships.isEmpty)
                  Text('Not assigned to any school',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.orange))
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: memberships
                        .map((m) => Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(Icons.apartment, size: 16),
                              label: Text(
                                  '${m.schoolName} · ${m.role.label}'),
                              onDeleted: () async {
                                final ok = await confirmDialog(
                                  context,
                                  'Remove from ${m.schoolName}?',
                                  '${user.fullName} loses access to that '
                                      'school. Their other schools are '
                                      'unaffected.',
                                  confirmLabel: 'Remove',
                                );
                                if (!ok) return;
                                await db.removeMembership(
                                    m.schoolId, user.uid);
                                if (context.mounted) {
                                  context.read<ActivityService>().log(
                                      ActivityAction.memberRemoved,
                                      target: user.fullName,
                                      details: m.schoolName);
                                }
                              },
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => _AssignToSchoolDialog(user: user),
                      ),
                      icon: const Icon(Icons.add_business, size: 18),
                      label: const Text('Assign to school'),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final grant = !user.superAdmin;
                        final ok = await confirmDialog(
                          context,
                          grant
                              ? 'Make ${user.fullName} a Super Admin?'
                              : 'Remove Super Admin from ${user.fullName}?',
                          grant
                              ? 'They will be able to create schools and '
                                  'assign anyone, across the whole platform.'
                              : 'They keep any school memberships they hold.',
                          confirmLabel: grant ? 'Grant' : 'Revoke',
                        );
                        if (!ok) return;
                        await db.setSuperAdmin(user.uid, grant);
                        if (context.mounted) {
                          context.read<ActivityService>().log(
                              ActivityAction.superAdminGranted,
                              target: user.fullName,
                              details: grant ? 'granted' : 'revoked');
                          showSnack(
                              context,
                              grant
                                  ? '${user.fullName} is now a Super Admin.'
                                  : 'Super Admin removed.');
                        }
                      },
                      icon: Icon(
                          user.superAdmin
                              ? Icons.remove_moderator
                              : Icons.admin_panel_settings,
                          size: 18),
                      label: Text(user.superAdmin
                          ? 'Revoke Super Admin'
                          : 'Make Super Admin'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pick a school and a role, and grant the membership immediately.
class _AssignToSchoolDialog extends StatefulWidget {
  const _AssignToSchoolDialog({required this.user});
  final AppUser user;

  @override
  State<_AssignToSchoolDialog> createState() => _AssignToSchoolDialogState();
}

class _AssignToSchoolDialogState extends State<_AssignToSchoolDialog> {
  String? _schoolId;
  UserRole _role = UserRole.admin;
  bool _saving = false;

  Future<void> _assign(List<School> schools) async {
    final school = schools.where((s) => s.id == _schoolId).firstOrNull;
    if (school == null) {
      showSnack(context, 'Pick a school');
      return;
    }
    final db = context.read<FirestoreService>();
    final activity = context.read<ActivityService>();
    setState(() => _saving = true);
    try {
      await db.setMembership(SchoolMembership(
        schoolId: school.id,
        schoolName: school.name,
        uid: widget.user.uid,
        role: _role,
        firstName: widget.user.firstName,
        lastName: widget.user.lastName,
        phone: widget.user.phone,
        email: widget.user.email,
      ));
      activity.log(ActivityAction.memberAssigned,
          target: widget.user.fullName,
          details: '${_role.label} at ${school.name}');
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(
          context,
          '${widget.user.fullName} is now ${_role.label.toLowerCase()} at '
          '${school.name}.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not assign: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AlertDialog(
      title: Text('Assign ${widget.user.fullName}'),
      content: SizedBox(
        width: 440,
        child: StreamBuilder<List<School>>(
          stream: db.watchSchools(),
          builder: (context, snap) {
            final schools = snap.data ?? const <School>[];
            if (snap.hasData && schools.isEmpty) {
              return const Text(
                  'No schools exist yet — create one first, then assign '
                  'somebody to run it.');
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue:
                      schools.any((s) => s.id == _schoolId) ? _schoolId : null,
                  decoration: const InputDecoration(labelText: 'School'),
                  items: schools
                      .map((s) => DropdownMenuItem(
                          value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _schoolId = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: UserRole.values
                      .map((r) => DropdownMenuItem(
                          value: r, child: Text(r.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
                const SizedBox(height: 8),
                Text(
                    _role.isManager
                        ? 'Admins and principals manage the whole school.'
                        : _role == UserRole.teacher
                            ? 'Teachers see their own classes and subjects.'
                            : 'Parents apply for children and track them.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        StreamBuilder<List<School>>(
          stream: db.watchSchools(),
          builder: (context, snap) => FilledButton(
            onPressed: _saving
                ? null
                : () => _assign(snap.data ?? const <School>[]),
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Assign'),
          ),
        ),
      ],
    );
  }
}
