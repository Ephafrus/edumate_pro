import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
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

  Future<Learner?> getLearner(String id) async {
    final doc = await _db.collection(Collections.learners).doc(id).get();
    return doc.exists ? Learner.fromDoc(doc) : null;
  }

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

  // ---- QR attendance -------------------------------------------------------

  /// Records a QR attendance scan: creates the attendance event and stamps
  /// the learner's live status, atomically. The `onAttendanceScan` Cloud
  /// Function emails the linked parents.
  Future<void> recordAttendance(
    Learner learner,
    AttendanceType type, {
    required AppUser by,
  }) {
    final eventRef = _db.collection(Collections.attendance).doc();
    final learnerRef =
        _db.collection(Collections.learners).doc(learner.id);
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
      _db
          .collection(Collections.attendance)
          .where('learnerId', isEqualTo: learnerId)
          .orderBy('at', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(AttendanceRecord.fromDoc).toList());

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

  // ---- SMTP settings & outgoing email -------------------------------------

  MailSettings? _cachedMailSettings;

  /// The school's SMTP settings (settings/smtp), cached per session.
  Future<MailSettings?> getMailSettings({bool refresh = false}) async {
    if (!refresh && _cachedMailSettings != null) return _cachedMailSettings;
    final doc =
        await _db.collection(Collections.settings).doc('smtp').get();
    _cachedMailSettings = doc.exists ? MailSettings.fromDoc(doc) : null;
    return _cachedMailSettings;
  }

  Future<void> setMailSettings(MailSettings settings) async {
    await _db
        .collection(Collections.settings)
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
      _db.collection(Collections.mailQueue).add({
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
    final snap = await _db
        .collection(Collections.mailQueue)
        .where('status', whereIn: ['pending', 'error'])
        .limit(limit)
        .get();
    return snap.docs.map(QueuedMail.fromDoc).toList();
  }

  Future<void> markMail(String id, String status, {String error = ''}) =>
      _db.collection(Collections.mailQueue).doc(id).update({
        'status': status,
        'error': error,
        if (status == 'sent') 'sentAt': FieldValue.serverTimestamp(),
      });

  /// Live count of unsent outbox messages, for the Email settings screen.
  Stream<int> watchOutboxCount() => _db
      .collection(Collections.mailQueue)
      .where('status', whereIn: ['pending', 'error'])
      .snapshots()
      .map((s) => s.docs.length);

  // ---- Broadcast messages --------------------------------------------------

  Future<String> createBroadcast(Broadcast b) async {
    final ref = await _db.collection(Collections.broadcasts).add(b.toMap());
    return ref.id;
  }

  Future<void> updateBroadcast(String id, Map<String, dynamic> data) =>
      _db.collection(Collections.broadcasts).doc(id).update(data);

  /// All broadcasts, newest first (admin history).
  Stream<List<Broadcast>> watchBroadcasts() => _db
      .collection(Collections.broadcasts)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(Broadcast.fromDoc).toList());

  /// Broadcasts addressed to this parent, newest first (announcements feed
  /// + the notification bell).
  Stream<List<Broadcast>> watchBroadcastsForUser(String uid,
          {int limit = 50}) =>
      _db
          .collection(Collections.broadcasts)
          .where('recipientUids', arrayContains: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((s) => s.docs.map(Broadcast.fromDoc).toList());

  /// Marks the user's announcements as seen (clears the bell badge).
  Future<void> markBroadcastsSeen(String uid) =>
      updateUser(uid, {'broadcastsSeenAt': FieldValue.serverTimestamp()});

  // ---- Calendar events -----------------------------------------------------

  Stream<List<CalendarEvent>> watchEvents() => _db
      .collection(Collections.events)
      .orderBy('start')
      .snapshots()
      .map((s) => s.docs.map(CalendarEvent.fromDoc).toList());

  Future<void> createEvent(CalendarEvent e) =>
      _db.collection(Collections.events).add(e.toMap()).then((_) {});

  Future<void> deleteEvent(String id) =>
      _db.collection(Collections.events).doc(id).delete();

  // ---- Fees ----------------------------------------------------------------

  Stream<List<FeeStructure>> watchFeeStructures() =>
      _db.collection(Collections.feeStructures).snapshots().map(
            (s) => s.docs.map(FeeStructure.fromDoc).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
          );

  Future<void> createFeeStructure(FeeStructure f) =>
      _db.collection(Collections.feeStructures).add(f.toMap()).then((_) {});

  Future<void> updateFeeStructure(String id, Map<String, dynamic> data) =>
      _db.collection(Collections.feeStructures).doc(id).update(data);

  Future<void> deleteFeeStructure(String id) =>
      _db.collection(Collections.feeStructures).doc(id).delete();

  /// Admin records a fee payment at the office — created pre-approved.
  Future<void> recordAdminPayment(PaymentRecord p) => createPayment(p);

  // ---- Bulk payment imports (staged CSV uploads) ---------------------------

  Future<String> createPaymentImport(PaymentImport imp) async {
    final ref =
        await _db.collection(Collections.paymentImports).add(imp.toMap());
    return ref.id;
  }

  Stream<List<PaymentImport>> watchPaymentImports() => _db
      .collection(Collections.paymentImports)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(PaymentImport.fromDoc).toList());

  Future<void> discardPaymentImport(String id) =>
      _db.collection(Collections.paymentImports).doc(id).update({
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
        final ref = _db.collection(Collections.payments).doc();
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
    await _db.collection(Collections.paymentImports).doc(imp.id).update({
      'status': ImportStatus.approved.name,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
    return created;
  }
}
