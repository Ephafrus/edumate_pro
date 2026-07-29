import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/academics.dart';
import '../models/activity_log.dart';
import '../models/school.dart';
import '../router/app_router.dart';
import '../services/activity_service.dart';
import '../services/firestore_service.dart';
import 'common.dart';

/// Dropdown for "who teaches this?", used for class teachers and for the
/// teacher of a subject.
///
/// It lists active staff **and** staff who have been invited but have not
/// signed in yet, so an admin can assign teaching the moment they add
/// somebody rather than waiting for their first sign-in. When there is
/// nobody to choose from it says so and offers a way to add staff, instead
/// of presenting an empty dropdown that looks broken.
class TeacherPicker extends StatelessWidget {
  const TeacherPicker({
    super.key,
    required this.selectedId,
    required this.onChanged,
    this.label = 'Teacher',
    this.allowNone = true,
  });

  /// The selected staff uid **or** invite id — whichever the record holds.
  final String? selectedId;
  final ValueChanged<TeacherOption?> onChanged;
  final String label;

  /// Whether "Not assigned" is offered as a choice.
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return StreamBuilder<List<TeacherOption>>(
      stream: db.watchTeacherOptions(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return InputDecorator(
            decoration: InputDecoration(labelText: label),
            child: const Text('Loading staff…',
                style: TextStyle(color: Colors.grey)),
          );
        }
        final options = snap.data!;
        if (options.isEmpty) {
          return InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              helperText: 'Nobody to assign yet',
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text('No staff at this school yet',
                      style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () => context.go(Routes.adminStaff),
                  child: const Text('Add staff'),
                ),
              ],
            ),
          );
        }

        // The list arrives asynchronously, so the dropdown is rebuilt with a
        // key that changes with it — otherwise the form field keeps the value
        // it captured on the first (empty) build and an already-assigned
        // teacher shows as unassigned.
        final known = options.any((o) => o.id == selectedId);
        return DropdownButtonFormField<String>(
          key: ValueKey('$label|$selectedId|${options.length}'),
          initialValue: known ? selectedId : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            if (allowNone)
              const DropdownMenuItem<String>(
                  value: '', child: Text('Not assigned')),
            ...options.map((o) => DropdownMenuItem<String>(
                  value: o.id,
                  child: Text(o.label, overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (id) => onChanged(
              options.where((o) => o.id == id).firstOrNull),
        );
      },
    );
  }
}

/// One-line explanation of a teaching assignment, including the "waiting for
/// them to sign in" case so an admin is never left wondering.
String teacherStatusLine(String teacherName, {required bool pending}) {
  if (teacherName.isEmpty) return 'No teacher assigned';
  return pending
      ? '$teacherName — invited, takes effect at their first sign-in'
      : teacherName;
}

/// Assigns (or clears) the teacher of a class or of a subject.
///
/// The same dialog is reachable from the classes list and from the class
/// page, so linking a teacher is one tap from wherever the admin happens to
/// be looking.
class AssignTeacherDialog extends StatefulWidget {
  const AssignTeacherDialog({super.key, this.schoolClass, this.subject})
      : assert(schoolClass != null || subject != null,
            'assign a teacher to either a class or a subject');

  final SchoolClass? schoolClass;
  final Subject? subject;

  @override
  State<AssignTeacherDialog> createState() => _AssignTeacherDialogState();
}

class _AssignTeacherDialogState extends State<AssignTeacherDialog> {
  TeacherOption? _teacher;
  String? _selectedId;
  bool _cleared = false;
  bool _saving = false;

  bool get _isClass => widget.schoolClass != null;
  String get _what => _isClass
      ? widget.schoolClass!.name
      : '${widget.subject!.name} · ${widget.subject!.className}';

  @override
  void initState() {
    super.initState();
    _selectedId = _isClass
        ? (widget.schoolClass!.teacherUid ??
            widget.schoolClass!.teacherInviteId)
        : (widget.subject!.teacherUid ?? widget.subject!.teacherInviteId);
  }

  Future<void> _save() async {
    if (_teacher == null && !_cleared) {
      Navigator.of(context).pop();
      return;
    }
    final db = context.read<FirestoreService>();
    final activity = context.read<ActivityService>();
    setState(() => _saving = true);
    try {
      if (_isClass) {
        await db.assignClassTeacher(widget.schoolClass!.id, _teacher);
      } else {
        await db.assignSubjectTeacher(widget.subject!.id, _teacher);
      }
      activity.log(ActivityAction.teacherAssigned,
          target: _what,
          details: _teacher == null
              ? 'cleared'
              : '${_teacher!.name}${_teacher!.pending ? ' (invited)' : ''}');
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(
          context,
          _teacher == null
              ? 'Teacher removed from $_what.'
              : _teacher!.pending
                  ? '${_teacher!.name} will take $_what when they first '
                      'sign in.'
                  : '${_teacher!.name} now takes $_what.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not assign: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isClass ? 'Class teacher' : 'Subject teacher'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_what, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            TeacherPicker(
              selectedId: _selectedId,
              onChanged: (t) => setState(() {
                _teacher = t;
                _selectedId = t?.id ?? '';
                _cleared = t == null;
              }),
            ),
          ],
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
