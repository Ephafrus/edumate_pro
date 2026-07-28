import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/app_user.dart';
import '../../models/broadcast.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../services/firestore_service.dart';
import '../../services/mail_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/html_editor_field.dart';

/// Broadcast messages: admin composes an HTML message and targets one
/// learner's parents, a class's parents, or every parent in the school.
/// Sending stores the broadcast (which lights up the recipients' in-app
/// notification bell) and emails each recipient over the school's SMTP.
class AdminBroadcastsScreen extends StatelessWidget {
  const AdminBroadcastsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Broadcasts',
      breadcrumb: 'Dashboard > Broadcasts',
      body: ContentContainer(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Broadcast messages',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                FilledButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const _ComposeBroadcastDialog(),
                  ),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('New broadcast'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<Broadcast>>(
              stream: db.watchBroadcasts(),
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
                      'No broadcasts yet — send a message to a learner\'s '
                      'parents, a class, or the whole school.',
                      icon: Icons.campaign_outlined);
                }
                return Column(
                  children: broadcasts
                      .map((b) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ExpansionTile(
                              title: Text(b.subject),
                              subtitle: Text([
                                b.scopeLabel,
                                '${b.recipientUids.length} recipient(s)',
                                '${b.emailsSent} emailed',
                                if (b.emailsFailed > 0)
                                  '${b.emailsFailed} failed',
                                formatDateTime(b.createdAt),
                              ].join(' · ')),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                  16, 0, 16, 12),
                              children: [Html(data: b.html)],
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

class _ComposeBroadcastDialog extends StatefulWidget {
  const _ComposeBroadcastDialog();

  @override
  State<_ComposeBroadcastDialog> createState() =>
      _ComposeBroadcastDialogState();
}

class _ComposeBroadcastDialogState extends State<_ComposeBroadcastDialog> {
  final _subject = TextEditingController();
  final _html = TextEditingController();
  BroadcastScope _scope = BroadcastScope.school;
  String? _classId;
  String _className = '';
  String? _learnerId;
  String _learnerName = '';
  bool _sending = false;
  String _progress = '';

  @override
  void dispose() {
    _subject.dispose();
    _html.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_subject.text.trim().isEmpty || _html.text.trim().isEmpty) {
      showSnack(context, 'Add a subject and a message');
      return;
    }
    if (_scope == BroadcastScope.schoolClass && _classId == null) {
      showSnack(context, 'Pick a class');
      return;
    }
    if (_scope == BroadcastScope.learner && _learnerId == null) {
      showSnack(context, 'Pick a learner');
      return;
    }

    final db = context.read<FirestoreService>();
    final mail = context.read<MailService>();
    final me = context.read<AuthController>().appUser;

    setState(() {
      _sending = true;
      _progress = 'Resolving recipients…';
    });
    try {
      // Resolve the target parent accounts for the chosen destination.
      final recipients = <AppUser>[];
      if (_scope == BroadcastScope.school) {
        recipients
            .addAll(await db.watchUsersByRole(UserRole.parent).first);
      } else {
        final uids = <String>{};
        if (_scope == BroadcastScope.schoolClass) {
          final learners =
              await db.watchLearnersInClass(_classId!).first;
          for (final l in learners) {
            uids.addAll(l.parentUids);
          }
        } else {
          final learner = await db.getLearner(_learnerId!);
          uids.addAll(learner?.parentUids ?? const []);
        }
        for (final uid in uids) {
          final u = await db.getUser(uid);
          if (u != null) recipients.add(u);
        }
      }
      if (recipients.isEmpty) {
        if (mounted) {
          showSnack(context,
              'No parent accounts found for that destination.');
          setState(() => _sending = false);
        }
        return;
      }

      // Store the broadcast first — this is the in-app notification.
      final id = await db.createBroadcast(Broadcast(
        id: '',
        subject: _subject.text.trim(),
        html: _html.text.trim(),
        scope: _scope,
        classId: _classId,
        className: _className,
        learnerId: _learnerId,
        learnerName: _learnerName,
        recipientUids: recipients.map((u) => u.uid).toList(),
        sentByName: me?.fullName ?? '',
      ));

      // Then email each recipient over the school's SMTP.
      var sent = 0;
      var failed = 0;
      final plain = _html.text
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      for (var i = 0; i < recipients.length; i++) {
        final r = recipients[i];
        if (mounted) {
          setState(() =>
              _progress = 'Emailing ${i + 1}/${recipients.length}…');
        }
        final address = r.email;
        if (address == null || address.isEmpty) continue;
        final outcome = await mail.send(
          to: address,
          subject: _subject.text.trim(),
          text: plain,
          html: _html.text.trim(),
        );
        if (outcome == MailOutcome.failed) {
          failed++;
        } else {
          sent++;
        }
      }
      await db.updateBroadcast(
          id, {'emailsSent': sent, 'emailsFailed': failed});

      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(
          context,
          'Broadcast sent to ${recipients.length} parent(s) — '
          '$sent email(s) delivered/queued'
          '${failed > 0 ? ', $failed failed' : ''}.');
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Could not send: $e');
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AlertDialog(
      title: const Text('New broadcast'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<BroadcastScope>(
                segments: BroadcastScope.values
                    .map((s) =>
                        ButtonSegment(value: s, label: Text(s.label)))
                    .toList(),
                selected: {_scope},
                onSelectionChanged: (s) =>
                    setState(() => _scope = s.first),
              ),
              const SizedBox(height: 12),
              if (_scope == BroadcastScope.schoolClass)
                StreamBuilder<List<SchoolClass>>(
                  stream: db.watchClasses(),
                  builder: (context, snap) {
                    final classes = snap.data ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue:
                          classes.any((c) => c.id == _classId)
                              ? _classId
                              : null,
                      decoration:
                          const InputDecoration(labelText: 'Class'),
                      items: classes
                          .map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name)))
                          .toList(),
                      onChanged: (id) => setState(() {
                        _classId = id;
                        _className = classes
                                .where((c) => c.id == id)
                                .firstOrNull
                                ?.name ??
                            '';
                      }),
                    );
                  },
                ),
              if (_scope == BroadcastScope.learner)
                StreamBuilder<List<Learner>>(
                  stream: db.watchLearners(),
                  builder: (context, snap) {
                    final learners = snap.data ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue:
                          learners.any((l) => l.id == _learnerId)
                              ? _learnerId
                              : null,
                      decoration: const InputDecoration(
                          labelText: 'Learner (message goes to their '
                              'parents)'),
                      items: learners
                          .map((l) => DropdownMenuItem(
                              value: l.id, child: Text(l.fullName)))
                          .toList(),
                      onChanged: (id) => setState(() {
                        _learnerId = id;
                        _learnerName = learners
                                .where((l) => l.id == id)
                                .firstOrNull
                                ?.fullName ??
                            '';
                      }),
                    );
                  },
                ),
              if (_scope != BroadcastScope.school)
                const SizedBox(height: 12),
              TextField(
                controller: _subject,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              const SizedBox(height: 12),
              HtmlEditorField(controller: _html),
              if (_sending) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Text(_progress),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Send broadcast'),
        ),
      ],
    );
  }
}
