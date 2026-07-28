import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// A broadcast message at `broadcasts/{id}`, composed by an admin with the
/// HTML editor and targeted per learner, per class or the whole school.
/// The resolved parent uids are stored on the doc so each parent's app shows
/// it as an in-app notification (bell + announcements feed); the same
/// message is emailed to every recipient over SMTP.
class Broadcast {
  const Broadcast({
    required this.id,
    required this.subject,
    required this.html,
    this.scope = BroadcastScope.school,
    this.classId,
    this.className = '',
    this.learnerId,
    this.learnerName = '',
    this.recipientUids = const [],
    this.emailsSent = 0,
    this.emailsFailed = 0,
    this.sentByName = '',
    this.createdAt,
  });

  final String id;
  final String subject;

  /// The rich message body (HTML), rendered in-app and sent as email HTML.
  final String html;
  final BroadcastScope scope;
  final String? classId;
  final String className;
  final String? learnerId;
  final String learnerName;

  /// Parent accounts this broadcast targets (resolved at send time).
  final List<String> recipientUids;
  final int emailsSent;
  final int emailsFailed;
  final String sentByName;
  final DateTime? createdAt;

  String get scopeLabel {
    switch (scope) {
      case BroadcastScope.school:
        return 'Whole school';
      case BroadcastScope.schoolClass:
        return 'Class: $className';
      case BroadcastScope.learner:
        return 'Learner: $learnerName';
    }
  }

  Map<String, dynamic> toMap() => {
        'subject': subject,
        'html': html,
        'scope': scope.name,
        'classId': classId,
        'className': className,
        'learnerId': learnerId,
        'learnerName': learnerName,
        'recipientUids': recipientUids,
        'emailsSent': emailsSent,
        'emailsFailed': emailsFailed,
        'sentByName': sentByName,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory Broadcast.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Broadcast(
      id: doc.id,
      subject: (m['subject'] ?? '') as String,
      html: (m['html'] ?? '') as String,
      scope: BroadcastScope.fromString(m['scope'] as String?),
      classId: m['classId'] as String?,
      className: (m['className'] ?? '') as String,
      learnerId: m['learnerId'] as String?,
      learnerName: (m['learnerName'] ?? '') as String,
      recipientUids: ((m['recipientUids'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      emailsSent: (m['emailsSent'] as num?)?.toInt() ?? 0,
      emailsFailed: (m['emailsFailed'] as num?)?.toInt() ?? 0,
      sentByName: (m['sentByName'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
