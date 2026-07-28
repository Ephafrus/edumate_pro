import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../models/app_user.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/learner_qr_dialog.dart';

/// Learner management: add/edit learners, assign each to a class, and link
/// learners to parent accounts (so parents see them and can pay for them).
class AdminLearnersScreen extends StatefulWidget {
  const AdminLearnersScreen({super.key});

  @override
  State<AdminLearnersScreen> createState() => _AdminLearnersScreenState();
}

class _AdminLearnersScreenState extends State<AdminLearnersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Learners',
      breadcrumb: 'Dashboard > Learners',
      body: ContentContainer(
        maxWidth: 860,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Learners',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                FilledButton.icon(
                  onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const _EditLearnerDialog()),
                  icon: const Icon(Icons.add),
                  label: const Text('Add learner'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name…',
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<Learner>>(
              stream: db.watchLearners(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final learners = snap.data!
                    .where((l) =>
                        _search.isEmpty ||
                        l.fullName.toLowerCase().contains(_search))
                    .toList();
                if (learners.isEmpty) {
                  return const EmptyState(
                      'No learners found. Add one directly, or enroll an '
                      'application.',
                      icon: Icons.child_care_outlined);
                }
                return Column(
                  children:
                      learners.map((l) => _LearnerCard(learner: l)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LearnerCard extends StatelessWidget {
  const _LearnerCard({required this.learner});
  final Learner learner;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final l = learner;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                    child:
                        Text(l.firstName.isEmpty ? '?' : l.firstName[0])),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.fullName,
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        [
                          if (l.grade.isNotEmpty) l.grade,
                          l.className.isEmpty
                              ? 'No class'
                              : 'Class: ${l.className}',
                          '${l.parentUids.length} parent(s) linked',
                        ].join(' · '),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  l.status.label,
                  l.status == LearnerStatus.active
                      ? Colors.green
                      : l.status == LearnerStatus.applicant
                          ? Colors.orange
                          : Colors.blueGrey,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _EditLearnerDialog(existing: l)),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _AssignClassDialog(learner: l)),
                  icon: const Icon(Icons.meeting_room_outlined, size: 18),
                  label: const Text('Assign class'),
                ),
                TextButton.icon(
                  onPressed: () => showDialog(
                      context: context,
                      builder: (_) => _LinkParentsDialog(learner: l)),
                  icon: const Icon(Icons.family_restroom, size: 18),
                  label: const Text('Link parents'),
                ),
                TextButton.icon(
                  onPressed: () => showDialog(
                      context: context,
                      builder: (_) => LearnerQrDialog(
                          learnerId: l.id, learnerName: l.fullName)),
                  icon: const Icon(Icons.qr_code_2, size: 18),
                  label: const Text('QR code'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      'Delete ${l.fullName}?',
                      'This removes the learner record permanently.',
                      confirmLabel: 'Delete',
                    );
                    if (ok) await db.deleteLearner(l.id);
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditLearnerDialog extends StatefulWidget {
  const _EditLearnerDialog({this.existing});
  final Learner? existing;

  @override
  State<_EditLearnerDialog> createState() => _EditLearnerDialogState();
}

class _EditLearnerDialogState extends State<_EditLearnerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _idNumber;
  String? _grade;
  DateTime? _dob;
  Gender? _gender;
  late LearnerStatus _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _first = TextEditingController(text: e?.firstName ?? '');
    _last = TextEditingController(text: e?.lastName ?? '');
    _idNumber = TextEditingController(text: e?.idNumber ?? '');
    _grade = e?.grade.isNotEmpty == true ? e!.grade : null;
    _dob = e?.dateOfBirth;
    _gender = e?.gender;
    _status = e?.status ?? LearnerStatus.active;
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _idNumber.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<FirestoreService>();
    setState(() => _saving = true);
    try {
      final data = {
        'firstName': _first.text.trim(),
        'lastName': _last.text.trim(),
        'idNumber': _idNumber.text.trim(),
        'grade': _grade ?? '',
        'dateOfBirth': _dob,
        'gender': _gender?.name,
        'status': _status.name,
      };
      if (widget.existing == null) {
        await db.createLearner(Learner(
          id: '',
          firstName: _first.text.trim(),
          lastName: _last.text.trim(),
          idNumber: _idNumber.text.trim(),
          grade: _grade ?? '',
          dateOfBirth: _dob,
          gender: _gender,
          status: _status,
        ));
      } else {
        await db.updateLearner(widget.existing!.id, data);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.existing == null ? 'Add learner' : 'Edit learner'),
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
                  controller: _first,
                  decoration:
                      const InputDecoration(labelText: 'First name'),
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
                  controller: _idNumber,
                  decoration: const InputDecoration(
                      labelText: 'ID / birth certificate number (optional)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _grade,
                  decoration: const InputDecoration(labelText: 'Grade'),
                  items: RefData.grades
                      .map((g) =>
                          DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) => setState(() => _grade = v),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dob ?? DateTime(now.year - 6),
                      firstDate: DateTime(now.year - 25),
                      lastDate: now,
                    );
                    if (picked != null) setState(() => _dob = picked);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date of birth',
                      suffixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    child:
                        Text(_dob == null ? 'Select…' : formatDate(_dob)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Gender>(
                  initialValue: _gender,
                  decoration: const InputDecoration(labelText: 'Gender'),
                  items: Gender.values
                      .map((g) =>
                          DropdownMenuItem(value: g, child: Text(g.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<LearnerStatus>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: LearnerStatus.values
                      .map((s) =>
                          DropdownMenuItem(value: s, child: Text(s.label)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _status = v ?? _status),
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
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Assign the learner to a class (or clear the assignment).
class _AssignClassDialog extends StatefulWidget {
  const _AssignClassDialog({required this.learner});
  final Learner learner;

  @override
  State<_AssignClassDialog> createState() => _AssignClassDialogState();
}

class _AssignClassDialogState extends State<_AssignClassDialog> {
  String? _classId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _classId = widget.learner.classId;
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AlertDialog(
      title: Text('Assign ${widget.learner.firstName} to a class'),
      content: SizedBox(
        width: 400,
        child: StreamBuilder<List<SchoolClass>>(
          stream: db.watchClasses(),
          builder: (context, snap) {
            final classes = snap.data ?? [];
            if (classes.isEmpty) {
              return const Text(
                  'No classes exist yet — create one under Classes first.');
            }
            return RadioGroup<String?>(
              groupValue: _classId,
              onChanged: (v) => setState(() => _classId = v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RadioListTile<String?>(
                    value: null,
                    title: Text('No class'),
                  ),
                  ...classes.map((c) => RadioListTile<String?>(
                        value: c.id,
                        title: Text(c.name),
                        subtitle: Text([
                          c.grade,
                          if (c.teacherName.isNotEmpty)
                            'Teacher: ${c.teacherName}',
                        ].join(' · ')),
                      )),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    String className = '';
                    if (_classId != null) {
                      final classes = await db.watchClasses().first;
                      className = classes
                              .where((c) => c.id == _classId)
                              .firstOrNull
                              ?.name ??
                          '';
                    }
                    await db.assignLearnerToClass(
                        widget.learner.id, _classId, className);
                    if (context.mounted) Navigator.of(context).pop();
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Link/unlink parent accounts to the learner.
class _LinkParentsDialog extends StatelessWidget {
  const _LinkParentsDialog({required this.learner});
  final Learner learner;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AlertDialog(
      title: Text('Parents of ${learner.firstName}'),
      content: SizedBox(
        width: 440,
        child: StreamBuilder<List<AppUser>>(
          stream: db.watchUsersByRole(UserRole.parent),
          builder: (context, parentSnap) {
            final parents = parentSnap.data ?? [];
            if (parents.isEmpty) {
              return const Text(
                  'No parent accounts yet. Parents appear here after they '
                  'sign in and create a profile.');
            }
            // Live learner doc so checkboxes update as links change.
            return StreamBuilder<List<Learner>>(
              stream: db.watchLearners(),
              builder: (context, learnerSnap) {
                final current = (learnerSnap.data ?? [])
                        .where((l) => l.id == learner.id)
                        .firstOrNull ??
                    learner;
                return SizedBox(
                  height: 320,
                  child: ListView(
                    children: parents
                        .map((p) => CheckboxListTile(
                              value: current.parentUids.contains(p.uid),
                              onChanged: (v) => db.setParentLink(
                                  learner.id, p.uid,
                                  linked: v ?? false),
                              title: Text(p.fullName),
                              subtitle: Text([
                                if (p.phone != null) p.phone!,
                                if (p.email != null && p.email!.isNotEmpty)
                                  p.email!,
                              ].join(' · ')),
                            ))
                        .toList(),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
