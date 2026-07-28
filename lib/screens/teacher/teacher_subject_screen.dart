import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/responsive.dart';
import '../../models/academics.dart';
import '../../models/school.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/upload_button.dart';

/// A teacher's workspace for one subject they teach: capture marks against
/// assessments, publish dated lesson plans, and set homework with due dates.
class TeacherSubjectScreen extends StatelessWidget {
  const TeacherSubjectScreen({super.key, required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final me = context.watch<AuthController>().appUser;

    return AppShell(
      title: 'Subject',
      breadcrumb: 'My classes > Subject',
      body: ContentContainer(
        maxWidth: 860,
        child: StreamBuilder<List<Subject>>(
          stream: db.watchSubjectsForTeacher(me?.uid ?? ''),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final subject =
                snap.data!.where((s) => s.id == subjectId).firstOrNull;
            if (subject == null) {
              return const EmptyState(
                  'Subject not found, or it is not assigned to you.');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(subject.name,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(subject.className,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Marks'),
                          Tab(text: 'Lesson plans'),
                          Tab(text: 'Homework'),
                        ],
                      ),
                      SizedBox(
                        height: 620,
                        child: TabBarView(
                          children: [
                            _MarksTab(subject: subject),
                            _LessonPlansTab(subject: subject),
                            _HomeworkTab(subject: subject),
                          ],
                        ),
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

// ---------------------------------------------------------------------------
// Marks
// ---------------------------------------------------------------------------

class _MarksTab extends StatelessWidget {
  const _MarksTab({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _NewAssessmentDialog(subject: subject)),
              icon: const Icon(Icons.add),
              label: const Text('New assessment'),
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<Assessment>>(
            stream: db.watchAssessmentsForSubject(subject.id),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final assessments = snap.data!;
              if (assessments.isEmpty) {
                return const EmptyState(
                    'No assessments yet — create one (e.g. "Term 1 test"), '
                    'then capture each learner\'s mark.',
                    icon: Icons.fact_check_outlined);
              }
              return Column(
                children: assessments
                    .map((a) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading:
                                const Icon(Icons.fact_check_outlined),
                            title: Text(a.title),
                            subtitle: Text(
                                'Term ${a.term} · out of ${a.outOf} · '
                                '${formatDate(a.date)}'),
                            trailing: const Icon(Icons.edit_note),
                            onTap: () => showDialog(
                              context: context,
                              builder: (_) => _CaptureMarksDialog(
                                  subject: subject, assessment: a),
                            ),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NewAssessmentDialog extends StatefulWidget {
  const _NewAssessmentDialog({required this.subject});
  final Subject subject;

  @override
  State<_NewAssessmentDialog> createState() => _NewAssessmentDialogState();
}

class _NewAssessmentDialogState extends State<_NewAssessmentDialog> {
  final _title = TextEditingController();
  final _outOf = TextEditingController(text: '100');
  int _term = 1;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _outOf.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showSnack(context, 'Give the assessment a title');
      return;
    }
    final db = context.read<FirestoreService>();
    final me = context.read<AuthController>().appUser;
    setState(() => _saving = true);
    try {
      await db.createAssessment(Assessment(
        id: '',
        title: _title.text.trim(),
        subjectId: widget.subject.id,
        subjectName: widget.subject.name,
        classId: widget.subject.classId,
        className: widget.subject.className,
        term: _term,
        outOf: int.tryParse(_outOf.text) ?? 100,
        date: _date,
        createdByUid: me?.uid ?? '',
        createdByName: me?.fullName ?? '',
      ));
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
      title: const Text('New assessment'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'Title', hintText: 'e.g. Term 1 test'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _term,
                    decoration: const InputDecoration(labelText: 'Term'),
                    items: const [1, 2, 3, 4]
                        .map((t) => DropdownMenuItem(
                            value: t, child: Text('Term $t')))
                        .toList(),
                    onChanged: (v) => setState(() => _term = v ?? 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _outOf,
                    decoration: const InputDecoration(labelText: 'Out of'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(DateTime.now().year - 1),
                  lastDate: DateTime(DateTime.now().year + 1),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date',
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(formatDate(_date)),
              ),
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
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// The mark sheet: every learner in the class with a score box.
class _CaptureMarksDialog extends StatefulWidget {
  const _CaptureMarksDialog(
      {required this.subject, required this.assessment});
  final Subject subject;
  final Assessment assessment;

  @override
  State<_CaptureMarksDialog> createState() => _CaptureMarksDialogState();
}

class _CaptureMarksDialogState extends State<_CaptureMarksDialog> {
  final Map<String, TextEditingController> _scores = {};
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    for (final c in _scores.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String learnerId) =>
      _scores.putIfAbsent(learnerId, () => TextEditingController());

  Future<void> _save(List<Learner> learners) async {
    final db = context.read<FirestoreService>();
    final me = context.read<AuthController>().appUser;
    setState(() => _saving = true);
    try {
      final marks = <Mark>[];
      for (final l in learners) {
        final text = _scores[l.id]?.text.trim() ?? '';
        if (text.isEmpty) continue; // not captured — leave as is
        final score = double.tryParse(text.replaceAll(',', '.'));
        if (score == null) continue;
        marks.add(Mark(
          id: '',
          learnerId: l.id,
          assessmentId: widget.assessment.id,
          learnerName: l.fullName,
          subjectId: widget.subject.id,
          subjectName: widget.subject.name,
          classId: widget.subject.classId,
          assessmentTitle: widget.assessment.title,
          term: widget.assessment.term,
          score: score,
          outOf: widget.assessment.outOf,
          parentUids: l.parentUids,
          capturedByName: me?.fullName ?? '',
          date: widget.assessment.date,
        ));
      }
      if (marks.isEmpty) {
        showSnack(context, 'Enter at least one mark');
        return;
      }
      await db.saveMarks(marks);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(context, '${marks.length} mark(s) saved.');
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
      title: Text(widget.assessment.title),
      content: SizedBox(
        width: 520,
        height: 460,
        child: StreamBuilder<List<Learner>>(
          stream: db.watchLearnersInClass(widget.subject.classId),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final learners = snap.data!;
            if (learners.isEmpty) {
              return const EmptyState(
                  'No learners assigned to this class yet.');
            }
            return StreamBuilder<List<Mark>>(
              stream: db.watchMarksForAssessment(widget.assessment.id),
              builder: (context, markSnap) {
                // Prefill previously captured marks once.
                if (!_loaded && markSnap.hasData) {
                  for (final m in markSnap.data!) {
                    _controllerFor(m.learnerId).text =
                        m.score.toStringAsFixed(
                            m.score == m.score.roundToDouble() ? 0 : 1);
                  }
                  _loaded = true;
                }
                return Column(
                  children: [
                    Text(
                        'Out of ${widget.assessment.outOf} · Term '
                        '${widget.assessment.term}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: learners.length,
                        itemBuilder: (context, i) {
                          final l = learners[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(child: Text(l.fullName)),
                                SizedBox(
                                  width: 110,
                                  child: TextField(
                                    controller: _controllerFor(l.id),
                                    textAlign: TextAlign.end,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      suffixText:
                                          '/ ${widget.assessment.outOf}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed:
                          _saving ? null : () => _save(learners),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save marks'),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Lesson plans
// ---------------------------------------------------------------------------

class _LessonPlansTab extends StatelessWidget {
  const _LessonPlansTab({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _NewLessonPlanDialog(subject: subject)),
              icon: const Icon(Icons.add),
              label: const Text('New lesson plan'),
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<LessonPlan>>(
            stream: db.watchLessonPlansForClass(subject.classId),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final plans = snap.data!
                  .where((p) => p.subjectId == subject.id)
                  .toList();
              if (plans.isEmpty) {
                return const EmptyState(
                    'No lesson plans yet — add one so parents can see what '
                    'the learners are doing.',
                    icon: Icons.menu_book_outlined);
              }
              return Column(
                children: plans
                    .map((p) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ExpansionTile(
                            leading:
                                const Icon(Icons.menu_book_outlined),
                            title: Text(p.title),
                            subtitle: Text(p.endDate == null
                                ? formatDate(p.date)
                                : '${formatDate(p.date)} – ${formatDate(p.endDate)}'),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            children: [
                              if (p.objectives.isNotEmpty)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child:
                                      InfoLine('Objectives', p.objectives),
                                ),
                              if (p.content.isNotEmpty)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.only(top: 4),
                                    child: Text(p.content),
                                  ),
                                ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    final ok = await confirmDialog(
                                      context,
                                      'Delete "${p.title}"?',
                                      'The lesson plan is removed for '
                                          'everyone.',
                                      confirmLabel: 'Delete',
                                    );
                                    if (ok) {
                                      await db.deleteLessonPlan(p.id);
                                    }
                                  },
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  label: const Text('Delete'),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NewLessonPlanDialog extends StatefulWidget {
  const _NewLessonPlanDialog({required this.subject});
  final Subject subject;

  @override
  State<_NewLessonPlanDialog> createState() => _NewLessonPlanDialogState();
}

class _NewLessonPlanDialogState extends State<_NewLessonPlanDialog> {
  final _title = TextEditingController();
  final _objectives = TextEditingController();
  final _content = TextEditingController();
  DateTime _date = DateTime.now();
  DateTime? _endDate;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _objectives.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showSnack(context, 'Give the lesson plan a title');
      return;
    }
    final db = context.read<FirestoreService>();
    final me = context.read<AuthController>().appUser;
    setState(() => _saving = true);
    try {
      await db.createLessonPlan(LessonPlan(
        id: '',
        title: _title.text.trim(),
        subjectId: widget.subject.id,
        subjectName: widget.subject.name,
        classId: widget.subject.classId,
        className: widget.subject.className,
        objectives: _objectives.text.trim(),
        content: _content.text.trim(),
        date: _date,
        endDate: _endDate,
        teacherUid: me?.uid ?? '',
        teacherName: me?.fullName ?? '',
      ));
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
      title: const Text('New lesson plan'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Fractions — introduction'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(DateTime.now().year - 1),
                          lastDate: DateTime(DateTime.now().year + 1),
                        );
                        if (picked != null) {
                          setState(() => _date = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration:
                            const InputDecoration(labelText: 'Date'),
                        child: Text(formatDate(_date)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _endDate ?? _date,
                          firstDate: _date,
                          lastDate: DateTime(DateTime.now().year + 1),
                        );
                        if (picked != null) {
                          setState(() => _endDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'Ends (optional)'),
                        child: Text(_endDate == null
                            ? '—'
                            : formatDate(_endDate)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _objectives,
                decoration:
                    const InputDecoration(labelText: 'Objectives'),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _content,
                decoration: const InputDecoration(
                    labelText: 'What the learners will be doing'),
                minLines: 3,
                maxLines: 8,
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
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Homework
// ---------------------------------------------------------------------------

class _HomeworkTab extends StatelessWidget {
  const _HomeworkTab({required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => showDialog(
                  context: context,
                  builder: (_) => _NewHomeworkDialog(subject: subject)),
              icon: const Icon(Icons.add),
              label: const Text('Set homework'),
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<Homework>>(
            stream: db.watchHomeworkForClass(subject.classId),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data!
                  .where((h) => h.subjectId == subject.id)
                  .toList();
              if (items.isEmpty) {
                return const EmptyState(
                    'No homework set yet — add one with a due date.',
                    icon: Icons.assignment_turned_in_outlined);
              }
              return Column(
                children: items
                    .map((h) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(h.title,
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.bold)),
                                    ),
                                    StatusChip(
                                      h.isOverdue
                                          ? 'Due ${formatDate(h.dueDate)}'
                                          : 'Due in ${h.daysUntilDue} day(s)',
                                      h.isOverdue
                                          ? Colors.grey
                                          : Colors.blue,
                                    ),
                                  ],
                                ),
                                if (h.instructions.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(h.instructions),
                                ],
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    if (h.attachmentUrl.isNotEmpty)
                                      TextButton.icon(
                                        onPressed: () => launchUrl(
                                            Uri.parse(h.attachmentUrl),
                                            mode: LaunchMode
                                                .externalApplication),
                                        icon: const Icon(
                                            Icons.attach_file,
                                            size: 18),
                                        label: Text(h.attachmentName.isEmpty
                                            ? 'Attachment'
                                            : h.attachmentName),
                                      ),
                                    TextButton.icon(
                                      onPressed: () async {
                                        final ok = await confirmDialog(
                                          context,
                                          'Delete "${h.title}"?',
                                          'Learners and parents will no '
                                              'longer see it.',
                                          confirmLabel: 'Delete',
                                        );
                                        if (ok) {
                                          await db.deleteHomework(h.id);
                                        }
                                      },
                                      icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18),
                                      label: const Text('Delete'),
                                    ),
                                  ],
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
    );
  }
}

class _NewHomeworkDialog extends StatefulWidget {
  const _NewHomeworkDialog({required this.subject});
  final Subject subject;

  @override
  State<_NewHomeworkDialog> createState() => _NewHomeworkDialogState();
}

class _NewHomeworkDialogState extends State<_NewHomeworkDialog> {
  final _title = TextEditingController();
  final _instructions = TextEditingController();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  PickedUpload? _attachment;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showSnack(context, 'Give the homework a title');
      return;
    }
    final db = context.read<FirestoreService>();
    final storage = context.read<StorageService>();
    final auth = context.read<AuthController>();
    final me = auth.appUser;
    setState(() => _saving = true);
    try {
      var url = '';
      if (_attachment != null) {
        url = await storage.uploadHomework(
          auth.activeSchoolId ?? 'unknown',
          _attachment!.bytes,
          filename: _attachment!.filename,
          contentType: _attachment!.contentType,
        );
      }
      await db.createHomework(Homework(
        id: '',
        title: _title.text.trim(),
        subjectId: widget.subject.id,
        subjectName: widget.subject.name,
        classId: widget.subject.classId,
        className: widget.subject.className,
        instructions: _instructions.text.trim(),
        dueDate: _dueDate,
        attachmentUrl: url,
        attachmentName: _attachment?.filename ?? '',
        teacherUid: me?.uid ?? '',
        teacherName: me?.fullName ?? '',
      ));
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
      title: const Text('Set homework'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Worksheet 3 — fractions'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _instructions,
                decoration:
                    const InputDecoration(labelText: 'Instructions'),
                minLines: 2,
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dueDate,
                    firstDate: DateTime.now()
                        .subtract(const Duration(days: 1)),
                    lastDate:
                        DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Due date',
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(formatDate(_dueDate)),
                ),
              ),
              const SizedBox(height: 12),
              UploadButton(
                label: 'Attach worksheet (optional)',
                filename: _attachment?.filename,
                onPicked: (f) => setState(() => _attachment = f),
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
              : const Text('Set homework'),
        ),
      ],
    );
  }
}
