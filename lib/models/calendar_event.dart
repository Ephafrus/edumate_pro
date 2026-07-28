import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// A school calendar event at `events/{id}` — added by admin (any audience)
/// or a teacher (their own classes). Audience decides who sees it:
///  * [EventAudience.school] — everyone (staff + parents);
///  * [EventAudience.schoolClass] — the class teacher + parents of learners
///    in that class;
///  * [EventAudience.parents] — all parents.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.description = '',
    this.audience = EventAudience.school,
    this.classId,
    this.className = '',
    this.createdByUid = '',
    this.createdByName = '',
    this.createdAt,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final String description;
  final EventAudience audience;
  final String? classId;
  final String className;
  final String createdByUid;
  final String createdByName;
  final DateTime? createdAt;

  String get audienceLabel => audience == EventAudience.schoolClass
      ? (className.isEmpty ? 'A class' : className)
      : audience.label;

  Map<String, dynamic> toMap() => {
        'title': title,
        'start': Timestamp.fromDate(start),
        'end': end != null ? Timestamp.fromDate(end!) : null,
        'description': description,
        'audience': audience.name,
        'classId': classId,
        'className': className,
        'createdByUid': createdByUid,
        'createdByName': createdByName,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory CalendarEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return CalendarEvent(
      id: doc.id,
      title: (m['title'] ?? '') as String,
      start: (m['start'] as Timestamp?)?.toDate() ?? DateTime.now(),
      end: (m['end'] as Timestamp?)?.toDate(),
      description: (m['description'] ?? '') as String,
      audience: EventAudience.fromString(m['audience'] as String?),
      classId: m['classId'] as String?,
      className: (m['className'] ?? '') as String,
      createdByUid: (m['createdByUid'] ?? '') as String,
      createdByName: (m['createdByName'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
