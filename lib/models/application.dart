import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// A timeline event on an application — every status change is recorded so
/// parents can track progress ("Submitted → Under review → Accepted → …").
class ApplicationEvent {
  const ApplicationEvent({
    required this.status,
    this.note = '',
    this.byName = '',
    this.at,
  });

  final ApplicationStatus status;
  final String note;
  final String byName;
  final DateTime? at;

  Map<String, dynamic> toMap() => {
        'status': status.name,
        'note': note,
        'byName': byName,
        // Server timestamps are not allowed inside arrays; use client time.
        'at': Timestamp.fromDate(at ?? DateTime.now()),
      };

  factory ApplicationEvent.fromMap(Map<String, dynamic> m) => ApplicationEvent(
        status: ApplicationStatus.fromString(m['status'] as String?),
        note: (m['note'] ?? '') as String,
        byName: (m['byName'] ?? '') as String,
        at: (m['at'] as Timestamp?)?.toDate(),
      );
}

/// An enrollment application at `applications/{id}`, captured through the
/// step-by-step wizard: learner details → guardian details → medical &
/// language info → supporting documents → review & submit.
class EnrollmentApplication {
  const EnrollmentApplication({
    required this.id,
    required this.parentUid,
    this.status = ApplicationStatus.draft,
    // Step 1 — learner
    this.learnerFirstName = '',
    this.learnerLastName = '',
    this.learnerIdType,
    this.learnerIdNumber = '',
    this.learnerDob,
    this.learnerGender,
    this.gradeApplyingFor = '',
    this.homeLanguage = '',
    this.previousSchool = '',
    // Step 2 — guardian
    this.guardianFirstName = '',
    this.guardianLastName = '',
    this.guardianRelationship = '',
    this.guardianPhone = '',
    this.guardianEmail = '',
    this.guardianAddress = '',
    this.guardianProvince = '',
    // Step 3 — medical / additional
    this.medicalConditions = '',
    this.doctorName = '',
    this.doctorPhone = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.notes = '',
    // Step 4 — documents
    this.documents = const {},
    // Tracking
    this.events = const [],
    this.rejectionReason = '',
    this.learnerId,
    this.createdAt,
    this.updatedAt,
    this.submittedAt,
  });

  final String id;
  final String parentUid;
  final ApplicationStatus status;

  final String learnerFirstName;
  final String learnerLastName;
  final IdType? learnerIdType;
  final String learnerIdNumber;
  final DateTime? learnerDob;
  final Gender? learnerGender;
  final String gradeApplyingFor;
  final String homeLanguage;
  final String previousSchool;

  final String guardianFirstName;
  final String guardianLastName;
  final String guardianRelationship;
  final String guardianPhone;
  final String guardianEmail;
  final String guardianAddress;
  final String guardianProvince;

  final String medicalConditions;
  final String doctorName;
  final String doctorPhone;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String notes;

  /// Uploaded supporting documents: label → storage download URL
  /// (e.g. "Birth certificate" → https://...).
  final Map<String, String> documents;

  /// Status history, oldest first.
  final List<ApplicationEvent> events;
  final String rejectionReason;

  /// Set when the application is enrolled and a learner record is created.
  final String? learnerId;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? submittedAt;

  String get learnerFullName => '$learnerFirstName $learnerLastName'.trim();
  String get guardianFullName => '$guardianFirstName $guardianLastName'.trim();
  bool get isDraft => status == ApplicationStatus.draft;

  Map<String, dynamic> toMap() => {
        'parentUid': parentUid,
        'status': status.name,
        'learnerFirstName': learnerFirstName,
        'learnerLastName': learnerLastName,
        'learnerIdType': learnerIdType?.name,
        'learnerIdNumber': learnerIdNumber,
        'learnerDob':
            learnerDob != null ? Timestamp.fromDate(learnerDob!) : null,
        'learnerGender': learnerGender?.name,
        'gradeApplyingFor': gradeApplyingFor,
        'homeLanguage': homeLanguage,
        'previousSchool': previousSchool,
        'guardianFirstName': guardianFirstName,
        'guardianLastName': guardianLastName,
        'guardianRelationship': guardianRelationship,
        'guardianPhone': guardianPhone,
        'guardianEmail': guardianEmail,
        'guardianAddress': guardianAddress,
        'guardianProvince': guardianProvince,
        'medicalConditions': medicalConditions,
        'doctorName': doctorName,
        'doctorPhone': doctorPhone,
        'emergencyContactName': emergencyContactName,
        'emergencyContactPhone': emergencyContactPhone,
        'notes': notes,
        'documents': documents,
        'events': events.map((e) => e.toMap()).toList(),
        'rejectionReason': rejectionReason,
        'learnerId': learnerId,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'submittedAt':
            submittedAt != null ? Timestamp.fromDate(submittedAt!) : null,
      };

  factory EnrollmentApplication.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return EnrollmentApplication(
      id: doc.id,
      parentUid: (m['parentUid'] ?? '') as String,
      status: ApplicationStatus.fromString(m['status'] as String?),
      learnerFirstName: (m['learnerFirstName'] ?? '') as String,
      learnerLastName: (m['learnerLastName'] ?? '') as String,
      learnerIdType: IdType.fromString(m['learnerIdType'] as String?),
      learnerIdNumber: (m['learnerIdNumber'] ?? '') as String,
      learnerDob: (m['learnerDob'] as Timestamp?)?.toDate(),
      learnerGender: Gender.fromString(m['learnerGender'] as String?),
      gradeApplyingFor: (m['gradeApplyingFor'] ?? '') as String,
      homeLanguage: (m['homeLanguage'] ?? '') as String,
      previousSchool: (m['previousSchool'] ?? '') as String,
      guardianFirstName: (m['guardianFirstName'] ?? '') as String,
      guardianLastName: (m['guardianLastName'] ?? '') as String,
      guardianRelationship: (m['guardianRelationship'] ?? '') as String,
      guardianPhone: (m['guardianPhone'] ?? '') as String,
      guardianEmail: (m['guardianEmail'] ?? '') as String,
      guardianAddress: (m['guardianAddress'] ?? '') as String,
      guardianProvince: (m['guardianProvince'] ?? '') as String,
      medicalConditions: (m['medicalConditions'] ?? '') as String,
      doctorName: (m['doctorName'] ?? '') as String,
      doctorPhone: (m['doctorPhone'] ?? '') as String,
      emergencyContactName: (m['emergencyContactName'] ?? '') as String,
      emergencyContactPhone: (m['emergencyContactPhone'] ?? '') as String,
      notes: (m['notes'] ?? '') as String,
      documents: ((m['documents'] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', '$v')),
      events: ((m['events'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ApplicationEvent.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      rejectionReason: (m['rejectionReason'] ?? '') as String,
      learnerId: m['learnerId'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
      submittedAt: (m['submittedAt'] as Timestamp?)?.toDate(),
    );
  }
}
