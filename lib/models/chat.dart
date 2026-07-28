import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// A chat thread at `chats/{id}` with a `messages` subcollection.
///
/// Two kinds:
///  * [ChatType.staff] — between staff members (admin/teachers); active
///    immediately.
///  * [ChatType.parentTeacher] — requested by a parent with a teacher; starts
///    as [ChatApproval.requested] and unlocks once an admin approves it.
class ChatThread {
  const ChatThread({
    required this.id,
    required this.type,
    required this.participantUids,
    this.participantNames = const {},
    this.approval = ChatApproval.approved,
    this.requestReason = '',
    this.learnerName = '',
    this.lastMessage = '',
    this.lastSenderUid = '',
    this.updatedAt,
    this.createdAt,
  });

  final String id;
  final ChatType type;
  final List<String> participantUids;

  /// uid → display name, denormalised so thread lists render without lookups.
  final Map<String, String> participantNames;

  final ChatApproval approval;

  /// Why the parent asked to chat (shown to the approving admin).
  final String requestReason;

  /// The learner the parent-teacher chat concerns, if given.
  final String learnerName;

  final String lastMessage;
  final String lastSenderUid;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  bool get isActive => approval == ChatApproval.approved;

  /// Display name of the other participant from [uid]'s point of view.
  String titleFor(String uid) {
    for (final entry in participantNames.entries) {
      if (entry.key != uid && entry.value.isNotEmpty) return entry.value;
    }
    return 'Chat';
  }

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'participantUids': participantUids,
        'participantNames': participantNames,
        'approval': approval.name,
        'requestReason': requestReason,
        'learnerName': learnerName,
        'lastMessage': lastMessage,
        'lastSenderUid': lastSenderUid,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory ChatThread.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return ChatThread(
      id: doc.id,
      type: ChatType.fromString(m['type'] as String?),
      participantUids: ((m['participantUids'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      participantNames: ((m['participantNames'] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', '$v')),
      approval: ChatApproval.fromString(m['approval'] as String?),
      requestReason: (m['requestReason'] ?? '') as String,
      learnerName: (m['learnerName'] ?? '') as String,
      lastMessage: (m['lastMessage'] ?? '') as String,
      lastSenderUid: (m['lastSenderUid'] ?? '') as String,
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// A message within a chat thread (`chats/{chatId}/messages/{id}`).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUid,
    this.senderName = '',
    this.text = '',
    this.createdAt,
  });

  final String id;
  final String senderUid;
  final String senderName;
  final String text;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() => {
        'senderUid': senderUid,
        'senderName': senderName,
        'text': text,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return ChatMessage(
      id: doc.id,
      senderUid: (m['senderUid'] ?? '') as String,
      senderName: (m['senderName'] ?? '') as String,
      text: (m['text'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
