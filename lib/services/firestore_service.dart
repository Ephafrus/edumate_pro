import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../models/academics.dart';
import '../models/activity_log.dart';
import '../models/app_user.dart';
import '../models/application.dart';
import '../models/attendance.dart';
import '../models/broadcast.dart';
import '../models/calendar_event.dart';
import '../models/chat.dart';
import '../models/enums.dart';
import '../models/fees.dart';
import '../models/mail_settings.dart';
import '../models/payment.dart';
import '../models/school.dart';

/// All Cloud Firestore reads/writes for EduMate Pro, isolated from the UI.
/// Streams power the live lists; one-shot futures power mutations.
///
/// **Multi-school:** every school owns its data in subcollections of
/// `schools/{schoolId}`, so schools are fully isolated. [activeSchoolId] is
/// the school the signed-in user is currently working in (set by
/// `AuthController`, switched from the app bar); all school-scoped helpers
/// go through [_col], so a user only ever reads the school they are in.
/// Users, schools and staff invites are global.
class FirestoreService {
  FirestoreService([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Sentinel used before a school is chosen — reads resolve to an empty,
  /// non-existent school rather than crashing or leaking data.
  static const _noSchool = '__none__';

  String? activeSchoolId;

  DocumentReference<Map<String, dynamic>> get _schoolDoc =>
      _db.collection(Collections.schools).doc(activeSchoolId ?? _noSchool);

  /// A collection inside the active school.
  CollectionReference<Map<String, dynamic>> _col(String name) =>
      _schoolDoc.collection(name);

  // ---- First-run bootstrap -------------------------------------------------

  /// Claims the platform for the very first user, atomically.
  ///
  /// A brand-new deployment has no Super Admin and no schools, which would
  /// otherwise leave the first person to sign in stuck on "choose a school"
  /// with an empty list. The first user to get here creates
  /// `platform/config`; because a `create` fails if the document already
  /// exists, exactly one user can ever win this race, and they become the
  /// platform's first Super Admin.
  ///
  /// Returns true if this call claimed it.
  Future<bool> claimPlatformBootstrap(String uid) async {
    final ref = _db.collection(Collections.platform).doc('config');
    try {
      final existing = await ref.get();
      if (existing.exists) {
        // Idempotent: if a previous attempt created the claim but did not
        // finish promoting the account, let this caller carry on.
        return (existing.data() ?? const {})['firstSuperAdminUid'] == uid;
      }
    } catch (_) {
      // Unreadable — fall through and let the write decide.
    }
    try {
      await ref.set({
        'bootstrapped': true,
        'firstSuperAdminUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether the platform already has an owner.
  Future<bool> isPlatformBootstrapped() async {
    try {
      final doc =
          await _db.collection(Collections.platform).doc('config').get();
      return doc.exists;
    } catch (_) {
      // Rules deny reads to non-super-admins; assume claimed.
      return true;
    }
  }

  // ---- Activity log --------------------------------------------------------

  /// Appends one audit-trail entry. Never throws for the caller's benefit —
  /// [ActivityService] handles failures.
  Future<void> writeActivityLog(ActivityLog entry) async {
    await _db.collection(Collections.activityLogs).add(entry.toMap());
  }

  /// The Super Admin's activity feed, newest first.
  Stream<List<ActivityLog>> watchActivityLogs({int limit = 300}) => _db
      .collection(Collections.activityLogs)
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(ActivityLog.fromDoc).toList());

  // ---- Schools -------------------------------------------------------------

  /// Every school on the platform — the Super Admin console, and the list a
  /// parent picks from when joining a school.
  Stream<List<School>> watchSchools() =>
      _db.collection(Collections.schools).snapshots().map(
            (s) => s.docs.map(School.fromDoc).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
          );

  Future<School?> getSchool(String id) async {
    final doc = await _db.collection(Collections.schools).doc(id).get();
    return doc.exists ? School.fromDoc(doc) : null;
  }

  /// Super Admin sets a new school up; returns its id.
  Future<String> createSchool(School school) async {
    final ref =
        await _db.collection(Collections.schools).add(school.toMap());
    return ref.id;
  }

  Future<void> updateSchool(String id, Map<String, dynamic> data) =>
      _db.collection(Collections.schools).doc(id).update(data);

  // ---- School membership ---------------------------------------------------

  CollectionReference<Map<String, dynamic>> _members(String schoolId) => _db
      .collection(Collections.schools)
      .doc(schoolId)
      .collection(Collections.members);

  /// **All** schools this person belongs to, with their role at each. One
  /// collection-group query, so an admin, principal or teacher assigned to
  /// several schools sees every one of them and can switch between them.
  Stream<List<SchoolMembership>> watchMembershipsForUser(String uid) => _db
      .collectionGroup(Collections.members)
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((s) => s.docs.map(SchoolMembership.fromDoc).toList()
        ..sort((a, b) => a.schoolName.compareTo(b.schoolName)));

  Future<List<SchoolMembership>> getMembershipsForUser(String uid) async {
    final snap = await _db
        .collectionGroup(Collections.members)
        .where('uid', isEqualTo: uid)
        .get();
    return snap.docs.map(SchoolMembership.fromDoc).toList()
      ..sort((a, b) => a.schoolName.compareTo(b.schoolName));
  }

  /// Everybody at the **active** school (staff and parents).
  Stream<List<SchoolMembership>> watchSchoolMembers({List<UserRole>? roles}) =>
      watchMembers(activeSchoolId ?? _noSchool, roles: roles);

  /// The people at a school, optionally filtered by role.
  Stream<List<SchoolMembership>> watchMembers(String schoolId,
          {List<UserRole>? roles}) =>
      _members(schoolId).snapshots().map((s) => s.docs
          .map(SchoolMembership.fromDoc)
          .where((m) => roles == null || roles.contains(m.role))
          .toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName)));

  /// Adds (or updates) somebody's membership of a school.
  Future<void> setMembership(SchoolMembership member) =>
      _members(member.schoolId)
          .doc(member.uid)
          .set(member.toMap(), SetOptions(merge: true));

  Future<void> setMemberActive(String schoolId, String uid, bool active) =>
      _members(schoolId).doc(uid).update({'active': active});

  Future<void> removeMembership(String schoolId, String uid) =>
      _members(schoolId).doc(uid).delete();

  // ---- Users ---------------------------------------------------------------

  Future<AppUser?> getUser(String uid) async {
    final doc = await _db.collection(Collections.users).doc(uid).get();
    return doc.exists ? AppUser.fromDoc(doc) : null;
  }

  Future<void> upsertUser(AppUser user) => _db
      .collection(Collections.users)
      .doc(user.uid)
      .set(user.toMap(), SetOptions(merge: true));

  Future<void> updateUser(String uid, Map<String, dynamic> data) =>
      _db.collection(Collections.users).doc(uid).update(data);

  /// Every account on the platform — the Super Admin's user directory.
  Stream<List<AppUser>> watchAllUsers() => _db
      .collection(Collections.users)
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList()
        ..sort((a, b) => a.fullName.toLowerCase()
            .compareTo(b.fullName.toLowerCase())));

  /// Grants or revokes platform Super Admin.
  Future<void> setSuperAdmin(String uid, bool value) =>
      updateUser(uid, {'superAdmin': value});

  /// Looks a person up by phone number so a Super Admin / school admin can
  /// assign somebody who already has an account.
  Future<AppUser?> findUserByPhone(String phoneE164) async {
    final snap = await _db
        .collection(Collections.users)
        .where('phone', isEqualTo: phoneE164)
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : AppUser.fromDoc(snap.docs.first);
  }

  /// The active school's directory, filtered by role — drives the chat
  /// pickers, broadcast recipients and parent linking.
  Stream<List<AppUser>> watchUsersByRole(UserRole role) =>
      watchMembers(activeSchoolId ?? _noSchool, roles: [role])
          .map((ms) => ms.map((m) => m.toAppUser()).toList());

  /// Staff directory (admins, principals + teachers) for the staff chat
  /// picker, scoped to the active school.
  Stream<List<AppUser>> watchStaff() => watchMembers(
        activeSchoolId ?? _noSchool,
        roles: const [UserRole.admin, UserRole.principal, UserRole.teacher],
      ).map((ms) => ms.map((m) => m.toAppUser()).toList());

  // ---- Staff invites -------------------------------------------------------
  // Global collection keyed by phone number **and school**, so one person
  // can be invited to several schools and picks up every membership on
  // their next sign-in.

  Future<void> createStaffInvite(StaffInvite invite) async {
    await _db.collection(Collections.staffInvites).add(invite.toMap());
  }

  /// Unclaimed invites for a phone number, across all schools.
  Future<List<StaffInvite>> getStaffInvitesForPhone(String phoneE164) async {
    final snap = await _db
        .collection(Collections.staffInvites)
        .where('phone', isEqualTo: phoneE164)
        .get();
    return snap.docs
        .map(StaffInvite.fromDoc)
        .where((i) => !i.claimed)
        .toList();
  }

  Future<void> markInviteClaimed(String inviteId, String uid) => _db
      .collection(Collections.staffInvites)
      .doc(inviteId)
      .update({'claimedByUid': uid});

  Future<void> deleteStaffInvite(String inviteId) =>
      _db.collection(Collections.staffInvites).doc(inviteId).delete();

  /// Pending invites for one school (admin's Staff screen).
  Stream<List<StaffInvite>> watchStaffInvites(String schoolId) => _db
      .collection(Collections.staffInvites)
      .where('schoolId', isEqualTo: schoolId)
      .snapshots()
      .map((s) => s.docs.map(StaffInvite.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0))));

