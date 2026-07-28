import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// A parent-submitted payment at `payments/{id}`: the completed payment form
/// plus an uploaded proof of payment. Admin reviews and approves/rejects it;
/// the parent is notified by email on approval.
class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.parentUid,
    this.parentName = '',
    this.learnerId,
    this.learnerName = '',
    this.purpose = '',
    this.method = '',
    this.amountCents = 0,
    this.reference = '',
    this.paymentDate,
    this.notes = '',
    this.proofUrl = '',
    this.proofFilename = '',
    this.status = PaymentStatus.pending,
    this.reviewNote = '',
    this.reviewedByName = '',
    this.reviewedAt,
    this.source = 'parent',
    this.feeStructureId,
    this.createdAt,
  });

  final String id;
  final String parentUid;

  /// Denormalised for the admin review list.
  final String parentName;
  final String? learnerId;
  final String learnerName;

  /// What the payment is for (registration fee, school fees, …).
  final String purpose;

  /// How it was paid (EFT, cash deposit, …).
  final String method;
  final int amountCents;

  /// Bank/EFT reference the parent used.
  final String reference;
  final DateTime? paymentDate;
  final String notes;

  /// Uploaded proof of payment (receipt / bank confirmation).
  final String proofUrl;
  final String proofFilename;

  final PaymentStatus status;
  final String reviewNote;
  final String reviewedByName;
  final DateTime? reviewedAt;

  /// Where the record came from: 'parent' (submitted with proof), 'admin'
  /// (recorded at the office) or 'import' (approved bulk CSV upload).
  final String source;

  /// The fee structure this payment settles, when known — used by the
  /// outstanding-fees view.
  final String? feeStructureId;
  final DateTime? createdAt;

  double get amountRand => amountCents / 100.0;
  String get amountLabel => 'R ${(amountCents / 100).toStringAsFixed(2)}';

  Map<String, dynamic> toMap() => {
        'parentUid': parentUid,
        'parentName': parentName,
        'learnerId': learnerId,
        'learnerName': learnerName,
        'purpose': purpose,
        'method': method,
        'amountCents': amountCents,
        'reference': reference,
        'paymentDate':
            paymentDate != null ? Timestamp.fromDate(paymentDate!) : null,
        'notes': notes,
        'proofUrl': proofUrl,
        'proofFilename': proofFilename,
        'status': status.name,
        'reviewNote': reviewNote,
        'reviewedByName': reviewedByName,
        'reviewedAt':
            reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
        'source': source,
        'feeStructureId': feeStructureId,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory PaymentRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return PaymentRecord(
      id: doc.id,
      parentUid: (m['parentUid'] ?? '') as String,
      parentName: (m['parentName'] ?? '') as String,
      learnerId: m['learnerId'] as String?,
      learnerName: (m['learnerName'] ?? '') as String,
      purpose: (m['purpose'] ?? '') as String,
      method: (m['method'] ?? '') as String,
      amountCents: (m['amountCents'] as num?)?.toInt() ?? 0,
      reference: (m['reference'] ?? '') as String,
      paymentDate: (m['paymentDate'] as Timestamp?)?.toDate(),
      notes: (m['notes'] ?? '') as String,
      proofUrl: (m['proofUrl'] ?? '') as String,
      proofFilename: (m['proofFilename'] ?? '') as String,
      status: PaymentStatus.fromString(m['status'] as String?),
      reviewNote: (m['reviewNote'] ?? '') as String,
      reviewedByName: (m['reviewedByName'] ?? '') as String,
      reviewedAt: (m['reviewedAt'] as Timestamp?)?.toDate(),
      source: (m['source'] ?? 'parent') as String,
      feeStructureId: m['feeStructureId'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
