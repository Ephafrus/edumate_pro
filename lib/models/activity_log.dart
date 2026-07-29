import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// Broad grouping used to filter the Super Admin's activity feed.
enum ActivityCategory {
  auth,
  navigation,
  enrollment,
  learners,
  academics,
  attendance,
  finance,
  communication,
  administration,
  platform;

  String get label {
    switch (this) {
      case ActivityCategory.auth:
        return 'Sign-in';
      case ActivityCategory.navigation:
        return 'Navigation';
      case ActivityCategory.enrollment:
        return 'Enrollment';
      case ActivityCategory.learners:
        return 'Learners';
      case ActivityCategory.academics:
        return 'Academics';
      case ActivityCategory.attendance:
        return 'Attendance';
      case ActivityCategory.finance:
        return 'Finance';
      case ActivityCategory.communication:
        return 'Communication';
      case ActivityCategory.administration:
        return 'Administration';
      case ActivityCategory.platform:
        return 'Platform';
    }
  }
}

/// Every interaction the platform records. Stored as the string name, so
/// adding a value never breaks existing log documents.
enum ActivityAction {
  // Auth & session
  signedIn,
  signedOut,
  profileCreated,
  profileUpdated,
  schoolJoined,
  schoolSwitched,

  // Navigation (key screens)
  pageViewed,
  applyPageOpened,
  searchPerformed,

  // Enrollment
  applicationStarted,
  applicationSaved,
  applicationSubmitted,
  applicationStatusChanged,
  applicationCommented,
  applicationMessaged,
  learnerEnrolled,

  // Learners & classes
  learnerCreated,
  learnerUpdated,
  learnerDeleted,
  learnerClassAssigned,
  parentLinkChanged,
  classCreated,
  classUpdated,
  classDeleted,
  subjectCreated,
  subjectUpdated,
  subjectDeleted,
  teacherAssigned,

  // Academics
  assessmentCreated,
  marksCaptured,
  lessonPlanCreated,
  lessonPlanDeleted,
  homeworkCreated,
  homeworkDeleted,

  // Attendance
  attendanceScanned,

  // Finance
  paymentSubmitted,
  paymentReviewed,
  paymentRecorded,
  feeStructureChanged,
  paymentImportStaged,
  paymentImportResolved,

  // Communication
  broadcastSent,
  chatRequested,
  chatStarted,
  chatApprovalChanged,
  messageSent,
  emailSent,
  eventCreated,
  eventDeleted,

  // School administration
  staffInvited,
  staffInviteCancelled,
  memberAssigned,
  memberRoleChanged,
  memberRemoved,
  memberDeactivated,
  emailSettingsUpdated,

  // Platform (Super Admin)
  schoolCreated,
  schoolUpdated,
  schoolViewed,
  schoolViewExited,
  superAdminGranted,
  platformBootstrapped;

  static ActivityAction fromString(String? s) {
    for (final a in ActivityAction.values) {
      if (a.name == s) return a;
    }
    return ActivityAction.pageViewed;
  }

