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

/// Class management: create classes and assign a teacher to each.
class AdminClassesScreen extends StatelessWidget {
  const AdminClassesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Classes',
      breadcrumb: 'Dashboard > Classes',
      body: ContentContainer(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Classes',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                FilledButton.icon(
                  onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const _EditClassDialog()),
                  icon: const Icon(Icons.add),
                  label: const Text('New class'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<SchoolClass>>(
              stream: db.watchClasses(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final classes = snap.data!;
                if (classes.isEmpty) {
                  return const EmptyState(
                      'No classes yet — create one to start assigning '
                      'learners.',
                      icon: Icons.meeting_room_outlined);
                }
                return Column(
                  children: classes
                      .map((c) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.meeting_room_outlined),
                              title: Text(c.name),
                              subtitle: Text([
                                c.grade,
                                if (c.year != null) '${c.year}',
                                c.teacherName.isEmpty
                                    ? 'No teacher assigned'
                                    : 'Teacher: ${c.teacherName}',
                              ].join(' · ')),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Edit',
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 20),
                                    onPressed: () => showDialog(
                                        context: context,
                                        builder: (_) =>
                                            _EditClassDialog(existing: c)),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20),
                                    onPressed: () async {
                                      final ok = await confirmDialog(
                                        context,
                                        'Delete ${c.name}?',
                                        'Learners assigned to it keep their '
                                            'records but lose the class '
                                            'assignment.',
                                        confirmLabel: 'Delete',
                                      );
                                      if (ok) await db.deleteClass(c.id);
                                    },
                                  ),
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

class _EditClassDialog extends StatefulWidget {
  const _EditClassDialog({this.existing});
  final SchoolClass? existing;

  @override
  State<_EditClassDialog> createState() => _EditClassDialogState();
}

class _EditClassDialogState extends State<_EditClassDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _year;
  String? _grade;
  AppUser? _teacher;
  String? _teacherUid;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _year = TextEditingController(
        text: widget.existing?.year?.toString() ??
            DateTime.now().year.toString());
    _grade = widget.existing?.grade.isNotEmpty == true
        ? widget.existing!.grade
        : null;
    _teacherUid = widget.existing?.teacherUid;
  }

  @override
  void dispose() {
    _name.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_grade == null) {
      showSnack(context, 'Select a grade');
      return;
    }
    final db = context.read<FirestoreService>();
    setState(() => _saving = true);
    try {
      final data = SchoolClass(
        id: widget.existing?.id ?? '',
        name: _name.text.trim(),
        grade: _grade!,
        year: int.tryParse(_year.text),
        teacherUid: _teacher?.uid ?? _teacherUid,
        teacherName: _teacher?.fullName ?? widget.existing?.teacherName ?? '',
      );
      if (widget.existing == null) {
        await db.createClass(data);
      } else {
        await db.updateClass(widget.existing!.id, {
          'name': data.name,
          'grade': data.grade,
          'year': data.year,
          'teacherUid': data.teacherUid,
          'teacherName': data.teacherName,
        });
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
    final db = context.read<FirestoreService>();

    return AlertDialog(
      title: Text(widget.existing == null ? 'New class' : 'Edit class'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Class name', hintText: 'e.g. Grade 4 Blue'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Class name is required'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _grade,
                decoration: const InputDecoration(labelText: 'Grade'),
                items: RefData.grades
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => _grade = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _year,
                decoration:
                    const InputDecoration(labelText: 'Academic year'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<AppUser>>(
                stream: db.watchUsersByRole(UserRole.teacher),
                builder: (context, snap) {
                  final teachers = snap.data ?? [];
                  final knownUid =
                      teachers.any((t) => t.uid == _teacherUid);
                  return DropdownButtonFormField<String>(
                    initialValue: knownUid ? _teacherUid : null,
                    decoration: const InputDecoration(
                        labelText: 'Teacher (optional)'),
                    items: teachers
                        .map((t) => DropdownMenuItem(
                            value: t.uid, child: Text(t.fullName)))
                        .toList(),
                    onChanged: (uid) => setState(() {
                      _teacherUid = uid;
                      _teacher =
                          teachers.where((t) => t.uid == uid).firstOrNull;
                    }),
                  );
                },
              ),
            ],
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