  // ---- Classes -------------------------------------------------------------

  Stream<List<SchoolClass>> watchClasses() =>
      _col(Collections.classes).snapshots().map(
            (s) => s.docs.map(SchoolClass.fromDoc).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
          );

  Stream<List<SchoolClass>> watchClassesForTeacher(String teacherUid) => _col(Collections.classes)
      .where('teacherUid', isEqualTo: teacherUid)
      .snapshots()
      .map((s) => s.docs.map(SchoolClass.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

  Future<void> createClass(SchoolClass c) =>
      _col(Collections.classes).add(c.toMap()).then((_) {});

  Future<void> updateClass(String id, Map<String, dynamic> data) =>
      _col(Collections.classes).doc(id).update(data);

  Future<void> deleteClass(String id) =>
      _col(Collections.classes).doc(id).delete();

  // ---- Learners ------------------------------------------------------------

  Stream<List<Learner>> watchLearners() =>
      _col(Collections.learners).snapshots().map(
            (s) => s.docs.map(Learner.fromDoc).toList()
              ..sort((a, b) => a.fullName.compareTo(b.fullName)),
          );

  Stream<List<Learner>> watchLearnersInClass(String classId) => _col(Collections.learners)
      .where('classId', isEqualTo: classId)
      .snapshots()
      .map((s) => s.docs.map(Learner.fromDoc).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName)));

