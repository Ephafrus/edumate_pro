import 'package:cloud_firestore/cloud_firestore.dart';

/// A subject taught in a class, at `schools/{schoolId}/subjects/{id}`
/// (e.g. "Mathematics" in Grade 4 Blue). The school admin creates subjects
/// on a class and assigns the teacher who teaches it; that teacher then
/// captures marks, lesson plans and homework against it.
class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.classId,
    this.className = '',
    this.teacherUid,
    this.teacherName = '',
    this.createdAt,
  });

  final String id;
  final String name;
  final String classId;

  /// Denormalised so lists render without a join.
  final String className;
  final String? teacherUid;
  final String teacherName;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'name': name,
        'classId': classId,
        'className': className,
        'teacherUid': teacherUid,
        'teacherName': teacherName,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory Subject.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Subject(
      id: doc.id,
      name: (m['name'] ?? '') as String,
      classId: (m['classId'] ?? '') as String,
      className: (m['className'] ?? '') as String,
      teacherUid: m['teacherUid'] as String?,
      teacherName: (m['teacherName'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// An assessment a teacher captures marks against, at
/// `schools/{schoolId}/assessments/{id}` — e.g. "Term 1 test", out of 50.
class Assessment {
  const Assessment({
    required this.id,
    required this.title,
    required this.subjectId,
    this.subjectName = '',
    this.classId = '',
    this.className = '',
    this.term = 1,
    this.outOf = 100,
    this.date,
    this.createdByUid = '',
    this.createdByName = '',
    this.createdAt,
  });

  final String id;
  final String title;
  final String subjectId;
  final String subjectName;
  final String classId;
  final String className;
  final int term;
  final int outOf;
  final DateTime? date;
  final String createdByUid;
  final String createdByName;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'title': title,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'classId': classId,
        'className': className,
        'term': term,
        'outOf': outOf,
        'date': date != null ? Timestamp.fromDate(date!) : null,
        'createdByUid': createdByUid,
        'createdByName': createdByName,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory Assessment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Assessment(
      id: doc.id,
      title: (m['title'] ?? '') as String,
      subjectId: (m['subjectId'] ?? '') as String,
      subjectName: (m['subjectName'] ?? '') as String,
      classId: (m['classId'] ?? '') as String,
      className: (m['className'] ?? '') as String,
      term: (m['term'] as num?)?.toInt() ?? 1,
      outOf: (m['outOf'] as num?)?.toInt() ?? 100,
      date: (m['date'] as Timestamp?)?.toDate(),
      createdByUid: (m['createdByUid'] ?? '') as String,
      createdByName: (m['createdByName'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// One learner's mark for one assessment, at
/// `schools/{schoolId}/marks/{id}`. Denormalised with the subject and class
/// so progress reports and the parent dashboard read from a single query.
class Mark {
  const Mark({
    required this.id,
    required this.learnerId,
    required this.assessmentId,
    this.learnerName = '',
    this.subjectId = '',
    this.subjectName = '',
    this.classId = '',
    this.assessmentTitle = '',
    this.term = 1,
    this.score = 0,
    this.outOf = 100,
    this.comment = '',
    this.parentUids = const [],
    this.capturedByName = '',
    this.date,
    this.updatedAt,
  });

  final String id;
  final String learnerId;
  final String assessmentId;
  final String learnerName;
  final String subjectId;
  final String subjectName;
  final String classId;
  final String assessmentTitle;
  final int term;
  final double score;
  final int outOf;
  final String comment;

  /// Copied from the learner so parents can read their own child's marks.
  final List<String> parentUids;
  final String capturedByName;
  final DateTime? date;
  final DateTime? updatedAt;

  double get percentage => outOf == 0 ? 0 : (score / outOf) * 100;
  String get percentageLabel => '${percentage.toStringAsFixed(0)}%';

  /// South African school symbol bands (levels 1–7).
  String get symbol {
    final p = percentage;
    if (p >= 80) return 'A';
    if (p >= 70) return 'B';
    if (p >= 60) return 'C';
    if (p >= 50) return 'D';
    if (p >= 40) return 'E';
    if (p >= 30) return 'F';
    return 'G';
  }

  Map<String, dynamic> toMap() => {
        'learnerId': learnerId,
        'assessmentId': assessmentId,
        'learnerName': learnerName,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'classId': classId,
        'assessmentTitle': assessmentTitle,
        'term': term,
        'score': score,
        'outOf': outOf,
        'comment': comment,
        'parentUids': parentUids,
        'capturedByName': capturedByName,
        'date': date != null ? Timestamp.fromDate(date!) : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  factory Mark.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Mark(
      id: doc.id,
      learnerId: (m['learnerId'] ?? '') as String,
      assessmentId: (m['assessmentId'] ?? '') as String,
      learnerName: (m['learnerName'] ?? '') as String,
      subjectId: (m['subjectId'] ?? '') as String,
      subjectName: (m['subjectName'] ?? '') as String,
      classId: (m['classId'] ?? '') as String,
      assessmentTitle: (m['assessmentTitle'] ?? '') as String,
      term: (m['term'] as num?)?.toInt() ?? 1,
      score: (m['score'] as num?)?.toDouble() ?? 0,
      outOf: (m['outOf'] as num?)?.toInt() ?? 100,
      comment: (m['comment'] ?? '') as String,
      parentUids:
          ((m['parentUids'] as List?) ?? const []).map((e) => '$e').toList(),
      capturedByName: (m['capturedByName'] ?? '') as String,
      date: (m['date'] as Timestamp?)?.toDate(),
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// A dated lesson plan at `schools/{schoolId}/lessonPlans/{id}`: what the
/// learners are doing in a subject on a given date (or over a date range).
class LessonPlan {
  const LessonPlan({
    required this.id,
    required this.title,
    required this.subjectId,
    this.subjectName = '',
    this.classId = '',
    this.className = '',
    this.content = '',
    this.objectives = '',
    required this.date,
    this.endDate,
    this.teacherUid = '',
    this.teacherName = '',
    this.createdAt,
  });

  final String id;
  final String title;
  final String subjectId;
  final String subjectName;
  final String classId;
  final String className;

  /// What the learners will be doing.
  final String content;
  final String objectives;

  /// The lesson date; [endDate] covers a plan that spans a week.
  final DateTime date;
  final DateTime? endDate;
  final String teacherUid;
  final String teacherName;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'title': title,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'classId': classId,
        'className': className,
        'content': content,
        'objectives': objectives,
        'date': Timestamp.fromDate(date),
        'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
        'teacherUid': teacherUid,
        'teacherName': teacherName,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory LessonPlan.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return LessonPlan(
      id: doc.id,
      title: (m['title'] ?? '') as String,
      subjectId: (m['subjectId'] ?? '') as String,
      subjectName: (m['subjectName'] ?? '') as String,
      classId: (m['classId'] ?? '') as String,
      className: (m['className'] ?? '') as String,
      content: (m['content'] ?? '') as String,
      objectives: (m['objectives'] ?? '') as String,
      date: (m['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (m['endDate'] as Timestamp?)?.toDate(),
      teacherUid: (m['teacherUid'] ?? '') as String,
      teacherName: (m['teacherName'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Homework at `schools/{schoolId}/homework/{id}` — set by a teacher for a
/// class/subject with a **due date** and an optional uploaded attachment.
class Homework {
  const Homework({
    required this.id,
    required this.title,
    required this.subjectId,
    this.subjectName = '',
    this.classId = '',
    this.className = '',
    this.instructions = '',
    required this.dueDate,
    this.attachmentUrl = '',
    this.attachmentName = '',
    this.teacherUid = '',
    this.teacherName = '',
    this.createdAt,
  });

  final String id;
  final String title;
  final String subjectId;
  final String subjectName;
  final String classId;
  final String className;
  final String instructions;
  final DateTime dueDate;

  /// Optional uploaded worksheet (PDF/image).
  final String attachmentUrl;
  final String attachmentName;
  final String teacherUid;
  final String teacherName;
  final DateTime? createdAt;

  bool get isOverdue => DateTime.now().isAfter(dueDate);

  /// Days until due — negative once overdue.
  int get daysUntilDue =>
      DateTime(dueDate.year, dueDate.month, dueDate.day)
          .difference(DateTime(
              DateTime.now().year, DateTime.now().month, DateTime.now().day))
          .inDays;

  Map<String, dynamic> toMap() => {
        'title': title,
        'subjectId': subjectId,
        'subjectName': subjectName,
        'classId': classId,
        'className': className,
        'instructions': instructions,
        'dueDate': Timestamp.fromDate(dueDate),
        'attachmentUrl': attachmentUrl,
        'attachmentName': attachmentName,
        'teacherUid': teacherUid,
        'teacherName': teacherName,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory Homework.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Homework(
      id: doc.id,
      title: (m['title'] ?? '') as String,
      subjectId: (m['subjectId'] ?? '') as String,
      subjectName: (m['subjectName'] ?? '') as String,
      classId: (m['classId'] ?? '') as String,
      className: (m['className'] ?? '') as String,
      instructions: (m['instructions'] ?? '') as String,
      dueDate: (m['dueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      attachmentUrl: (m['attachmentUrl'] ?? '') as String,
      attachmentName: (m['attachmentName'] ?? '') as String,
      teacherUid: (m['teacherUid'] ?? '') as String,
      teacherName: (m['teacherName'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// A learner's aggregated performance in one subject — computed from marks
/// for progress reports and the parent dashboard.
class SubjectProgress {
  const SubjectProgress({
    required this.subjectId,
    required this.subjectName,
    required this.marks,
  });

  final String subjectId;
  final String subjectName;
  final List<Mark> marks;

  double get average => marks.isEmpty
      ? 0
      : marks.map((m) => m.percentage).reduce((a, b) => a + b) /
          marks.length;

  String get averageLabel => '${average.toStringAsFixed(0)}%';

  /// Difference between the latest and the first mark — the trend arrow.
  double get trend {
    if (marks.length < 2) return 0;
    final sorted = [...marks]..sort((a, b) =>
        (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));
    return sorted.last.percentage - sorted.first.percentage;
  }
}
