import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../models/app_user.dart';
import '../models/application.dart';
import '../models/chat.dart';
import '../models/enums.dart';
import '../models/payment.dart';
import '../models/school.dart';

/// All Cloud Firestore reads/writes for EduMate Pro, isolated from the UI.
/// Streams power the live lists; one-shot futures power mutations.
class FirestoreService {
  FirestoreService([FirebaseFirestore? db])
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

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

  Stream<List<AppUser>> watchUsersByRole(UserRole role) => _db
      .collection(Collections.users)
      .where('role', isEqualTo: role.name)
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName)));

  /// Staff directory (admins + teachers) for the staff chat picker.
  Stream<List<AppUser>> watchStaff() => _db
      .collection(Collections.users)
      .where('role', whereIn: [UserRole.admin.name, UserRole.teacher.name])
      .snapshots()
      .map((s) => s.docs.map(AppUser.fromDoc).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName)));

  // ---- Staff invites -------------------------------------------------------

  /// Admin pre-provisions a staff account against a phone number. The doc id
  /// is the E.164 number so first sign-in can look it up directly.
  Future<void> createStaffInvite(StaffInvite invite) => _db
      .collection(Collections.staffInvites)
      .doc(invite.phone)
      .set(invite.toMap());

  Future<StaffInvite?> getStaffInvite(String phoneE164) async {
    final doc =
        await _db.collection(Collections.staffInvites).doc(phoneE164).get();
    return doc.exists ? StaffInvite.fromDoc(doc) : null;
  }

  Future<void> markInviteClaimed(String phoneE164, String uid) => _db
      .collection(Collections.staffInvites)
      .doc(phoneE164)
      .update({'claimedByUid': uid});

  Future<void> deleteStaffInvite(String phoneE164) =>
      _db.collection(Collections.staffInvites).doc(phoneE164).delete();

  Stream<List<StaffInvite>> watchStaffInvites() => _db
      .collection(Collections.staffInvites)
      .snapshots()
      .map((s) => s.docs.map(StaffInvite.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0))));

  // ---- Classes -------------------------------------------------------------

  Stream<List<SchoolClass>> watchClasses() =>
      _db.collection(Collections.classes).snapshots().map(
            (s) => s.docs.map(SchoolClass.fromDoc).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
          );

  Stream<List<SchoolClass>> watchClassesForTeacher(String teacherUid) => _db
      .collection(Collections.classes)
      .where('teacherUid', isEqualTo: teacherUid)
      .snapshots()
      .map((s) => s.docs.map(SchoolClass.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

  Future<void> createClass(SchoolClass c) =>
      _db.collection(Collections.classes).add(c.toMap()).then((_) {});

  Future<void> updateClass(String id, Map<String, dynamic> data) =>
      _db.collection(Collections.classes).doc(id).update(data);

  Future<void> deleteClass(String id) =>
      _db.collection(Collections.classes).doc(id).delete();

  // ---- Learners ------------------------------------------------------------

  Stream<List<Learner>> watchLearners() =>
      _db.collection(Collections.learners).snapshots().map(
            (s) => s.docs.map(Learner.fromDoc).toList()
              ..sort((a, b) => a.fullName.compareTo(b.fullName)),
          );

  Stream<List<Learner>> watchLearnersInClass(String classId) => _db
      .collection(Collections.learners)
      .where('classId', isEqualTo: classId)
      .snapshots()
      .map((s) => s.docs.map(Learner.fromDoc).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName)));

  /// The children linked to a parent account — drives the parent dashboard.
  Stream<List<Learner>> watchLearnersForParent(String parentUid) => _db
      .collection(Collections.learners)
      .where('parentUids', arrayContains: parentUid)
      .snapshots()
      .map((s) => s.docs.map(Learner.fromDoc).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName)));

  Future<String> createLearner(Learner l) async {
    final ref = await _db.collection(Collections.learners).add(l.toMap());
    return ref.id;
  }

  Future<void> updateLearner(String id, Map<String, dynamic> data) =>
      _db.collection(Collections.learners).doc(id).update(data);

  Future<void> deleteLearner(String id) =>
      _db.collection(Collections.learners).doc(id).delete();

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

  // ---- Enrollment applications --------------------------------------------

  Future<String> createApplication(EnrollmentApplication app) async {
    final ref =
        await _db.collection(Collections.applications).add(app.toMap());
    return ref.id;
  }

  /// Creates a new draft from raw wizard field data (the wizard saves after
  /// every step, so partial data is expected).
  Future<String> createDraftApplication(
      String parentUid, Map<String, dynamic> data) async {
    final ref = await _db.collection(Collections.applications).add({
      ...data,
      'parentUid': parentUid,
      'status': ApplicationStatus.draft.name,
      'events': const [],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateApplication(String id, Map<String, dynamic> data) => _db
      .collection(Collections.applications)
      .doc(id)
      .update({...data, 'updatedAt': FieldValue.serverTimestamp()});

  Stream<EnrollmentApplication?> watchApplication(String id) => _db
      .collection(Collections.applications)
      .doc(id)
      .snapshots()
      .map((d) => d.exists ? EnrollmentApplication.fromDoc(d) : null);

  Stream<List<EnrollmentApplication>> watchApplicationsForParent(
          String parentUid) =>
      _db
          .collection(Collections.applications)
          .where('parentUid', isEqualTo: parentUid)
          .snapshots()
          .map((s) => s.docs.map(EnrollmentApplication.fromDoc).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(0))
                .compareTo(a.createdAt ?? DateTime(0))));

  /// All applications for the admin review queue (client-side filtered).
  Stream<List<EnrollmentApplication>> watchApplications() => _db
      .collection(Collections.applications)
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
    final learnerRef = _db.collection(Collections.learners).doc();
    final appRef = _db.collection(Collections.applications).doc(app.id);
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
      _db.collection(Collections.payments).add(p.toMap()).then((_) {});

  Stream<List<PaymentRecord>> watchPaymentsForParent(String parentUid) => _db
      .collection(Collections.payments)
      .where('parentUid', isEqualTo: parentUid)
      .snapshots()
      .map((s) => s.docs.map(PaymentRecord.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0))));

  Stream<List<PaymentRecord>> watchPayments() => _db
      .collection(Collections.payments)
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
      _db.collection(Collections.payments).doc(paymentId).update({
        'status': status.name,
        'reviewNote': note,
        'reviewedByName': byName,
        'reviewedAt': FieldValue.serverTimestamp(),
      });

  // ---- Chat ----------------------------------------------------------------

  Stream<List<ChatThread>> watchChatsForUser(String uid) => _db
      .collection(Collections.chats)
      .where('participantUids', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.map(ChatThread.fromDoc).toList()
        ..sort((a, b) => (b.updatedAt ?? DateTime(0))
            .compareTo(a.updatedAt ?? DateTime(0))));

  /// Parent→teacher chat requests awaiting admin approval.
  Stream<List<ChatThread>> watchPendingChatRequests() => _db
      .collection(Collections.chats)
      .where('approval', isEqualTo: ChatApproval.requested.name)
      .snapshots()
      .map((s) => s.docs.map(ChatThread.fromDoc).toList()
        ..sort((a, b) => (b.createdAt ?? DateTime(0))
            .compareTo(a.createdAt ?? DateTime(0))));

  /// Opens (or reuses) a staff chat between two staff members.
  Future<String> openStaffChat(AppUser me, AppUser other) async {
    final existing = await _db
        .collection(Collections.chats)
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
    final ref = await _db.collection(Collections.chats).add(thread.toMap());
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
    final existing = await _db
        .collection(Collections.chats)
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
    final ref = await _db.collection(Collections.chats).add(thread.toMap());
    return ref.id;
  }

  Future<void> setChatApproval(String chatId, ChatApproval approval) =>
      _db.collection(Collections.chats).doc(chatId).update({
        'approval': approval.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Stream<ChatThread?> watchChat(String chatId) => _db
      .collection(Collections.chats)
      .doc(chatId)
      .snapshots()
      .map((d) => d.exists ? ChatThread.fromDoc(d) : null);

  Stream<List<ChatMessage>> watchMessages(String chatId) => _db
      .collection(Collections.chats)
      .doc(chatId)
      .collection('messages')
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map(ChatMessage.fromDoc).toList());

  Future<void> sendMessage(String chatId, ChatMessage msg) async {
    final chatRef = _db.collection(Collections.chats).doc(chatId);
    await chatRef.collection('messages').add(msg.toMap());
    await chatRef.update({
      'lastMessage': msg.text,
      'lastSenderUid': msg.senderUid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- Outgoing email ------------------------------------------------------

  /// Queues an email; the SMTP Cloud Function picks it up and sends it.
  /// Used for admin-composed notices — automatic notifications (application
  /// status, payment review) are queued server-side by Firestore triggers.
  Future<void> enqueueMail({
    required String to,
    required String subject,
    required String text,
  }) =>
      _db.collection(Collections.mailQueue).add({
        'to': to,
        'subject': subject,
        'text': text,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
}