  /// The children linked to a parent account — drives the parent dashboard.
  Stream<List<Learner>> watchLearnersForParent(String parentUid) => _col(Collections.learners)
      .where('parentUids', arrayContains: parentUid)
      .snapshots()
      .map((s) => s.docs.map(Learner.fromDoc).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName)));

  Future<Learner?> getLearner(String id) async {
    final doc = await _col(Collections.learners).doc(id).get();
    return doc.exists ? Learner.fromDoc(doc) : null;
  }

  Future<String> createLearner(Learner l) async {
    final ref = await _col(Collections.learners).add(l.toMap());
    return ref.id;
  }

  Future<void> updateLearner(String id, Map<String, dynamic> data) =>
      _col(Collections.learners).doc(id).update(data);

  Future<void> deleteLearner(String id) =>
      _col(Collections.learners).doc(id).delete();

  /// Assign (or unassign, with null) a learner to a class. Stores the class
  /// name too so lists render without a join.
  Future<void> assignLearnerToClass(
          String learnerId, String? classId, String className) =>
      updateLearner(learnerId, {'classId': classId, 'className': className});

  /// Link/unlink a parent account to a learner.
  Future<void> setParentLink(String learnerId, String parentUid,
          {required bool linked}) =>
      updateLearner(learnerId, {
        'parentUids': linked
            ? FieldValue.arrayUnion([parentUid])
            : FieldValue.arrayRemove([parentUid]),
      });

  // ---- QR attendance -------------------------------------------------------

  /// Records a QR attendance scan: creates the attendance event and stamps
  /// the learner's live status, atomically. The `onAttendanceScan` Cloud
  /// Function emails the linked parents.
  Future<void> recordAttendance(
    Learner learner,
    AttendanceType type, {
    required AppUser by,
  }) {
    final eventRef = _col(Collections.attendance).doc();
    final learnerRef =
        _col(Collections.learners).doc(learner.id);
    final record = AttendanceRecord(
      id: eventRef.id,
      learnerId: learner.id,
      type: type,
      learnerName: learner.fullName,
      className: learner.className,
      byUid: by.uid,
      byName: by.fullName,
      parentUids: learner.parentUids,
    );

    final batch = _db.batch();
    batch.set(eventRef, record.toMap());
    batch.update(learnerRef, {
      'attendanceStatus': type.name,
      'lastAttendanceAt': FieldValue.serverTimestamp(),
    });
    return batch.commit();
  }

  /// A learner's scan history, newest first (parents see their own children;
  /// staff see all).
  Stream<List<AttendanceRecord>> watchAttendanceForLearner(String learnerId,
          {int limit = 20}) =>
      _col(Collections.attendance)
          .where('learnerId', isEqualTo: learnerId)
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(AttendanceRecord.fromDoc).toList());

  // ---- Subjects ------------------------------------------------------------

  Stream<List<Subject>> watchSubjects() =>
      _col(Collections.subjects).snapshots().map(
            (s) => s.docs.map(Subject.fromDoc).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
          );

  Stream<List<Subject>> watchSubjectsForClass(String classId) => _col(
          Collections.subjects)
      .where('classId', isEqualTo: classId)
      .snapshots()
      .map((s) => s.docs.map(Subject.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

  /// The subjects a teacher teaches — their capture list.
  Stream<List<Subject>> watchSubjectsForTeacher(String teacherUid) => _col(
          Collections.subjects)
      .where('teacherUid', isEqualTo: teacherUid)
      .snapshots()
      .map((s) => s.docs.map(Subject.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

  Future<void> createSubject(Subject s) =>
      _col(Collections.subjects).add(s.toMap()).then((_) {});

  Future<void> updateSubject(String id, Map<String, dynamic> data) =>
      _col(Collections.subjects).doc(id).update(data);

  Future<void> deleteSubject(String id) =>
      _col(Collections.subjects).doc(id).delete();

  // ---- Assessments & marks -------------------------------------------------

  Stream<List<Assessment>> watchAssessmentsForSubject(String subjectId) =>
      _col(Collections.assessments)
          .where('subjectId', isEqualTo: subjectId)
          .snapshots()
          .map((s) => s.docs.map(Assessment.fromDoc).toList()
            ..sort((a, b) => (b.date ?? DateTime(0))
                .compareTo(a.date ?? DateTime(0))));

  Future<String> createAssessment(Assessment a) async {
    final ref = await _col(Collections.assessments).add(a.toMap());
    return ref.id;
  }

  Future<void> deleteAssessment(String id) =>
      _col(Collections.assessments).doc(id).delete();

  Stream<List<Mark>> watchMarksForAssessment(String assessmentId) =>
      _col(Collections.marks)
          .where('assessmentId', isEqualTo: assessmentId)
          .snapshots()
          .map((s) => s.docs.map(Mark.fromDoc).toList()
            ..sort((a, b) => a.learnerName.compareTo(b.learnerName)));

  /// Every mark for one learner — the progress report and the parent's
  /// child-progress dashboard.
  Stream<List<Mark>> watchMarksForLearner(String learnerId) =>
      _col(Collections.marks)
          .where('learnerId', isEqualTo: learnerId)
          .snapshots()
          .map((s) => s.docs.map(Mark.fromDoc).toList()
            ..sort((a, b) => (b.date ?? DateTime(0))
                .compareTo(a.date ?? DateTime(0))));

  Stream<List<Mark>> watchMarksForClass(String classId) =>
      _col(Collections.marks)
          .where('classId', isEqualTo: classId)
          .snapshots()
          .map((s) => s.docs.map(Mark.fromDoc).toList());

  /// Saves a whole mark sheet in one batch — one document per learner,
  /// keyed `{assessmentId}_{learnerId}` so re-capturing overwrites cleanly.
  Future<void> saveMarks(List<Mark> marks) async {
    final batch = _db.batch();
    for (final m in marks) {
      final ref = _col(Collections.marks)
          .doc('${m.assessmentId}_${m.learnerId}');
      batch.set(ref, m.toMap(), SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// Groups a learner's marks by subject for progress reporting.
  static List<SubjectProgress> progressBySubject(List<Mark> marks) {
    final bySubject = <String, List<Mark>>{};
    for (final m in marks) {
      bySubject.putIfAbsent(m.subjectId, () => []).add(m);
    }
    final out = bySubject.entries
        .map((e) => SubjectProgress(
              subjectId: e.key,
              subjectName: e.value.first.subjectName,
              marks: e.value,
            ))
        .toList()
      ..sort((a, b) => a.subjectName.compareTo(b.subjectName));
    return out;
  }

  // ---- Lesson plans & homework ---------------------------------------------

  Stream<List<LessonPlan>> watchLessonPlansForClass(String classId) =>
      _col(Collections.lessonPlans)
          .where('classId', isEqualTo: classId)
          .snapshots()
          .map((s) => s.docs.map(LessonPlan.fromDoc).toList()
            ..sort((a, b) => b.date.compareTo(a.date)));

  Stream<List<LessonPlan>> watchLessonPlansForTeacher(String teacherUid) =>
      _col(Collections.lessonPlans)
          .where('teacherUid', isEqualTo: teacherUid)
          .snapshots()
          .map((s) => s.docs.map(LessonPlan.fromDoc).toList()
            ..sort((a, b) => b.date.compareTo(a.date)));

  Future<void> createLessonPlan(LessonPlan p) =>
      _col(Collections.lessonPlans).add(p.toMap()).then((_) {});

  Future<void> deleteLessonPlan(String id) =>
      _col(Collections.lessonPlans).doc(id).delete();

  Stream<List<Homework>> watchHomeworkForClass(String classId) =>
      _col(Collections.homework)
          .where('classId', isEqualTo: classId)
          .snapshots()
          .map((s) => s.docs.map(Homework.fromDoc).toList()
            ..sort((a, b) => b.dueDate.compareTo(a.dueDate)));

  Stream<List<Homework>> watchHomeworkForTeacher(String teacherUid) =>
      _col(Collections.homework)
          .where('teacherUid', isEqualTo: teacherUid)
          .snapshots()
          .map((s) => s.docs.map(Homework.fromDoc).toList()
            ..sort((a, b) => b.dueDate.compareTo(a.dueDate)));

  Future<void> createHomework(Homework h) =>
      _col(Collections.homework).add(h.toMap()).then((_) {});

  Future<void> deleteHomework(String id) =>
      _col(Collections.homework).doc(id).delete();

  // ---- Enrollment applications --------------------------------------------

  Future<String> createApplication(EnrollmentApplication app) async {
    final ref =
        await _col(Collections.applications).add(app.toMap());
    return ref.id;
  }

  /// Creates a new draft from raw wizard field data (the wizard saves after
  /// every step, so partial data is expected).
  Future<String> createDraftApplication(
      String parentUid, Map<String, dynamic> data) async {
    final ref = await _col(Collections.applications).add({
      ...data,
      'parentUid': parentUid,
      'status': ApplicationStatus.draft.name,
      'events': const [],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateApplication(String id, Map<String, dynamic> data) => _col(Collections.applications)
      .doc(id)
      .update({...data, 'updatedAt': FieldValue.serverTimestamp()});

  Stream<EnrollmentApplication?> watchApplication(String id) => _col(Collections.applications)
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? EnrollmentApplication.fromDoc(d) : null);

  Stream<List<EnrollmentApplication>> watchApplicationsForParent(
          String parentUid) =>
      _col(Collections.applications)
          .where('parentUid', isEqualTo: parentUid)
          .snapshots()
          .map((s) => s.docs.map(EnrollmentApplication.fromDoc).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0))
                .compareTo(a.createdAt ?? DateTime(0))));

  /// All applications for the admin review queue (client-side filtered).
  Stream<List<EnrollmentApplication>> watchApplications() => _col(Collections.applications)
      .snapshots()
      .map((s) => s.docs.map(EnrollmentApplication.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0))));

  /// Moves an application to a new status, appending a tracking event. The
  /// Cloud Function watches this change and emails the guardian.
  Future<void> setApplicationStatus(
    EnrollmentApplication app,
    ApplicationStatus status, {
    String note = '',
    String byName = '',
  }) {
    final event = ApplicationEvent(status: status, note: note, byName: byName);
    return updateApplication(app.id, {
      'status': status.name,
      if (status == ApplicationStatus.submitted)
        'submittedAt': FieldValue.serverTimestamp(),
      if (status == ApplicationStatus.rejected) 'rejectionReason': note,
      'events': FieldValue.arrayUnion([event.toMap()]),
    });
  }

  /// Enrolls an accepted application: creates the learner record, links the
  /// applying parent, and marks the application enrolled — atomically.
  Future<String> enrollApplication(EnrollmentApplication app,
      {String byName = ''}) async {
    final learnerRef = _col(Collections.learners).doc();
    final appRef = _col(Collections.applications).doc(app.id);
    final event = ApplicationEvent(
        status: ApplicationStatus.enrolled,
        note: 'Learner record created',
        byName: byName);

    final learner = Learner(
      id: learnerRef.id,
      firstName: app.learnerFirstName,
      lastName: app.learnerLastName,
      grade: app.gradeApplyingFor,
      dateOfBirth: app.learnerDob,
      gender: app.learnerGender,
      idNumber: app.learnerIdNumber,
      status: LearnerStatus.active,
      parentUids: [app.parentUid],
      applicationId: app.id,
    );

    final batch = _db.batch();
    batch.set(learnerRef, learner.toMap());
    batch.update(appRef, {
      'status': ApplicationStatus.enrolled.name,
      'learnerId': learnerRef.id,
      'events': FieldValue.arrayUnion([event.toMap()]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return learnerRef.id;
  }

  // ---- Payments ------------------------------------------------------------

  Future<void> createPayment(PaymentRecord p) =>
      _col(Collections.payments).add(p.toMap()).then((_) {});

  Stream<List<PaymentRecord>> watchPaymentsForParent(String parentUid) => _col(Collections.payments)
      .where('parentUid', isEqualTo: parentUid)
      .snapshots()
      .map((s) => s.docs.map(PaymentRecord.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0))));

  Stream<List<PaymentRecord>> watchPayments() => _col(Collections.payments)
      .snapshots()
      .map((s) => s.docs.map(PaymentRecord.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0))));

  /// Approve/reject a submitted payment. The Cloud Function watches this
  /// change and emails the parent.
  Future<void> reviewPayment(
    String paymentId,
    PaymentStatus status, {
    String note = '',
    String byName = '',
  }) =>
      _col(Collections.payments).doc(paymentId).update({
        'status': status.name,
        'reviewNote': note,
        'reviewedByName': byName,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

  // ---- Chat ----------------------------------------------------------------

  Stream<List<ChatThread>> watchChatsForUser(String uid) => _col(Collections.chats)
      .where('participantUids', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.map(ChatThread.fromDoc).toList()
        ..sort((a, b) => (b.updatedAt ?? DateTime(0))
            .compareTo(a.updatedAt ?? DateTime(0))));

  /// Parent→teacher chat requests awaiting admin approval.
  Stream<List<ChatThread>> watchPendingChatRequests() => _col(Collections.chats)
      .where('approval', isEqualTo: ChatApproval.requested.name)
      .snapshots()
      .map((s) => s.docs.map(ChatThread.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0))));

  /// Opens (or reuses) a staff chat between two staff members.
  Future<String> openStaffChat(AppUser me, AppUser other) async {
    final existing = await _col(Collections.chats)
        .where('participantUids', arrayContains: me.uid)
        .where('type', isEqualTo: ChatType.staff.name)
        .get();
    for (final doc in existing.docs) {
      final t = ChatThread.fromDoc(doc);
      if (t.participantUids.contains(other.uid)) return t.id;
    }
    final thread = ChatThread(
      id: '',
      type: ChatType.staff,
      participantUids: [me.uid, other.uid],
      participantNames: {me.uid: me.fullName, other.uid: other.fullName},
      approval: ChatApproval.approved,
    );
    final ref = await _col(Collections.chats).add(thread.toMap());
    return ref.id;
  }

  /// Parent requests a chat with a teacher; created as `requested` and only
  /// becomes usable once an admin approves it.
  Future<String> requestParentTeacherChat({
    required AppUser parent,
    required AppUser teacher,
    String reason = '',
    String learnerName = '',
  }) async {
    final existing = await _col(Collections.chats)
        .where('participantUids', arrayContains: parent.uid)
        .where('type', isEqualTo: ChatType.parentTeacher.name)
        .get();
    for (final doc in existing.docs) {
      final t = ChatThread.fromDoc(doc);
      if (t.participantUids.contains(teacher.uid) &&
          t.approval != ChatApproval.declined) {
        return t.id;
      }
    }
    final thread = ChatThread(
      id: '',
      type: ChatType.parentTeacher,
      participantUids: [parent.uid, teacher.uid],
      participantNames: {
        parent.uid: parent.fullName,
        teacher.uid: teacher.fullName,
      },
      approval: ChatApproval.requested,
      requestReason: reason,
      learnerName: learnerName,
    );
    final ref = await _col(Collections.chats).add(thread.toMap());
    return ref.id;
  }

  Future<void> setChatApproval(String chatId, ChatApproval approval) =>
      _col(Collections.chats).doc(chatId).update({
        'approval': approval.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Stream<ChatThread?> watchChat(String chatId) => _col(Collections.chats)
      .doc(chatId)
      .snapshots()
      .map((d) => d.exists ? ChatThread.fromDoc(d) : null);

  Stream<List<ChatMessage>> watchMessages(String chatId) => _col(Collections.chats)
      .doc(chatId)
      .collection('messages')
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  Future<void> sendMessage(String chatId, ChatMessage msg) async {
    final chatRef = _col(Collections.chats).doc(chatId);
    await chatRef.collection('messages').add(msg.toMap());
    await chatRef.update({
      'lastMessage': msg.text,
      'lastSenderUid': msg.senderUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- SMTP settings & outgoing email -------------------------------------

  MailSettings? _cachedMailSettings;

  /// The school's SMTP settings (settings/smtp), cached per session.
  Future<MailSettings?> getMailSettings({bool refresh = false}) async {
    if (!refresh && _cachedMailSettings != null) return _cachedMailSettings;
    final doc =
        await _col(Collections.settings).doc('smtp').get();
    _cachedMailSettings = doc.exists ? MailSettings.fromDoc(doc) : null;
    return _cachedMailSettings;
  }

  Future<void> setMailSettings(MailSettings settings) async {
    await _col(Collections.settings)
        .doc('smtp')
        .set(settings.toMap(), SetOptions(merge: true));
    _cachedMailSettings = settings;
  }

  /// Records an outgoing email in the audit trail / outbox.
  Future<void> logMail({
    required String to,
    required String subject,
    required String text,
    String? html,
    required String status,
    String error = '',
  }) =>
      _col(Collections.mailQueue).add({
        'to': to,
        'subject': subject,
        'text': text,
        'html': html,
        'status': status,
        'error': error,
        'createdAt': FieldValue.serverTimestamp(),
      });

  /// Outbox messages still to be sent (queued from web / before SMTP was
  /// configured / failed attempts).
  Future<List<QueuedMail>> getUnsentMail({int limit = 25}) async {
    final snap = await _col(Collections.mailQueue)
        .where('status', whereIn: ['pending', 'error'])
        .limit(limit)
        .get();
    return snap.docs.map(QueuedMail.fromDoc).toList();
  }

  Future<void> markMail(String id, String status, {String error = ''}) =>
      _col(Collections.mailQueue).doc(id).update({
        'status': status,
        'error': error,
        if (status == 'sent') 'sentAt': FieldValue.serverTimestamp(),
      });

  /// Live count of unsent outbox messages, for the Email settings screen.
  Stream<int> watchOutboxCount() => _col(Collections.mailQueue)
      .where('status', whereIn: ['pending', 'error'])
      .snapshots()
      .map((s) => s.docs.length);

  // ---- Broadcast messages --------------------------------------------------

  Future<String> createBroadcast(Broadcast b) async {
    final ref = await _col(Collections.broadcasts).add(b.toMap());
    return ref.id;
  }

  Future<void> updateBroadcast(String id, Map<String, dynamic> data) =>
      _col(Collections.broadcasts).doc(id).update(data);

  /// All broadcasts, newest first (admin history).
  Stream<List<Broadcast>> watchBroadcasts() => _col(Collections.broadcasts)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(Broadcast.fromDoc).toList());

  /// Broadcasts addressed to this parent, newest first (announcements feed
  /// + the notification bell).
  Stream<List<Broadcast>> watchBroadcastsForUser(String uid,
          {int limit = 50}) =>
      _col(Collections.broadcasts)
          .where('recipientUids', arrayContains: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(Broadcast.fromDoc).toList());

  /// Marks the user's announcements as seen (clears the bell badge).
  Future<void> markBroadcastsSeen(String uid) =>
      updateUser(uid, {'broadcastsSeenAt': FieldValue.serverTimestamp()});

  // ---- Calendar events -----------------------------------------------------

  Stream<List<CalendarEvent>> watchEvents() => _col(Collections.events)
      .orderBy('start')
      .snapshots()
      .map((s) => s.docs.map(CalendarEvent.fromDoc).toList());

  Future<void> createEvent(CalendarEvent e) =>
      _col(Collections.events).add(e.toMap()).then((_) {});

  Future<void> deleteEvent(String id) =>
      _col(Collections.events).doc(id).delete();

  // ---- Fees ----------------------------------------------------------------

  Stream<List<FeeStructure>> watchFeeStructures() =>
      _col(Collections.feeStructures).snapshots().map(
            (s) => s.docs.map(FeeStructure.fromDoc).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
          );

  Future<void> createFeeStructure(FeeStructure f) =>
      _col(Collections.feeStructures).add(f.toMap()).then((_) {});

  Future<void> updateFeeStructure(String id, Map<String, dynamic> data) =>
      _col(Collections.feeStructures).doc(id).update(data);

  Future<void> deleteFeeStructure(String id) =>
      _col(Collections.feeStructures).doc(id).delete();

  /// Admin records a fee payment at the office — created pre-approved.
  Future<void> recordAdminPayment(PaymentRecord p) => createPayment(p);

  // ---- Bulk payment imports (staged CSV uploads) ---------------------------

  Future<String> createPaymentImport(PaymentImport imp) async {
    final ref =
        await _col(Collections.paymentImports).add(imp.toMap());
    return ref.id;
  }

  Stream<List<PaymentImport>> watchPaymentImports() => _col(Collections.paymentImports)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(PaymentImport.fromDoc).toList());

  Future<void> discardPaymentImport(String id) =>
      _col(Collections.paymentImports).doc(id).update({
        'status': ImportStatus.discarded.name,
        'resolvedAt': FieldValue.serverTimestamp(),
      });

  /// Approves a staged import: creates an approved payment record for every
  /// valid row (batched), then marks the import approved. Returns the number
  /// of payments created.
  Future<int> approvePaymentImport(
    PaymentImport imp, {
    required String byName,
    required Map<String, Learner> learnersById,
  }) async {
    final valid = imp.rows.where((r) => r.valid).toList();
    var created = 0;
    // Firestore batches cap at 500 writes; keep headroom.
    for (var i = 0; i < valid.length; i += 400) {
      final batch = _db.batch();
      for (final row in valid.skip(i).take(400)) {
        final learner = learnersById[row.learnerId];
        final ref = _col(Collections.payments).doc();
        batch.set(
            ref,
            PaymentRecord(
              id: ref.id,
              parentUid: learner?.parentUids.firstOrNull ?? '',
              learnerId: row.learnerId,
              learnerName: row.learnerName,
              purpose: row.purpose,
              method: row.method,
              amountCents: row.amountCents,
              reference: row.reference,
              paymentDate: row.date,
              notes: 'Bulk import: ${imp.filename}',
              status: PaymentStatus.approved,
              reviewedByName: byName,
              reviewedAt: DateTime.now(),
              source: 'import',
            ).toMap());
        created++;
      }
      await batch.commit();
    }
    await _col(Collections.paymentImports).doc(imp.id).update({
      'status': ImportStatus.approved.name,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
    return created;
  }
}
