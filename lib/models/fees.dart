import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// The special grade value meaning a fee applies to every grade.
const kAllGrades = 'All grades';

/// A configured fee at `feeStructures/{id}` (e.g. "School fees 2026 —
/// Grade 4, R12 000"). Grade may be [kAllGrades]. The outstanding-fees view
/// compares each active learner's applicable structures against their
/// approved payments.
/// How a fee is charged.
enum FeeCycle {
  /// Tuition for the year, billed in monthly installments.
  annual,

  /// A single charge (registration, a trip) invoiced once when it applies.
  onceOff;

  static FeeCycle fromString(String? s) =>
      s == 'onceOff' ? FeeCycle.onceOff : FeeCycle.annual;

  String get label =>
      this == FeeCycle.annual ? 'Annual tuition' : 'Once-off charge';
}

class FeeStructure {
  const FeeStructure({
    required this.id,
    required this.name,
    this.grade = kAllGrades,
    this.year,
    this.amountCents = 0,
    this.cycle = FeeCycle.annual,
    this.installments = 12,
    this.firstMonth = 1,
    this.dueDay = 7,
    this.dueDate,
    this.createdAt,
  });

  final String id;
  final String name;
  final String grade;
  final int? year;

  /// For [FeeCycle.annual] this is the **whole year's** tuition, which is
  /// split into [installments] monthly invoices. For a once-off charge it is
  /// simply the amount.
  final int amountCents;
  final FeeCycle cycle;

  /// How many monthly invoices the annual amount is spread over.
  final int installments;

  /// Calendar month (1–12) the first installment falls in — schools rarely
  /// bill in December.
  final int firstMonth;

  /// Day of the month each installment is due.
  final int dueDay;
  final DateTime? dueDate;
  final DateTime? createdAt;

  String get amountLabel => 'R ${(amountCents / 100).toStringAsFixed(2)}';

  /// What a parent pays each month, before any rounding remainder — see
  /// `FeesService.installmentAmounts` for the exact schedule.
  int get monthlyCents => cycle == FeeCycle.annual && installments > 0
      ? amountCents ~/ installments
      : amountCents;

  String get monthlyLabel => 'R ${(monthlyCents / 100).toStringAsFixed(2)}';

  bool appliesTo(String learnerGrade) =>
      grade == kAllGrades || grade == learnerGrade;

  Map<String, dynamic> toMap() => {
        'name': name,
        'grade': grade,
        'year': year,
        'amountCents': amountCents,
        'cycle': cycle.name,
        'installments': installments,
        'firstMonth': firstMonth,
        'dueDay': dueDay,
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
      cycle: FeeCycle.fromString(m['cycle'] as String?),
      installments: (m['installments'] as num?)?.toInt() ?? 12,
      firstMonth: (m['firstMonth'] as num?)?.toInt() ?? 1,
      dueDay: (m['dueDay'] as num?)?.toInt() ?? 7,
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

/// One charge raised against a learner, at
/// `schools/{schoolId}/invoices/{id}`.
///
/// Invoices are the debit side of a learner's fee account: the annual tuition
/// becomes one invoice per month, and once-off charges become a single
/// invoice. Payments are the credit side. Balance is always
/// `invoices raised − payments approved`, never a stored running total, so it
/// cannot drift out of step with the documents it is derived from.
class Invoice {
  const Invoice({
    required this.id,
    required this.learnerId,
    required this.period,
    required this.amountCents,
    this.learnerName = '',
    this.grade = '',
    this.parentUids = const [],
    this.feeStructureId,
    this.description = '',
    this.dueDate,
    this.issuedAt,
    this.installmentNumber,
    this.installmentsTotal,
  });

  final String id;
  final String learnerId;
  final String learnerName;
  final String grade;

  /// Parents who may see this invoice — copied from the learner so the
  /// parent's own query does not need a join.
  final List<String> parentUids;

  /// Billing period as `YYYY-MM`. With [learnerId] and [feeStructureId] this
  /// forms the document id, which is what makes monthly generation safe to
  /// run from any number of devices — see [Invoice.idFor].
  final String period;
  final String? feeStructureId;
  final String description;
  final int amountCents;
  final DateTime? dueDate;
  final DateTime? issuedAt;
  final int? installmentNumber;
  final int? installmentsTotal;

  String get amountLabel => 'R ${(amountCents / 100).toStringAsFixed(2)}';

  String get periodLabel {
    final parts = period.split('-');
    if (parts.length != 2) return period;
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final m = int.tryParse(parts[1]) ?? 0;
    if (m < 1 || m > 12) return period;
    return '${months[m - 1]} ${parts[0]}';
  }

  bool get isOverdue =>
      dueDate != null && dueDate!.isBefore(DateTime.now());

  /// Deterministic id: one invoice per learner, per fee, per month. Re-running
  /// generation overwrites rather than duplicates, which matters because the
  /// monthly run is triggered by whichever staff session opens the app first.
  static String idFor(String learnerId, String? feeStructureId, String period) =>
      '${learnerId}__${feeStructureId ?? 'adhoc'}__$period';

  /// `YYYY-MM` for a date.
  static String periodOf(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
        'learnerId': learnerId,
        'learnerName': learnerName,
        'grade': grade,
        'parentUids': parentUids,
        'period': period,
        'feeStructureId': feeStructureId,
        'description': description,
        'amountCents': amountCents,
        'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
        'issuedAt': issuedAt != null
            ? Timestamp.fromDate(issuedAt!)
            : FieldValue.serverTimestamp(),
        'installmentNumber': installmentNumber,
        'installmentsTotal': installmentsTotal,
      };

  factory Invoice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return Invoice(
      id: doc.id,
      learnerId: (m['learnerId'] ?? '') as String,
      learnerName: (m['learnerName'] ?? '') as String,
      grade: (m['grade'] ?? '') as String,
      parentUids:
          ((m['parentUids'] as List?) ?? const []).map((e) => '$e').toList(),
      period: (m['period'] ?? '') as String,
      feeStructureId: m['feeStructureId'] as String?,
      description: (m['description'] ?? '') as String,
      amountCents: (m['amountCents'] as num?)?.toInt() ?? 0,
      dueDate: (m['dueDate'] as Timestamp?)?.toDate(),
      issuedAt: (m['issuedAt'] as Timestamp?)?.toDate(),
      installmentNumber: (m['installmentNumber'] as num?)?.toInt(),
      installmentsTotal: (m['installmentsTotal'] as num?)?.toInt(),
    );
  }
}

/// Whether a statement line adds to what is owed or reduces it.
enum LedgerKind { invoice, payment }

/// One line of a learner's fee statement, with the balance **after** it.
class LedgerLine {
  const LedgerLine({
    required this.date,
    required this.kind,
    required this.description,
    required this.amountCents,
    required this.balanceCents,
    this.reference = '',
  });

