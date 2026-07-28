import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// A class/register group at `classes/{id}` (e.g. "Grade 4 Blue"), optionally
/// assigned to a teacher. Learners reference their class via `classId`.
class SchoolClass {
  const SchoolClass({
    required this.id,
    required this.name,
    required this.grade,
    this.year,
    this.teacherUid,
    this.teacherName = '',
    this.createdAt,
  });

  final String id;
  final String name;
  final String grade;
  final int? year;
  final String? teacherUid;

  /// Denormalised for list rendering without extra reads.
  final String teacherName;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'name': name,
        'grade': grade,
        'year': year,
        'teacherUid': teacherUid,
        'teacherName': teacherName,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory SchoolClass.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return SchoolClass(
      id: doc.id,
      name: (m['name'] ?? '') as String,
      grade: (m['grade'] ?? '') as String,
      year: (m['year'] as num?)?.toInt(),
      teacherUid: m['teacherUid'] as String?,
      teacherName: (m['teacherName'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// A learner at `learners/{id}`. Created by an admin directly, or
/// automatically when an application is marked enrolled. Linked to a class
/// via [classId] and to parent accounts via [parentUids].
class Learner {
  const Learner({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.grade = '',
    this.dateOfBirth,
    this.gender,
    this.idNumber = '',
    this.status = LearnerStatus.applicant,
    this.classId,
    this.className = '',
    this.parentUids = const [],
    this.applicationId,
    this.attendanceStatus,
    this.lastAttendanceAt,
    this.createdAt,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String grade;
  final DateTime? dateOfBirth;
  final Gender? gender;
  final String idNumber;
  final LearnerStatus status;
  final String? classId;

  /// Denormalised class name for list rendering.
  final String className;

  /// Parent/guardian account uids linked to this learner.
  final List<String> parentUids;

  /// The enrollment application this learner originated from, if any.
  final String? applicationId;

  /// Last QR attendance scan: checkIn = in school, checkOut = left school.
  final AttendanceType? attendanceStatus;
  final DateTime? lastAttendanceAt;
  final DateTime? createdAt;

  String get fullName => '$firstName $lastName'.trim();
  bool get isInSchool => attendanceStatus == AttendanceType.checkIn;

  Map<String, dynamic> toMap() => {
        'firstName': firstName,
        'lastName': lastName,
        'grade': grade,
        'dateOfBirth':
            dateOfBirth != null ? Timestamp.fromDate(dateOfBirth!) : null,
        'gender': gender?.name,
        'idNumber': idNumber,
        'status': status.name,
        'classId': classId,
        'className': className,
        'parentUids': parentUids,
        'applicationId': applicationId,
        'attendanceStatus': attendanceStatus?.name,
        'lastAttendanceAt': lastAttendanceAt != null
            ? Timestamp.fromDate(lastAttendanceAt!)
            : null,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory Learner.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Learner(
      id: doc.id,
      firstName: (m['firstName'] ?? '') as String,
      lastName: (m['lastName'] ?? '') as String,
      grade: (m['grade'] ?? '') as String,
      dateOfBirth: (m['dateOfBirth'] as Timestamp?)?.toDate(),
      gender: Gender.fromString(m['gender'] as String?),
      idNumber: (m['idNumber'] ?? '') as String,
      status: LearnerStatus.fromString(m['status'] as String?),
      classId: m['classId'] as String?,
      className: (m['className'] ?? '') as String,
      parentUids:
          ((m['parentUids'] as List?) ?? const []).map((e) => '$e').toList(),
      applicationId: m['applicationId'] as String?,
      attendanceStatus: m['attendanceStatus'] == null
          ? null
          : AttendanceType.fromString(m['attendanceStatus'] as String?),
      lastAttendanceAt: (m['lastAttendanceAt'] as Timestamp?)?.toDate(),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Learner copyWith({
    String? firstName,
    String? lastName,
    String? grade,
    DateTime? dateOfBirth,
    Gender? gender,
    String? idNumber,
    LearnerStatus? status,
    String? classId,
    String? className,
    List<String>? parentUids,
  }) =>
      Learner(
        id: id,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        grade: grade ?? this.grade,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        gender: gender ?? this.gender,
        idNumber: idNumber ?? this.idNumber,
        status: status ?? this.status,
        classId: classId ?? this.classId,
        className: className ?? this.className,
        parentUids: parentUids ?? this.parentUids,
        applicationId: applicationId,
        attendanceStatus: attendanceStatus,
        lastAttendanceAt: lastAttendanceAt,
        createdAt: createdAt,
      );
}
