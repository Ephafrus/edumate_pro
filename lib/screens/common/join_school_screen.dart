import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/school.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Shown to a signed-in user who belongs to no school yet.
///
/// Parents pick the school they want to apply to and join it themselves.
/// Staff don't self-serve — their access comes from a Super Admin (admins
/// and principals) or their school admin (teachers), so they see a short
/// explanation instead.
class JoinSchoolScreen extends StatelessWidget {
  const JoinSchoolScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final auth = context.watch<AuthController>();

    return AppShell(
      title: 'Choose a school',
      body: ContentContainer(
        maxWidth: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Text('Which school are you joining?',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'Pick the school your child attends (or where you want to '
                'apply). You can join more than one school later if your '
                'children attend different schools.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            StreamBuilder<List<School>>(
              stream: db.watchSchools(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final schools =
                    snap.data!.where((s) => s.active).toList();
                if (schools.isEmpty) {
                  return const EmptyState(
                      'No schools are on EduMate Pro yet. Please check back '
                      'once your school has been set up.',
                      icon: Icons.school_outlined);
                }
                return Column(
                  children: schools
                      .map((s) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const CircleAvatar(
                                  child: Icon(Icons.school)),
                              title: Text(s.name),
                              subtitle: Text([
                                if (s.address.isNotEmpty) s.address,
                                if (s.phone.isNotEmpty) s.phone,
                              ].join(' · ')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: auth.busy
                                  ? null
                                  : () async {
                                      final ok = await auth
                                          .joinSchoolAsParent(s);
                                      if (!context.mounted) return;
                                      if (ok) {
                                        showSnack(context,
                                            'You joined ${s.name}.');
                                        context.go(auth.homePath);
                                      } else {
                                        showSnack(
                                            context,
                                            auth.error ??
                                                'Could not join that school');
                                      }
                                    },
                            ),
                          ))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Staff member?',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        'Teachers, principals and school admins are added by '
                        'their school. Once you have been assigned, your '
                        'school appears here automatically the next time you '
                        'sign in.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
