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
/// and principals) or their school admin (teachers).
///
/// Landing here is also the symptom of a staff invite that has not been
/// picked up, so the screen re-checks for one as it opens and offers a
/// manual re-check. That matters because tapping a school here would
/// otherwise write the person in as a **parent**, which is how invited
/// teachers ended up with the wrong role.
class JoinSchoolScreen extends StatefulWidget {
  const JoinSchoolScreen({super.key});

  @override
  State<JoinSchoolScreen> createState() => _JoinSchoolScreenState();
}

class _JoinSchoolScreenState extends State<JoinSchoolScreen> {
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    // An invite created while they were already signed in is only claimed
    // on the next auth event, which may never come in a long web session.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(silent: true));
  }

  Future<void> _check({bool silent = false}) async {
    final auth = context.read<AuthController>();
    setState(() => _checking = true);
    final claimed = await auth.recheckInvites();
    if (!mounted) return;
    setState(() => _checking = false);
    if (claimed > 0) {
      showSnack(context, 'Welcome — your school is ready.');
      context.go(auth.homePath);
    } else if (!silent) {
      showSnack(
          context,
          auth.inviteError == null
              ? 'No staff invite found for your number yet.'
              : 'Could not check invites: ${auth.inviteError}');
    }
  }

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
                              onTap: auth.busy || _checking
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
                        'their school — you do not join from this list. If '
                        'your school has added you, check again below; your '
                        'number must match the one they were given.',
                        style: Theme.of(context).textTheme.bodySmall),
                    if (auth.phone != null) ...[
                      const SizedBox(height: 6),
                      Text('You are signed in as ${auth.phone}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                    if (auth.inviteError != null) ...[
                      const SizedBox(height: 6),
                      Text('Last check failed: ${auth.inviteError}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.red)),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _checking ? null : () => _check(),
                      icon: _checking
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 18),
                      label: Text(_checking
                          ? 'Checking…'
                          : "I've been added as staff — check again"),
                    ),
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
