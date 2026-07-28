import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// The special grade value meaning a fee applies to every grade.
const kAllGrades = 'All grades';

/// A configured fee at `feeStructures/{id}` (e.g. "School fees 2026 —
/// Grade 4, R12 000"). Grade may be [kAllGrades]. The outstanding-fees view
/// compares each active learner's applicable structures against their
/// approved payments.
class FeeStructure {
  const FeeStructure({
    required this.id,
    required this.name,
    this.grade = kAllGrades,
    this.year,
    this.amountCents = 0,
    this.dueDate,
    this.createdAt,
  });

  final String id;
  final String name;
  final String grade;
  final int? year;
  final int amountCents;
  final DateTime? dueDate;
  final DateTime? createdAt;

  String get amountLabel => 'R ${(amountCents / 100).toStringAsFixed(2)}';

  bool appliesTo(String learnerGrade) =>
      grade == kAllGrades || grade == learnerGrade;

  Map<String, dynamic> toMap() => {
        'name': name,
        'grade': grade,
        'year': year,
        'amountCents': amountCents,
        'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory FeeStructure.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return FeeStructure(
      id: doc.id,
      name: (m['name'] ?? '') as String,
      grade: (m['grade'] ?? kAllGrades) as String,
      year: (m['year'] as num?)?.toInt(),
      amountCents: (m['amountCents'] as num?)?.toInt() ?? 0,
      dueDate: (m['dueDate'] as Timestamp?)?.toDate(),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// One parsed row of a bulk payment CSV upload. Invalid rows carry an
/// [error] and are skipped on approval.
class ImportRow {
  const ImportRow({
    this.learnerId = '',
    this.learnerName = '',
    this.amountCents = 0,
    this.date,
    this.method = '',
    this.reference = '',
    this.purpose = 'School fees',
    this.error,
  });

  final String learnerId;
  final String learnerName;
  final int amountCents;
  final DateTime? date;
  final String method;
  final String reference;
  final String purpose;
  final String? error;

  bool get valid => error == null;
  String get amountLabel => 'R ${(amountCents / 100).toStringAsFixed(2)}';

  Map<String, dynamic> toMap() => {
        'learnerId': learnerId,
        'learnerName': learnerName,
        'amountCents': amountCents,
        'date': date != null ? Timestamp.fromDate(date!) : null,
        'method': method,
        'reference': reference,
        'purpose': purpose,
        'error': error,
      };

  factory ImportRow.fromMap(Map<String, dynamic> m) => ImportRow(
        learnerId: (m['learnerId'] ?? '') as String,
        learnerName: (m['learnerName'] ?? '') as String,
        amountCents: (m['amountCents'] as num?)?.toInt() ?? 0,
        date: (m['date'] as Timestamp?)?.toDate(),
        method: (m['method'] ?? '') as String,
        reference: (m['reference'] ?? '') as String,
        purpose: (m['purpose'] ?? 'School fees') as String,
        error: m['error'] as String?,
      );
}

/// A staged bulk payment upload at `paymentImports/{id}`. Uploaded CSVs are
/// parsed and **staged** here first; an admin reviews the rows and then
/// approves (creating the payment records) or discards the batch.
class PaymentImport {
  const PaymentImport({
    required this.id,
    this.filename = '',
    this.rows = const [],
    this.status = ImportStatus.staged,
    this.createdByName = '',
    this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final String filename;
  final List<ImportRow> rows;
  final ImportStatus status;
  final String createdByName;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  int get validCount => rows.where((r) => r.valid).length;
  int get invalidCount => rows.length - validCount;
  int get totalCents =>
      rows.where((r) => r.valid).fold(0, (acc, r) => acc + r.amountCents);
  String get totalLabel => 'R ${(totalCents / 100).toStringAsFixed(2)}';

  Map<String, dynamic> toMap() => {
        'filename': filename,
        'rows': rows.map((r) => r.toMap()).toList(),
        'status': status.name,
        'createdByName': createdByName,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        'resolvedAt':
            resolvedAt != null ? Timestamp.fromDate(resolvedAt!) : null,
      };

  factory PaymentImport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return PaymentImport(
      id: doc.id,
      filename: (m['filename'] ?? '') as String,
      rows: ((m['rows'] as List?) ?? const [])
          .whereType<Map>()
          .map((r) => ImportRow.fromMap(Map<String, dynamic>.from(r)))
          .toList(),
      status: ImportStatus.fromString(m['status'] as String?),
      createdByName: (m['createdByName'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      resolvedAt: (m['resolvedAt'] as Timestamp?)?.toDate(),
    );
  }
}
