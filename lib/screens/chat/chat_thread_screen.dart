import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/chat.dart';
import '../../models/enums.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// One conversation. Messaging is enabled only while the thread is approved
/// (staff chats always are; parent-teacher chats need admin approval first).
class ChatThreadScreen extends StatefulWidget {
  const ChatThreadScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final user = context.read<AuthController>().appUser!;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await context.read<FirestoreService>().sendMessage(
            widget.chatId,
            ChatMessage(
              id: '',
              senderUid: user.uid,
              senderName: user.fullName,
              text: text,
            ),
          );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final user = context.watch<AuthController>().appUser;
    final uid = user?.uid ?? '';

    return AppShell(
      title: 'Chat',
      scrollable: false,
      body: ContentContainer(
        maxWidth: 720,
        child: StreamBuilder<ChatThread?>(
          stream: db.watchChat(widget.chatId),
          builder: (context, threadSnap) {
            final thread = threadSnap.data;
            if (threadSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (thread == null || !thread.participantUids.contains(uid)) {
              return const EmptyState('Conversation not found');
            }
            final locked = !thread.isActive;

            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(thread.titleFor(uid),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    if (thread.type == ChatType.parentTeacher)
                      StatusChip.chat(thread.approval),
                  ],
                ),
                const SizedBox(height: 8),
                if (locked)
                  Card(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        thread.approval == ChatApproval.requested
                            ? 'This chat is waiting for school admin '
                                'approval. Messaging unlocks once approved.'
                            : 'This chat request was declined by the school '
                                'admin.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<List<ChatMessage>>(
                    stream: db.watchMessages(widget.chatId),
                    builder: (context, snap) {
                      final msgs = snap.data ?? [];
                      if (msgs.isEmpty) {
                        return const EmptyState(
                            'No messages yet. Say hello!',
                            icon: Icons.chat_bubble_outline);
                      }
                      return ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.all(8),
                        itemCount: msgs.length,
                        itemBuilder: (context, i) {
                          final m = msgs[msgs.length - 1 - i];
                          final mine = m.senderUid == uid;
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin:
                                  const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              constraints:
                                  const BoxConstraints(maxWidth: 420),
                              decoration: BoxDecoration(
                                color: mine
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: mine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!mine && m.senderName.isNotEmpty)
                                    Text(m.senderName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        )),
                                  Text(
                                    m.text,
                                    style: TextStyle(
                                        color: mine
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onPrimary
                                            : null),
                                  ),
                                  Text(
                                    formatDateTime(m.createdAt),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: mine
                                          ? Theme.of(context)
                                              .colorScheme
                                              .onPrimary
                                              .withValues(alpha: 0.7)
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          enabled: !locked,
                          minLines: 1,
                          maxLines: 4,
                          decoration: InputDecoration(
                              hintText: locked
                                  ? 'Messaging locked'
                                  : 'Type a message…'),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed:
                            _sending || locked ? null : () => _send(),
                        icon: const Icon(Icons.send),
                      ),
                    ],
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
