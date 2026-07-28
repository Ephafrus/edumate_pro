import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/broadcast.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// The parent's announcements feed: every broadcast addressed to them,
/// newest first, rendered from its HTML. Opening this screen clears the
/// notification bell.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  @override
  void initState() {
    super.initState();
    // Clear the bell badge once the feed is opened.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthController>();
      final uid = auth.appUser?.uid;
      if (uid != null) {
        await context.read<FirestoreService>().markBroadcastsSeen(uid);
        await auth.refreshAppUser();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final user = context.watch<AuthController>().appUser;
    if (user == null) {
      return const AppShell(title: 'Announcements', body: SizedBox());
    }

    return AppShell(
      title: 'Announcements',
      body: ContentContainer(
        maxWidth: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('School announcements',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            StreamBuilder<List<Broadcast>>(
              stream: db.watchBroadcastsForUser(user.uid),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final broadcasts = snap.data!;
                if (broadcasts.isEmpty) {
                  return const EmptyState(
                      'No announcements yet — school messages addressed to '
                      'you appear here.',
                      icon: Icons.campaign_outlined);
                }
                return Column(
                  children: broadcasts
                      .map((b) => Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(b.subject,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                    [
                                      formatDateTime(b.createdAt),
                                      if (b.learnerName.isNotEmpty)
                                        'Re: ${b.learnerName}'
                                      else if (b.className.isNotEmpty)
                                        b.className,
                                    ].join(' · '),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Colors.grey),
                                  ),
                                  const Divider(),
                                  Html(data: b.html),
                                ],
                              ),
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
