import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../models/school.dart';
import '../../router/app_router.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Super Admin console: every school on the platform, and the button to set
/// a new one up. Opening a school leads to its detail screen, where the
/// admins / principals who manage it are assigned.
class SuperSchoolsScreen extends StatelessWidget {
  const SuperSchoolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final me = context.watch<AuthController>().appUser;
    final scheme = Theme.of(context).colorScheme;

    return AppShell(
      title: 'Schools',
      body: ContentContainer(
        maxWidth: 860,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: scheme.heroGradient,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.admin_panel_settings,
                          color: Colors.white),
                      const SizedBox(width: 8),
                      Text('Super Admin — ${me?.firstName ?? ''}'.trim(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                      'Set schools up on the platform and assign the admins '
                      'and principals who manage them.',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text('Schools',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                FilledButton.icon(
                  onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const _NewSchoolDialog()),
                  icon: const Icon(Icons.add_business),
                  label: const Text('New school'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<School>>(
              stream: db.watchSchools(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final schools = snap.data!;
                if (schools.isEmpty) {
                  return const EmptyState(
                      'No schools yet — set the first one up to get started.',
                      icon: Icons.school_outlined);
                }
                return Column(
                  children: schools
                      .map((s) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    scheme.primary.withValues(alpha: 0.12),
                                child: Icon(Icons.school,
                                    color: scheme.primary),
                              ),
                              title: Text(s.name),
                              subtitle: Text([
                                if (s.address.isNotEmpty) s.address,
                                if (s.phone.isNotEmpty) s.phone,
                                'Created ${formatDate(s.createdAt)}',
                              ].join(' · ')),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!s.active)
                                    const StatusChip(
                                        'Suspended', Colors.orange),
                                  IconButton(
                                    tooltip: 'Sign in to this school',
                                    icon: const Icon(Icons.login),
                                    onPressed: () async {
                                      await context
                                          .read<AuthController>()
                                          .enterSchool(s);
                                      if (context.mounted) {
                                        context.go(Routes.adminHome);
                                      }
                                    },
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              onTap: () =>
                                  context.go(Routes.superSchoolDetail(s.id)),
                            ),
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

class _NewSchoolDialog extends StatefulWidget {
  const _NewSchoolDialog();

  @override
  State<_NewSchoolDialog> createState() => _NewSchoolDialogState();
}

class _NewSchoolDialogState extends State<_NewSchoolDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _motto = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _email, _motto]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<FirestoreService>();
    setState(() => _saving = true);
    try {
      final id = await db.createSchool(School(
        id: '',
        name: _name.text.trim(),
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        motto: _motto.text.trim(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(context,
          '${_name.text.trim()} created — assign an admin to manage it.');
      context.go(Routes.superSchoolDetail(id));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not create: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set up a new school'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                      labelText: 'School name',
                      hintText: 'e.g. Sunnyside Primary School'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'School name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(labelText: 'Address'),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phone,
                  decoration:
                      const InputDecoration(labelText: 'Contact phone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration:
                      const InputDecoration(labelText: 'Contact email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _motto,
                  decoration:
                      const InputDecoration(labelText: 'Motto (optional)'),
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
              : const Text('Create school'),
        ),
      ],
    );
  }
}
