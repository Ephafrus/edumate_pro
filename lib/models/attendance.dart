import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// A QR-scan attendance event at `attendance/{id}`: a staff member scanned a
/// learner's QR code and marked them in (dropped off / present) or out
/// (leaving school). A Cloud Function emails the linked parents on create.
///
/// The QR code itself encodes [qrPrefix] + the learner's document id.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.learnerId,
    required this.type,
    this.learnerName = '',
    this.className = '',
    this.byUid = '',
    this.byName = '',
    this.parentUids = const [],
    this.at,
  });

  static const qrPrefix = 'edumate-learner:';

  /// The scan payload for a learner's QR code.
  static String qrData(String learnerId) => '$qrPrefix$learnerId';

  /// Extracts the learner id from a scanned code, or null if it is not an
  /// EduMate Pro learner QR.
  static String? learnerIdFromQr(String? raw) {
    if (raw == null || !raw.startsWith(qrPrefix)) return null;
    final id = raw.substring(qrPrefix.length).trim();
    return id.isEmpty ? null : id;
  }

  final String id;
  final String learnerId;
  final AttendanceType type;

  /// Denormalised for lists and the notification email.
  final String learnerName;
  final String className;

  /// The staff member who scanned.
  final String byUid;
  final String byName;

  /// Copied from the learner at scan time so parents can read their child's
  /// attendance without an extra lookup (and rules can check membership).
  final List<String> parentUids;

  final DateTime? at;

  Map<String, dynamic> toMap() => {
        'learnerId': learnerId,
        'type': type.name,
        'learnerName': learnerName,
        'className': className,
        'byUid': byUid,
        'byName': byName,
        'parentUids': parentUids,
        'at': at != null
            ? Timestamp.fromDate(at!)
            : FieldValue.serverTimestamp(),
      };

  factory AttendanceRecord.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return AttendanceRecord(
      id: doc.id,
      learnerId: (m['learnerId'] ?? '') as String,
      type: AttendanceType.fromString(m['type'] as String?),
      learnerName: (m['learnerName'] ?? '') as String,
      className: (m['className'] ?? '') as String,
      byUid: (m['byUid'] ?? '') as String,
      byName: (m['byName'] ?? '') as String,
      parentUids:
          ((m['parentUids'] as List?) ?? const []).map((e) => '$e').toList(),
      at: (m['at'] as Timestamp?)?.toDate(),
    );
  }
}
