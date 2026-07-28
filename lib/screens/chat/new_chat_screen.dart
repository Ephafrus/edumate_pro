import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/app_user.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../router/app_router.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Start a conversation.
///  * Staff pick a colleague — the chat opens immediately.
///  * Parents pick a teacher and give a reason — this creates a chat
///    *request* that a school admin must approve before messaging unlocks.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _reason = TextEditingController();
  String? _teacherUid;
  String? _learnerName;
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _openStaffChat(AppUser other) async {
    final db = context.read<FirestoreService>();
    final me = context.read<AuthController>().appUser!;
    setState(() => _saving = true);
    try {
      final chatId = await db.openStaffChat(me, other);
      if (mounted) context.go(Routes.chatThread(chatId));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestTeacherChat(List<AppUser> teachers) async {
    final db = context.read<FirestoreService>();
    final me = context.read<AuthController>().appUser!;
    final teacher =
        teachers.where((t) => t.uid == _teacherUid).firstOrNull;
    if (teacher == null) {
      showSnack(context, 'Select a teacher');
      return;
    }
    setState(() => _saving = true);
    try {
      final chatId = await db.requestParentTeacherChat(
        parent: me,
        teacher: teacher,
        reason: _reason.text.trim(),
        learnerName: _learnerName ?? '',
      );
      if (!mounted) return;
      showSnack(context,
          'Request sent — the school admin will review it shortly.');
      context.go(Routes.chatThread(chatId));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final user = context.watch<AuthController>().appUser;
    if (user == null) {
      return const AppShell(title: 'New chat', body: SizedBox());
    }

    return AppShell(
      title: user.isStaff ? 'New chat' : 'Request a chat',
      breadcrumb: 'Messages > New',
      body: ContentContainer(
        maxWidth: 560,
        child: user.isStaff
            ? _staffPicker(db, user)
            : _parentRequestForm(db, user),
      ),
    );
  }

  Widget _staffPicker(FirestoreService db, AppUser me) {
    return SectionCard(
      title: 'Start a chat with a colleague',
      child: StreamBuilder<List<AppUser>>(
        stream: db.watchStaff(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final colleagues =
              snap.data!.where((u) => u.uid != me.uid).toList();
          if (colleagues.isEmpty) {
            return const EmptyState('No other staff members yet.');
          }
          return Column(
            children: colleagues
                .map((u) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                          child: Text(
                              u.firstName.isEmpty ? '?' : u.firstName[0])),
                      title: Text(u.fullName),
                      subtitle: Text(u.role.label),
                      trailing: const Icon(Icons.chat_bubble_outline),
                      onTap: _saving ? null : () => _openStaffChat(u),
                    ))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _parentRequestForm(FirestoreService db, AppUser me) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: "Request a chat with your child's teacher",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  'The school admin reviews chat requests before messaging '
                  'opens.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              StreamBuilder<List<AppUser>>(
                stream: db.watchUsersByRole(UserRole.teacher),
                builder: (context, snap) {
                  final teachers = snap.data ?? [];
                  return DropdownButtonFormField<String>(
                    initialValue:
                        teachers.any((t) => t.uid == _teacherUid)
                            ? _teacherUid
                            : null,
                    decoration:
                        const InputDecoration(labelText: 'Teacher'),
                    items: teachers
                        .map((t) => DropdownMenuItem(
                            value: t.uid, child: Text(t.fullName)))
                        .toList(),
                    onChanged: (v) => setState(() => _teacherUid = v),
                  );
                },
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<Learner>>(
                stream: db.watchLearnersForParent(me.uid),
                builder: (context, snap) {
                  final learners = snap.data ?? [];
                  if (learners.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: learners
                              .any((l) => l.fullName == _learnerName)
                          ? _learnerName
                          : null,
                      decoration: const InputDecoration(
                          labelText: 'Regarding (optional)'),
                      items: learners
                          .map((l) => DropdownMenuItem(
                              value: l.fullName, child: Text(l.fullName)))
                          .toList(),
                      onChanged: (v) => setState(() => _learnerName = v),
                    ),
                  );
                },
              ),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'What would you like to discuss?',
                  helperText: 'Shown to the admin reviewing your request',
                ),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        final teachers = await db
                            .watchUsersByRole(UserRole.teacher)
                            .first;
                        if (mounted) await _requestTeacherChat(teachers);
                      },
                icon: const Icon(Icons.send),
                label: const Text('Send request'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
