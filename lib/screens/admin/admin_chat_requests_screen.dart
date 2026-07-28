import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/chat.dart';
import '../../models/enums.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Admin approval queue for parent→teacher chat requests. A chat only
/// unlocks for messaging once approved here.
class AdminChatRequestsScreen extends StatelessWidget {
  const AdminChatRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Chat requests',
      breadcrumb: 'Dashboard > Chat requests',
      body: ContentContainer(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Parent chat requests',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'Parents may only message a teacher after you approve their '
                'request.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            StreamBuilder<List<ChatThread>>(
              stream: db.watchPendingChatRequests(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final requests = snap.data!;
                if (requests.isEmpty) {
                  return const EmptyState('No pending chat requests.',
                      icon: Icons.mark_chat_read_outlined);
                }
                return Column(
                  children: requests.map((t) {
                    final names = t.participantNames.values.toList();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(names.join(' ↔ '),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            if (t.learnerName.isNotEmpty)
                              InfoLine('Regarding learner', t.learnerName),
                            if (t.requestReason.isNotEmpty)
                              InfoLine('Reason', t.requestReason),
                            InfoLine('Requested', formatDate(t.createdAt)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: () async {
                                    await db.setChatApproval(
                                        t.id, ChatApproval.approved);
                                    if (context.mounted) {
                                      showSnack(context,
                                          'Chat approved — both sides can '
                                          'now message.');
                                    }
                                  },
                                  icon: const Icon(Icons.check, size: 18),
                                  label: const Text('Approve'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final ok = await confirmDialog(
                                      context,
                                      'Decline this chat request?',
                                      'The parent will see the request was '
                                          'declined.',
                                      confirmLabel: 'Decline',
                                    );
                                    if (ok) {
                                      await db.setChatApproval(
                                          t.id, ChatApproval.declined);
                                    }
                                  },
                                  icon: const Icon(Icons.close, size: 18),
                                  label: const Text('Decline'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
