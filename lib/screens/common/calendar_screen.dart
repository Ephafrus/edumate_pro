import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/responsive.dart';
import '../../models/app_user.dart';
import '../../models/calendar_event.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// The school calendar, shared by every role with audience filtering:
///  * whole-school events — everyone;
///  * class events — that class's teacher and its learners' parents;
///  * parents events — all parents (admin sees everything).
/// Admin adds events for any audience; a teacher adds events for their own
/// classes.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final user = context.watch<AuthController>().appUser;
    if (user == null) {
      return const AppShell(title: 'Calendar', body: SizedBox());
    }

    // The class ids relevant to me: classes I teach, or my children's classes.
    final Stream<Set<String>> classIdsStream;
    if (user.isTeacher) {
      classIdsStream = db
          .watchClassesForTeacher(user.uid)
          .map((cs) => cs.map((c) => c.id).toSet());
    } else if (user.isParent) {
      classIdsStream = db.watchLearnersForParent(user.uid).map((ls) => ls
          .map((l) => l.classId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet());
    } else {
      classIdsStream = Stream.value(const <String>{});
    }

    return AppShell(
      title: 'Calendar',
      body: ContentContainer(
        maxWidth: 760,
        child: StreamBuilder<Set<String>>(
          stream: classIdsStream,
          initialData: const <String>{},
          builder: (context, classSnap) {
            final myClassIds = classSnap.data ?? const <String>{};
            return StreamBuilder<List<CalendarEvent>>(
              stream: db.watchEvents(),
              builder: (context, snap) {
                final events = (snap.data ?? [])
                    .where((e) => e.visibleTo(user, myClassIds))
                    .toList();
                final byDay = <DateTime, List<CalendarEvent>>{};
                for (final e in events) {
                  final key =
                      DateTime(e.start.year, e.start.month, e.start.day);
                  byDay.putIfAbsent(key, () => []).add(e);
                }
                List<CalendarEvent> eventsOn(DateTime day) =>
                    byDay[DateTime(day.year, day.month, day.day)] ??
                    const [];

                final dayEvents = eventsOn(_selected);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('School calendar',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ),
                        if (user.isStaff)
                          FilledButton.icon(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => _AddEventDialog(
                                  user: user, initialDate: _selected),
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Add event'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: TableCalendar<CalendarEvent>(
                          firstDay: DateTime.now()
                              .subtract(const Duration(days: 365)),
                          lastDay: DateTime.now()
                              .add(const Duration(days: 730)),
                          focusedDay: _focused,
                          selectedDayPredicate: (d) =>
                              isSameDay(d, _selected),
                          eventLoader: eventsOn,
                          startingDayOfWeek: StartingDayOfWeek.monday,
                          calendarStyle: CalendarStyle(
                            todayDecoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                            selectedDecoration: BoxDecoration(
                              color:
                                  Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            markerDecoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .tertiary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                          ),
                          onDaySelected: (selected, focused) =>
                              setState(() {
                            _selected = selected;
                            _focused = focused;
                          }),
                          onPageChanged: (focused) => _focused = focused,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title:
                          'Events on ${formatDate(_selected)}',
                      child: dayEvents.isEmpty
                          ? const Text('No events on this day',
                              style: TextStyle(color: Colors.grey))
                          : Column(
                              children: dayEvents
                                  .map((e) => ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                            Icons.event_outlined),
                                        title: Text(e.title),
                                        subtitle: Text([
                                          '${TimeOfDay.fromDateTime(e.start).format(context)}'
                                              '${e.end != null ? '–${TimeOfDay.fromDateTime(e.end!).format(context)}' : ''}',
                                          e.audienceLabel,
                                          if (e.description.isNotEmpty)
                                            e.description,
                                        ].join(' · ')),
                                        trailing: (user.isAdmin ||
                                                e.createdByUid ==
                                                    user.uid)
                                            ? IconButton(
                                                tooltip: 'Delete event',
                                                icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 20),
                                                onPressed: () async {
                                                  final ok =
                                                      await confirmDialog(
                                                    context,
                                                    'Delete "${e.title}"?',
                                                    'This removes the event '
                                                        'for everyone.',
                                                    confirmLabel: 'Delete',
                                                  );
                                                  if (ok) {
                                                    await db
                                                        .deleteEvent(e.id);
                                                  }
                                                },
                                              )
                                            : null,
                                      ))
                                  .toList(),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Add-event dialog. Admin picks any audience; teachers are limited to
/// their own classes.
class _AddEventDialog extends StatefulWidget {
  const _AddEventDialog({required this.user, required this.initialDate});
  final AppUser user;
  final DateTime initialDate;

  @override
  State<_AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<_AddEventDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  late DateTime _date = widget.initialDate;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay? _endTime;
  late EventAudience _audience =
      widget.user.isAdmin ? EventAudience.school : EventAudience.schoolClass;
  String? _classId;
  String _className = '';
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showSnack(context, 'Give the event a title');
      return;
    }
    if (_audience == EventAudience.schoolClass && _classId == null) {
      showSnack(context, 'Pick a class');
      return;
    }
    final db = context.read<FirestoreService>();
    setState(() => _saving = true);
    try {
      final start = DateTime(_date.year, _date.month, _date.day,
          _time.hour, _time.minute);
      await db.createEvent(CalendarEvent(
        id: '',
        title: _title.text.trim(),
        description: _description.text.trim(),
        start: start,
        end: _endTime != null
            ? DateTime(_date.year, _date.month, _date.day, _endTime!.hour,
                _endTime!.minute)
            : null,
        audience: _audience,
        classId:
            _audience == EventAudience.schoolClass ? _classId : null,
        className:
            _audience == EventAudience.schoolClass ? _className : '',
        createdByUid: widget.user.uid,
        createdByName: widget.user.fullName,
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
    final db = context.read<FirestoreService>();
    final classesStream = widget.user.isAdmin
        ? db.watchClasses()
        : db.watchClassesForTeacher(widget.user.uid);

    return AlertDialog(
      title: const Text('Add event'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(
                    labelText: 'Description (optional)'),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              if (widget.user.isAdmin) ...[
                DropdownButtonFormField<EventAudience>(
                  initialValue: _audience,
                  decoration: const InputDecoration(labelText: 'For'),
                  items: EventAudience.values
                      .map((a) => DropdownMenuItem(
                          value: a, child: Text(a.label)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _audience = v ?? _audience),
                ),
                const SizedBox(height: 12),
              ],
              if (_audience == EventAudience.schoolClass) ...[
                StreamBuilder<List<SchoolClass>>(
                  stream: classesStream,
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
                const SizedBox(height: 12),
              ],
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now()
                        .subtract(const Duration(days: 365)),
                    lastDate:
                        DateTime.now().add(const Duration(days: 730)),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                            context: context, initialTime: _time);
                        if (picked != null) {
                          setState(() => _time = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration:
                            const InputDecoration(labelText: 'Starts'),
                        child: Text(_time.format(context)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                            context: context,
                            initialTime: _endTime ?? _time);
                        if (picked != null) {
                          setState(() => _endTime = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'Ends (optional)'),
                        child: Text(_endTime?.format(context) ?? '—'),
                      ),
                    ),
                  ),
                ],
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
          child: const Text('Add event'),
        ),
      ],
    );
  }
}
