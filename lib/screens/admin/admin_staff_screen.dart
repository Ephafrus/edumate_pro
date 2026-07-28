import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/app_user.dart';
import '../../models/enums.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Staff management: add teachers (and other admins) by phone number. The
/// invite is keyed on the E.164 number — when that number first signs in with
/// phone OTP, the account is created with the invited role automatically.
class AdminStaffScreen extends StatelessWidget {
  const AdminStaffScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Staff',
      breadcrumb: 'Dashboard > Staff',
      body: ContentContainer(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Teachers & staff',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                FilledButton.icon(
                  onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const _AddStaffDialog()),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add staff member'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Active staff',
              child: StreamBuilder<List<AppUser>>(
                stream: db.watchStaff(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final staff = snap.data!;
                  if (staff.isEmpty) {
                    return const EmptyState(
                        'No staff accounts yet. Add a staff member — their '
                        'account activates when they first sign in.');
                  }
                  return Column(
                    children: staff
                        .map((u) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                  child: Text(u.firstName.isEmpty
                                      ? '?'
                                      : u.firstName[0])),
                              title: Text(u.fullName),
                              subtitle: Text([
                                u.role.label,
                                if (u.phone != null) u.phone!,
                                if (u.email != null && u.email!.isNotEmpty)
                                  u.email!,
                              ].join(' · ')),
                              trailing: u.active
                                  ? IconButton(
                                      tooltip: 'Deactivate',
                                      icon: const Icon(Icons.block,
                                          color: Colors.red, size: 20),
                                      onPressed: () async {
                                        final ok = await confirmDialog(
                                          context,
                                          'Deactivate ${u.fullName}?',
                                          'They will keep their account but '
                                              'lose access.',
                                          confirmLabel: 'Deactivate',
                                        );
                                        if (ok) {
                                          await db.updateUser(
                                              u.uid, {'active': false});
                                        }
                                      },
                                    )
                                  : TextButton(
                                      onPressed: () => db.updateUser(
                                          u.uid, {'active': true}),
                                      child: const Text('Reactivate'),
                                    ),
                            ))
                        .toList(),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Pending invites',
              child: StreamBuilder<List<StaffInvite>>(
                stream: db.watchStaffInvites(
                    context.read<AuthController>().activeSchoolId ?? ''),
                builder: (context, snap) {
                  final invites =
                      (snap.data ?? []).where((i) => !i.claimed).toList();
                  if (invites.isEmpty) {
                    return const Text('No pending invites',
                        style: TextStyle(color: Colors.grey));
                  }
                  return Column(
                    children: invites
                        .map((i) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.hourglass_top),
                              title: Text(i.fullName.isEmpty
                                  ? i.phone
                                  : '${i.fullName} (${i.phone})'),
                              subtitle: Text(
                                  '${i.role.label} · waiting for first sign-in'),
                              trailing: IconButton(
                                tooltip: 'Cancel invite',
                                icon: const Icon(Icons.delete_outline),
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
        ),
      ),
    );
  }
}

class _AddStaffDialog extends StatefulWidget {
  const _AddStaffDialog();

  @override
  State<_AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<_AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  UserRole _role = UserRole.teacher;
  bool _saving = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<FirestoreService>();
    setState(() => _saving = true);
    try {
      final auth = context.read<AuthController>();
      await db.createStaffInvite(StaffInvite(
        id: '',
        phone: AuthService.toE164(_phone.text),
        role: _role,
        schoolId: auth.activeSchoolId ?? '',
        schoolName: auth.activeSchoolName,
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(context,
          'Invite created — ask them to sign in with this phone number.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not add: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a staff member'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<UserRole>(
                  segments: const [
                    ButtonSegment(
                        value: UserRole.teacher, label: Text('Teacher')),
                    ButtonSegment(
                        value: UserRole.principal, label: Text('Principal')),
                    ButtonSegment(value: UserRole.admin, label: Text('Admin')),
                  ],
                  selected: {_role},
                  onSelectionChanged: (s) => setState(() => _role = s.first),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _first,
                  decoration: const InputDecoration(labelText: 'First name'),
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
                  controller: _phone,
                  decoration: const InputDecoration(
                    labelText: 'Cell phone number',
                    helperText:
                        'They sign in with this number (e.g. 072 123 4567)',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) => (v == null || v.trim().length < 9)
                      ? 'Enter a valid cell number'
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
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }
}
