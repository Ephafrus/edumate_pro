import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/chat.dart';
import '../../models/enums.dart';
import '../../router/app_router.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// All chat threads for the signed-in user. Staff see colleague chats plus
/// approved parent chats; parents see their (possibly still pending) teacher
/// chats.
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final user = context.watch<AuthController>().appUser;
    if (user == null) {
      return const AppShell(title: 'Messages', body: SizedBox());
    }

    return AppShell(
      title: 'Messages',
      body: ContentContainer(
        maxWidth: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Messages',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                FilledButton.icon(
                  onPressed: () => context.go(Routes.newChat),
                  icon: const Icon(Icons.add_comment_outlined),
                  label: Text(
                      user.isStaff ? 'New chat' : 'Request teacher chat'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<ChatThread>>(
              stream: db.watchChatsForUser(user.uid),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final threads = snap.data!;
                if (threads.isEmpty) {
                  return EmptyState(
                      user.isStaff
                          ? 'No conversations yet — start one with a '
                              'colleague.'
                          : 'No conversations yet — request a chat with your '
                              "child's teacher.",
                      icon: Icons.chat_bubble_outline);
                }
                return Column(
                  children: threads.map((t) {
                    final pending = t.approval == ChatApproval.requested;
                    final declined = t.approval == ChatApproval.declined;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(t.type == ChatType.staff
                              ? Icons.badge_outlined
                              : Icons.family_restroom),
                        ),
                        title: Text(t.titleFor(user.uid)),
                        subtitle: Text(
                          pending
                              ? 'Waiting for admin approval'
                              : declined
                                  ? 'Request declined'
                                  : (t.lastMessage.isEmpty
                                      ? 'No messages yet'
                                      : t.lastMessage),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: t.isActive
                            ? const Icon(Icons.chevron_right)
                            : StatusChip.chat(t.approval),
                        onTap: t.isActive || user.isStaff
                            ? () => context.go(Routes.chatThread(t.id))
                            : null,
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