  final DateTime date;
  final LedgerKind kind;
  final String description;

  /// Always positive; [kind] says which way it moves the balance.
  final int amountCents;

  /// Running balance after this line — what the parent still owes.
  final int balanceCents;
  final String reference;

  bool get isDebit => kind == LedgerKind.invoice;

  String get debitLabel =>
      isDebit ? 'R ${(amountCents / 100).toStringAsFixed(2)}' : '';
  String get creditLabel =>
      isDebit ? '' : 'R ${(amountCents / 100).toStringAsFixed(2)}';
  String get balanceLabel => 'R ${(balanceCents / 100).toStringAsFixed(2)}';
}

/// A learner's fee position: what has been billed, what has been paid, and
/// what is still owed.
class FeeAccount {
  const FeeAccount({
    required this.learnerId,
    required this.learnerName,
    required this.grade,
    required this.billedCents,
    required this.paidCents,
    required this.pendingCents,
    required this.annualCents,
    required this.monthlyCents,
    required this.lines,
    this.nextDue,
  });

  final String learnerId;
  final String learnerName;
  final String grade;

  /// Invoiced so far this year — the basis for "balance to date".
  final int billedCents;

  /// Payments the principal has approved.
  final int paidCents;

  /// Submitted but not yet approved: shown to the parent so a payment they
  /// have made does not look ignored, but never counted as settled.
  final int pendingCents;

  /// The full year's tuition, whether invoiced yet or not.
  final int annualCents;
  final int monthlyCents;
  final List<LedgerLine> lines;
  final DateTime? nextDue;

  /// What is owed **now**: only invoices already raised count.
  int get balanceCents => billedCents - paidCents;

  /// What will be owed over the whole year.
  int get yearOutstandingCents => annualCents - paidCents;

  bool get isInArrears => balanceCents > 0;
  bool get isSettled => balanceCents <= 0;

  String get balanceLabel => 'R ${(balanceCents / 100).toStringAsFixed(2)}';
  String get paidLabel => 'R ${(paidCents / 100).toStringAsFixed(2)}';
  String get billedLabel => 'R ${(billedCents / 100).toStringAsFixed(2)}';
  String get annualLabel => 'R ${(annualCents / 100).toStringAsFixed(2)}';
  String get monthlyLabel => 'R ${(monthlyCents / 100).toStringAsFixed(2)}';
  String get pendingLabel => 'R ${(pendingCents / 100).toStringAsFixed(2)}';
}