  ActivityCategory get category {
    switch (this) {
      case ActivityAction.signedIn:
      case ActivityAction.signedOut:
      case ActivityAction.profileCreated:
      case ActivityAction.profileUpdated:
      case ActivityAction.schoolJoined:
      case ActivityAction.schoolSwitched:
        return ActivityCategory.auth;
      case ActivityAction.pageViewed:
      case ActivityAction.applyPageOpened:
      case ActivityAction.searchPerformed:
        return ActivityCategory.navigation;
      case ActivityAction.applicationStarted:
      case ActivityAction.applicationSaved:
      case ActivityAction.applicationSubmitted:
      case ActivityAction.applicationStatusChanged:
      case ActivityAction.applicationCommented:
      case ActivityAction.applicationMessaged:
      case ActivityAction.learnerEnrolled:
        return ActivityCategory.enrollment;
      case ActivityAction.learnerCreated:
      case ActivityAction.learnerUpdated:
      case ActivityAction.learnerDeleted:
      case ActivityAction.learnerClassAssigned:
      case ActivityAction.parentLinkChanged:
      case ActivityAction.classCreated:
      case ActivityAction.classUpdated:
      case ActivityAction.classDeleted:
      case ActivityAction.subjectCreated:
      case ActivityAction.subjectUpdated:
      case ActivityAction.subjectDeleted:
      case ActivityAction.teacherAssigned:
        return ActivityCategory.learners;
      case ActivityAction.assessmentCreated:
      case ActivityAction.marksCaptured:
      case ActivityAction.lessonPlanCreated:
      case ActivityAction.lessonPlanDeleted:
      case ActivityAction.homeworkCreated:
      case ActivityAction.homeworkDeleted:
        return ActivityCategory.academics;
      case ActivityAction.attendanceScanned:
        return ActivityCategory.attendance;
      case ActivityAction.paymentSubmitted:
      case ActivityAction.paymentReviewed:
      case ActivityAction.paymentRecorded:
      case ActivityAction.feeStructureChanged:
      case ActivityAction.paymentImportStaged:
      case ActivityAction.paymentImportResolved:
        return ActivityCategory.finance;
      case ActivityAction.broadcastSent:
      case ActivityAction.chatRequested:
      case ActivityAction.chatStarted:
      case ActivityAction.chatApprovalChanged:
      case ActivityAction.messageSent:
      case ActivityAction.emailSent:
      case ActivityAction.eventCreated:
      case ActivityAction.eventDeleted:
        return ActivityCategory.communication;
      case ActivityAction.staffInvited:
      case ActivityAction.staffInviteCancelled:
      case ActivityAction.memberAssigned:
      case ActivityAction.memberRoleChanged:
      case ActivityAction.memberRemoved:
      case ActivityAction.memberDeactivated:
      case ActivityAction.emailSettingsUpdated:
        return ActivityCategory.administration;
      case ActivityAction.schoolCreated:
      case ActivityAction.schoolUpdated:
      case ActivityAction.schoolViewed:
      case ActivityAction.schoolViewExited:
      case ActivityAction.superAdminGranted:
      case ActivityAction.platformBootstrapped:
        return ActivityCategory.platform;
    }
  }

  /// Human sentence fragment: "<actor> <label>".
  String get label {
    switch (this) {
      case ActivityAction.signedIn:
        return 'signed in';
      case ActivityAction.signedOut:
        return 'signed out';
      case ActivityAction.profileCreated:
        return 'created their profile';
      case ActivityAction.profileUpdated:
        return 'updated their profile';
      case ActivityAction.schoolJoined:
        return 'joined a school';
      case ActivityAction.schoolSwitched:
        return 'switched school';
      case ActivityAction.pageViewed:
        return 'opened a page';
      case ActivityAction.applyPageOpened:
        return 'opened the enrollment application';
      case ActivityAction.searchPerformed:
        return 'searched';
      case ActivityAction.applicationStarted:
        return 'started an application';
      case ActivityAction.applicationSaved:
        return 'saved an application draft';
      case ActivityAction.applicationSubmitted:
        return 'submitted an application';
      case ActivityAction.applicationStatusChanged:
        return 'changed an application status';
      case ActivityAction.applicationCommented:
        return 'commented on an application';
      case ActivityAction.applicationMessaged:
        return 'messaged an applicant';
      case ActivityAction.learnerEnrolled:
        return 'enrolled a learner';
      case ActivityAction.learnerCreated:
        return 'added a learner';
      case ActivityAction.learnerUpdated:
        return 'updated a learner';
      case ActivityAction.learnerDeleted:
        return 'deleted a learner';
      case ActivityAction.learnerClassAssigned:
        return 'assigned a learner to a class';
      case ActivityAction.parentLinkChanged:
        return 'changed a parent link';
      case ActivityAction.classCreated:
        return 'created a class';
      case ActivityAction.classUpdated:
        return 'updated a class';
      case ActivityAction.classDeleted:
        return 'deleted a class';
      case ActivityAction.subjectCreated:
        return 'added a subject';
      case ActivityAction.subjectUpdated:
        return 'updated a subject';
      case ActivityAction.subjectDeleted:
        return 'deleted a subject';
      case ActivityAction.teacherAssigned:
        return 'assigned a teacher';
      case ActivityAction.assessmentCreated:
        return 'created an assessment';
      case ActivityAction.marksCaptured:
        return 'captured marks';
      case ActivityAction.lessonPlanCreated:
        return 'published a lesson plan';
      case ActivityAction.lessonPlanDeleted:
        return 'deleted a lesson plan';
      case ActivityAction.homeworkCreated:
        return 'set homework';
      case ActivityAction.homeworkDeleted:
        return 'deleted homework';
      case ActivityAction.attendanceScanned:
        return 'scanned attendance';
      case ActivityAction.paymentSubmitted:
        return 'submitted a payment';
      case ActivityAction.paymentReviewed:
        return 'reviewed a payment';
      case ActivityAction.paymentRecorded:
        return 'recorded a payment';
      case ActivityAction.feeStructureChanged:
        return 'changed a fee structure';
      case ActivityAction.paymentImportStaged:
        return 'uploaded a payment import';
      case ActivityAction.paymentImportResolved:
        return 'resolved a payment import';
      case ActivityAction.broadcastSent:
        return 'sent a broadcast';
      case ActivityAction.chatRequested:
        return 'requested a chat';
      case ActivityAction.chatStarted:
        return 'started a chat';
      case ActivityAction.chatApprovalChanged:
        return 'changed a chat approval';
      case ActivityAction.messageSent:
        return 'sent a message';
      case ActivityAction.emailSent:
        return 'sent an email';
      case ActivityAction.eventCreated:
        return 'added a calendar event';
      case ActivityAction.eventDeleted:
        return 'deleted a calendar event';
      case ActivityAction.staffInvited:
        return 'invited a staff member';
      case ActivityAction.staffInviteCancelled:
        return 'cancelled a staff invite';
      case ActivityAction.memberAssigned:
        return 'assigned somebody to a school';
      case ActivityAction.memberRoleChanged:
        return 'changed somebody\'s role';
      case ActivityAction.memberRemoved:
        return 'removed somebody from a school';
      case ActivityAction.memberDeactivated:
        return 'deactivated an account';
      case ActivityAction.emailSettingsUpdated:
        return 'updated email settings';
      case ActivityAction.schoolCreated:
        return 'created a school';
      case ActivityAction.schoolUpdated:
        return 'updated a school';
      case ActivityAction.schoolViewed:
        return 'signed in to a school as Super Admin';
      case ActivityAction.schoolViewExited:
        return 'left a school view';
      case ActivityAction.superAdminGranted:
        return 'granted Super Admin';
      case ActivityAction.platformBootstrapped:
        return 'set the platform up';
    }
  }
}

