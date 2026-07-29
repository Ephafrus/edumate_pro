import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/app_user.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../services/auth_service.dart';
import '../../router/app_router.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Super Admin's view of one school: its details, and the people who manage
/// it. Assigning an admin or principal by phone number either grants the
/// membership immediately (if that person already has an account) or leaves
/// an invite that becomes a membership when they first sign in.
class SuperSchoolDetailScreen extends StatelessWidget {
  const SuperSchoolDetailScreen({super.key, required this.schoolId});
  final String schoolId;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'School',
      breadcrumb: 'Super Admin > Schools > Detail',
      body: ContentContainer(
        maxWidth: 760,
        child: FutureBuilder<School?>(
          future: db.getSchool(schoolId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final school = snap.data;
            if (school == null) {
              return const EmptyState('School not found');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(school.name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    Switch(
                      value: school.active,
                      onChanged: (v) async {
                        await db.updateSchool(school.id, {'active': v});
                        if (context.mounted) {
                          showSnack(
                              context,
                              v
                                  ? '${school.name} is active.'
                                  : '${school.name} suspended.');
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () async {
                    await context.read<AuthController>().enterSchool(school);
                    if (context.mounted) context.go(Routes.adminHome);
                  },
                  icon: const Icon(Icons.login),
                  label: Text('Sign in to ${school.name}'),
                ),
                const SizedBox(height: 4),
                Text(
                    'Opens the school exactly as its admin sees it — learners, '
                    'classes, applications, payments and settings. Everything '
                    'you do there is recorded in the system log.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'School details',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoLine('Address',
                          school.address.isEmpty ? '—' : school.address),
                      InfoLine('Phone',
                          school.phone.isEmpty ? '—' : school.phone),
                      InfoLine('Email',
                          school.email.isEmpty ? '—' : school.email),
                      if (school.motto.isNotEmpty)
                        InfoLine('Motto', school.motto),
                      InfoLine('Created', formatDate(school.createdAt)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Management team',
                  trailing: FilledButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _AssignStaffDialog(school: school),
                    ),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Assign'),
                  ),
                  child: StreamBuilder<List<SchoolMembership>>(
                    stream: db.watchMembers(school.id,
                        roles: const [UserRole.admin, UserRole.principal]),
                    builder: (context, memberSnap) {
                      if (!memberSnap.hasData) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      final members = memberSnap.data!;
                      if (members.isEmpty) {
                        return const EmptyState(
                            'Nobody manages this school yet — assign an '
                            'admin so they can run it.',
                            icon: Icons.person_add_alt);
                      }
                      return Column(
                        children: members
                            .map((m) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                      child: Text(m.firstName.isEmpty
                                          ? '?'
                                          : m.firstName[0])),
                                  title: Text(m.fullName),
                                  subtitle: Text([
                                    m.role.label,
                                    if (m.phone != null) m.phone!,
                                    if (m.email != null &&
                                        m.email!.isNotEmpty)
                                      m.email!,
                                  ].join(' · ')),
                                  trailing: IconButton(
                                    tooltip: 'Remove from school',
                                    icon: const Icon(Icons.person_remove,
                                        size: 20),
                                    onPressed: () async {
                                      final ok = await confirmDialog(
                                        context,
                                        'Remove ${m.fullName}?',
                                        'They lose access to '
                                            '${school.name}. Their other '
                                            'schools are unaffected.',
                                        confirmLabel: 'Remove',
                                      );
                                      if (ok) {
                                        await db.removeMembership(
                                            school.id, m.uid);
                                      }
                                    },
                                  ),
                                ))
                            .toList(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Pending invitations',
                  child: StreamBuilder<List<StaffInvite>>(
                    stream: db.watchStaffInvites(school.id),
                    builder: (context, inviteSnap) {
                      final invites = (inviteSnap.data ?? [])
                          .where((i) => !i.claimed)
                          .toList();
                      if (invites.isEmpty) {
                        return const Text('No pending invitations',
                            style: TextStyle(color: Colors.grey));
                      }
                      return Column(
                        children: invites
                            .map((i) => ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading:
                                      const Icon(Icons.hourglass_top),
                                  title: Text(i.fullName.isEmpty
                                      ? i.phone
                                      : '${i.fullName} (${i.phone})'),
                                  subtitle: Text(
                                      '${i.role.label} · waiting for first '
                                      'sign-in'),
                                  trailing: IconButton(
                                    tooltip: 'Cancel invitation',
                                    icon:
                                        const Icon(Icons.delete_outline),
                                    onPressed: () =>
                                        db.deleteStaffInvite(i.id),
                                  ),
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

/// Assign an admin or principal to the school by phone number.
class _AssignStaffDialog extends StatefulWidget {
  const _AssignStaffDialog({required this.school});
  final School school;

  @override
  State<_AssignStaffDialog> createState() => _AssignStaffDialogState();
}

class _AssignStaffDialogState extends State<_AssignStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  UserRole _role = UserRole.admin;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _assign() async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<FirestoreService>();
    final me = context.read<AuthController>().appUser;
    final phone = AuthService.toE164(_phone.text);

    setState(() => _saving = true);
    try {
      // Already has an account? Grant the membership straight away.
      final existing = await db.findUserByPhone(phone);
      if (existing != null) {
        await db.setMembership(SchoolMembership(
          schoolId: widget.school.id,
          schoolName: widget.school.name,
          uid: existing.uid,
          role: _role,
          firstName: existing.firstName.isEmpty
              ? _first.text.trim()
              : existing.firstName,
          lastName: existing.lastName.isEmpty
              ? _last.text.trim()
              : existing.lastName,
          phone: phone,
          email: existing.email ??
              (_email.text.trim().isEmpty ? null : _email.text.trim()),
        ));
        if (!mounted) return;
        Navigator.of(context).pop();
        showSnack(
            context,
            '${existing.fullName} is now ${_role.label.toLowerCase()} at '
            '${widget.school.name}. They will see it next time they open '
            'the app.');
        return;
      }

      // Otherwise leave an invite that activates on first sign-in.
      await db.createStaffInvite(StaffInvite(
        id: '',
        phone: phone,
        role: _role,
        schoolId: widget.school.id,
        schoolName: widget.school.name,
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(
          context,
          'Invitation created${me == null ? '' : ''} — ask them to sign in '
          'with $phone.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not assign: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Assign to ${widget.school.name}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<UserRole>(
                  segments: UserRole.assignable
                      .map((r) =>
                          ButtonSegment(value: r, label: Text(r.label)))
                      .toList(),
                  selected: {_role},
                  onSelectionChanged: (s) =>
                      setState(() => _role = s.first),
                ),
                const SizedBox(height: 8),
                Text(
                    'Both roles manage the school in full — learners, '
                    'classes, applications, payments, broadcasts and staff.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: 'Cell phone number',
                    helperText: 'They sign in with this number',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) => (v == null || v.trim().length < 9)
                      ? 'Enter a valid cell number'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _first,
                  decoration:
                      const InputDecoration(labelText: 'First name'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'First name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _last,
                  decoration: const InputDecoration(labelText: 'Surname'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Surname is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(
                      labelText: 'Email address (optional)'),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _assign,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Assign'),
        ),
      ],
    );
  }
}
