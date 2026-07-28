// Shared enums for the EduMate Pro domain. Each has a `fromString` that
// tolerates unknown/legacy values so old Firestore records never crash the app.

/// The three platform roles. Everyone signs in with the same phone-OTP flow;
/// the role on `users/{uid}` decides navigation and permissions.
enum UserRole {
  admin,
  teacher,
  parent;

  static UserRole fromString(String? s) {
    switch (s) {
      case 'admin':
        return UserRole.admin;
      case 'teacher':
        return UserRole.teacher;
      default:
        return UserRole.parent;
    }
  }

  String get label {
    switch (this) {
      case UserRole.admin:
        return 'School admin';
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.parent:
        return 'Parent';
    }
  }
}

/// Lifecycle of an enrollment application (applications/{id}).
enum ApplicationStatus {
  draft,
  submitted,
  underReview,
  accepted,
  rejected,
  enrolled;

  static ApplicationStatus fromString(String? s) {
    switch (s) {
      case 'submitted':
        return ApplicationStatus.submitted;
      case 'underReview':
        return ApplicationStatus.underReview;
      case 'accepted':
        return ApplicationStatus.accepted;
      case 'rejected':
        return ApplicationStatus.rejected;
      case 'enrolled':
        return ApplicationStatus.enrolled;
      default:
        return ApplicationStatus.draft;
    }
  }

  String get label {
    switch (this) {
      case ApplicationStatus.draft:
        return 'Draft';
      case ApplicationStatus.submitted:
        return 'Submitted';
      case ApplicationStatus.underReview:
        return 'Under review';
      case ApplicationStatus.accepted:
        return 'Accepted';
      case ApplicationStatus.rejected:
        return 'Rejected';
      case ApplicationStatus.enrolled:
        return 'Enrolled';
    }
  }

  bool get isFinal =>
      this == ApplicationStatus.rejected || this == ApplicationStatus.enrolled;
}

/// Lifecycle of a learner record. Applicants become active on enrollment.
enum LearnerStatus {
  applicant,
  active,
  inactive;

  static LearnerStatus fromString(String? s) {
    switch (s) {
      case 'active':
        return LearnerStatus.active;
      case 'inactive':
        return LearnerStatus.inactive;
      default:
        return LearnerStatus.applicant;
    }
  }

  String get label {
    switch (this) {
      case LearnerStatus.applicant:
        return 'Applicant';
      case LearnerStatus.active:
        return 'Enrolled';
      case LearnerStatus.inactive:
        return 'Inactive';
    }
  }
}

/// Review state of a parent-submitted payment (payments/{id}).
enum PaymentStatus {
  pending,
  approved,
  rejected;

  static PaymentStatus fromString(String? s) {
    switch (s) {
      case 'approved':
        return PaymentStatus.approved;
      case 'rejected':
        return PaymentStatus.rejected;
      default:
        return PaymentStatus.pending;
    }
  }

  String get label {
    switch (this) {
      case PaymentStatus.pending:
        return 'Pending review';
      case PaymentStatus.approved:
        return 'Approved';
      case PaymentStatus.rejected:
        return 'Rejected';
    }
  }
}

/// Kind of chat thread (chats/{id}).
enum ChatType {
  staff,
  parentTeacher;

  static ChatType fromString(String? s) =>
      s == 'parentTeacher' ? ChatType.parentTeacher : ChatType.staff;
}

/// Approval state of a chat thread. Staff chats are active immediately;
/// parent→teacher chats start as `requested` until an admin approves.
enum ChatApproval {
  requested,
  approved,
  declined;

  static ChatApproval fromString(String? s) {
    switch (s) {
      case 'approved':
        return ChatApproval.approved;
      case 'declined':
        return ChatApproval.declined;
      default:
        return ChatApproval.requested;
    }
  }

  String get label {
    switch (this) {
      case ChatApproval.requested:
        return 'Awaiting approval';
      case ChatApproval.approved:
        return 'Approved';
      case ChatApproval.declined:
        return 'Declined';
    }
  }
}

/// Destination of a broadcast message.
enum BroadcastScope {
  school,
  schoolClass,
  learner;

  static BroadcastScope fromString(String? s) {
    switch (s) {
      case 'schoolClass':
        return BroadcastScope.schoolClass;
      case 'learner':
        return BroadcastScope.learner;
      default:
        return BroadcastScope.school;
    }
  }

  String get label {
    switch (this) {
      case BroadcastScope.school:
        return 'Whole school';
      case BroadcastScope.schoolClass:
        return 'A class';
      case BroadcastScope.learner:
        return 'One learner';
    }
  }
}

/// Who a calendar event is for.
enum EventAudience {
  school,
  schoolClass,
  parents;

  static EventAudience fromString(String? s) {
    switch (s) {
      case 'schoolClass':
        return EventAudience.schoolClass;
      case 'parents':
        return EventAudience.parents;
      default:
        return EventAudience.school;
    }
  }

  String get label {
    switch (this) {
      case EventAudience.school:
        return 'Whole school';
      case EventAudience.schoolClass:
        return 'A class';
      case EventAudience.parents:
        return 'All parents';
    }
  }
}

/// Lifecycle of a staged bulk payment import (paymentImports/{id}).
enum ImportStatus {
  staged,
  approved,
  discarded;

  static ImportStatus fromString(String? s) {
    switch (s) {
      case 'approved':
        return ImportStatus.approved;
      case 'discarded':
        return ImportStatus.discarded;
      default:
        return ImportStatus.staged;
    }
  }

  String get label {
    switch (this) {
      case ImportStatus.staged:
        return 'Awaiting approval';
      case ImportStatus.approved:
        return 'Approved';
      case ImportStatus.discarded:
        return 'Discarded';
    }
  }
}

/// A QR attendance scan event: arriving at school or leaving it.
enum AttendanceType {
  checkIn,
  checkOut;

  static AttendanceType fromString(String? s) =>
      s == 'checkOut' ? AttendanceType.checkOut : AttendanceType.checkIn;

  /// Label for the resulting state ("where is the child now").
  String get stateLabel =>
      this == AttendanceType.checkIn ? 'In school' : 'Left school';

  /// Label for the action a staff member takes.
  String get actionLabel => this == AttendanceType.checkIn
      ? 'Mark as in school (present)'
      : 'Mark as left school';
}

/// Identity document types captured on the enrollment form.
enum IdType {
  saId,
  passport;

  static IdType? fromString(String? s) {
    switch (s) {
      case 'saId':
        return IdType.saId;
      case 'passport':
        return IdType.passport;
      default:
        return null;
    }
  }

  String get label => this == IdType.saId ? 'South African ID' : 'Passport';
}

/// Gender. For South African IDs this can be decoded from the ID number itself
/// (digits 7–10); otherwise it is captured manually.
enum Gender {
  female,
  male;

  static Gender? fromString(String? s) {
    switch (s) {
      case 'female':
        return Gender.female;
      case 'male':
        return Gender.male;
      default:
        return null;
    }
  }

  String get label => this == Gender.female ? 'Female' : 'Male';
}