/// One immutable audit-trail entry at `activityLogs/{id}`.
///
/// Written by whoever performed the action (append-only — nobody can edit or
/// delete an entry) and readable only by a Super Admin, who reviews the whole
/// platform's activity in one feed.
class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.action,
    required this.actorUid,
    this.actorName = '',
    this.actorRole = '',
    this.schoolId,
    this.schoolName = '',
    this.target = '',
    this.details = '',
    this.at,
  });

  final String id;
  final ActivityAction action;
  final String actorUid;
  final String actorName;

  /// Role held at the time of the action ('superAdmin' for platform actions).
  final String actorRole;

  /// The school the action happened in — null for platform-level actions.
  final String? schoolId;
  final String schoolName;

  /// What was acted on, e.g. a learner or class name.
  final String target;

  /// Free-text extra context, e.g. "Grade 4 · submitted".
  final String details;
  final DateTime? at;

  ActivityCategory get category => action.category;

  /// "Thandi Mokoena submitted an application — Sipho Dlamini"
  String get summary {
    final who = actorName.isEmpty ? 'Someone' : actorName;
    final what = '$who ${action.label}';
    return target.isEmpty ? what : '$what — $target';
  }

  Map<String, dynamic> toMap() => {
        'action': action.name,
        'category': action.category.name,
        'actorUid': actorUid,
        'actorName': actorName,
        'actorRole': actorRole,
        'schoolId': schoolId,
        'schoolName': schoolName,
        'target': target,
        'details': details,
        'at': FieldValue.serverTimestamp(),
      };

  factory ActivityLog.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return ActivityLog(
      id: doc.id,
      action: ActivityAction.fromString(m['action'] as String?),
      actorUid: (m['actorUid'] ?? '') as String,
      actorName: (m['actorName'] ?? '') as String,
      actorRole: (m['actorRole'] ?? '') as String,
      schoolId: m['schoolId'] as String?,
      schoolName: (m['schoolName'] ?? '') as String,
      target: (m['target'] ?? '') as String,
      details: (m['details'] ?? '') as String,
      at: (m['at'] as Timestamp?)?.toDate(),
    );
  }
}

/// Who performed an action — supplied by [AuthController] so screens can log
/// without threading the user through every call.
class ActivityActor {
  const ActivityActor({
    required this.uid,
    this.name = '',
    this.role = '',
    this.schoolId,
    this.schoolName = '',
  });

  final String uid;
  final String name;
  final String role;
  final String? schoolId;
  final String schoolName;

  static ActivityActor forUser({
    required String uid,
    required String name,
    required bool superAdmin,
    UserRole? role,
    String? schoolId,
    String schoolName = '',
  }) =>
      ActivityActor(
        uid: uid,
        name: name,
        role: superAdmin ? 'superAdmin' : (role?.name ?? ''),
        schoolId: schoolId,
        schoolName: schoolName,
      );
}
