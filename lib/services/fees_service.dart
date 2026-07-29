import '../models/enums.dart';
import '../models/fees.dart';
import '../models/payment.dart';
import '../models/school.dart';

/// The school's accounting rules, kept deliberately free of Firebase so they
/// can be reasoned about and tested on their own.
///
/// Two principles run through all of it:
///
///  * **Money is integer cents.** Rand never appear until something is
///    displayed. A fee split into installments always adds back up to the
///    amount that was set.
///  * **Balances are derived, never stored.** A learner's position is always
///    recomputed from the invoices raised and the payments approved, so it
///    cannot drift away from the documents behind it — the failure mode that
///    makes school fee disputes unwinnable.
class FeesService {
  const FeesService._();

  /// Splits an annual fee into [installments] monthly amounts that sum
  /// **exactly** to [annualCents].
  ///
  /// Dividing R12 001 into 12 leaves a cent over; that remainder goes onto the
  /// first installment rather than being dropped, because a schedule that does
  /// not add up to the fee is the kind of error a parent finds a year later.
  static List<int> installmentAmounts(int annualCents, int installments) {
    if (installments <= 0) return const [];
    if (installments == 1) return [annualCents];
    final base = annualCents ~/ installments;
    final remainder = annualCents - (base * installments);
    return [
      for (var i = 0; i < installments; i++) i == 0 ? base + remainder : base,
    ];
  }

  /// The invoice schedule a learner owes for one annual fee in [year].
  ///
  /// Called when a child is enrolled — the whole year is laid out at once, so
  /// a parent can see the plan on day one — and again each month, where the
  /// deterministic ids mean re-running it changes nothing.
  static List<Invoice> scheduleFor({
    required Learner learner,
    required FeeStructure fee,
    required int year,
  }) {
    if (fee.cycle == FeeCycle.onceOff) {
      final due = fee.dueDate ?? DateTime(year, fee.firstMonth, fee.dueDay);
      final period = Invoice.periodOf(due);
      return [
        Invoice(
          id: Invoice.idFor(learner.id, fee.id, period),
          learnerId: learner.id,
          learnerName: learner.fullName,
          grade: learner.grade,
          parentUids: learner.parentUids,
          period: period,
          feeStructureId: fee.id,
          description: fee.name,
          amountCents: fee.amountCents,
          dueDate: due,
        ),
      ];
    }

    final amounts = installmentAmounts(fee.amountCents, fee.installments);
    final invoices = <Invoice>[];
    for (var i = 0; i < amounts.length; i++) {
      // Roll past December into the next calendar year rather than clamping,
      // so a February-to-January plan bills the months it says it will.
      final monthIndex = fee.firstMonth - 1 + i;
      final due = DateTime(
          year + monthIndex ~/ 12, (monthIndex % 12) + 1, fee.dueDay);
      final period = Invoice.periodOf(due);
      invoices.add(Invoice(
        id: Invoice.idFor(learner.id, fee.id, period),
        learnerId: learner.id,
        learnerName: learner.fullName,
        grade: learner.grade,
        parentUids: learner.parentUids,
        period: period,
        feeStructureId: fee.id,
        description: '${fee.name} — installment ${i + 1} of ${amounts.length}',
        amountCents: amounts[i],
        dueDate: due,
        installmentNumber: i + 1,
        installmentsTotal: amounts.length,
      ));
    }
    return invoices;
  }

  /// Every invoice a learner should have for [year], across all fees that
  /// apply to their grade.
  static List<Invoice> scheduleForLearner({
    required Learner learner,
    required List<FeeStructure> fees,
    required int year,
  }) =>
      [
        for (final fee in fees)
          if (fee.appliesTo(learner.grade) && (fee.year == null || fee.year == year))
            ...scheduleFor(learner: learner, fee: fee, year: year),
      ];

  /// Builds the statement: every charge and every payment in date order, each
  /// with the balance owing after it.
  ///
  /// Only **approved** payments reduce the balance. A payment awaiting the
  /// principal is reported separately by [accountFor] so the parent can see it
  /// has been received without the school's books treating it as settled.
  static List<LedgerLine> statement({
    required List<Invoice> invoices,
    required List<PaymentRecord> payments,
    DateTime? upTo,
  }) {
    final cutoff = upTo ?? DateTime.now();
    final entries = <({DateTime date, LedgerKind kind, String text, int cents, String ref})>[];

    for (final i in invoices) {
      final date = i.dueDate ?? i.issuedAt;
      if (date == null || date.isAfter(cutoff)) continue;
      entries.add((
        date: date,
        kind: LedgerKind.invoice,
        text: i.description.isEmpty ? i.periodLabel : i.description,
        cents: i.amountCents,
        ref: i.period,
      ));
    }
    for (final p in payments) {
      if (p.status != PaymentStatus.approved) continue;
      final date = p.paymentDate ?? p.createdAt;
      if (date == null || date.isAfter(cutoff)) continue;
      entries.add((
        date: date,
        kind: LedgerKind.payment,
        text: p.purpose.isEmpty ? 'Payment received' : p.purpose,
        cents: p.amountCents,
        ref: p.reference,
      ));
    }

    entries.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      // A charge and a payment on the same day read better charge-first.
      return a.kind == b.kind ? 0 : (a.kind == LedgerKind.invoice ? -1 : 1);
    });

    var balance = 0;
    return [
      for (final e in entries)
        LedgerLine(
          date: e.date,
          kind: e.kind,
          description: e.text,
          amountCents: e.cents,
          reference: e.ref,
          balanceCents:
              balance += e.kind == LedgerKind.invoice ? e.cents : -e.cents,
        ),
    ];
  }

  /// A learner's full fee position.
  static FeeAccount accountFor({
    required Learner learner,
    required List<Invoice> invoices,
    required List<PaymentRecord> payments,
    required List<FeeStructure> fees,
    int? year,
    DateTime? asAt,
  }) {
    final now = asAt ?? DateTime.now();
    final forYear = year ?? now.year;
    final mine = invoices.where((i) => i.learnerId == learner.id).toList();
    final theirs =
        payments.where((p) => p.learnerId == learner.id).toList();

    final billed = mine
        .where((i) => !(i.dueDate ?? i.issuedAt ?? now).isAfter(now))
        .fold<int>(0, (acc, i) => acc + i.amountCents);
    final paid = theirs
        .where((p) => p.status == PaymentStatus.approved)
        .fold<int>(0, (acc, p) => acc + p.amountCents);
    final pending = theirs
        .where((p) => p.status == PaymentStatus.pending)
        .fold<int>(0, (acc, p) => acc + p.amountCents);

    final applicable = fees
        .where((f) =>
            f.appliesTo(learner.grade) &&
            (f.year == null || f.year == forYear))
        .toList();
    final annual =
        applicable.fold<int>(0, (acc, f) => acc + f.amountCents);
    final monthly = applicable
        .where((f) => f.cycle == FeeCycle.annual)
        .fold<int>(0, (acc, f) => acc + f.monthlyCents);

    final upcoming = mine
        .where((i) => (i.dueDate ?? now).isAfter(now))
        .map((i) => i.dueDate!)
        .toList()
      ..sort();

    return FeeAccount(
      learnerId: learner.id,
      learnerName: learner.fullName,
      grade: learner.grade,
      billedCents: billed,
      paidCents: paid,
      pendingCents: pending,
      annualCents: annual,
      monthlyCents: monthly,
      nextDue: upcoming.isEmpty ? null : upcoming.first,
      lines: statement(invoices: mine, payments: theirs, upTo: now),
    );
  }

  /// Every learner's position, worst arrears first — the order the office and
  /// the principal want to work through.
  static List<FeeAccount> accountsInArrears({
    required List<Learner> learners,
    required List<Invoice> invoices,
    required List<PaymentRecord> payments,
    required List<FeeStructure> fees,
    DateTime? asAt,
  }) =>
      learners
          .where((l) => l.status == LearnerStatus.active)
          .map((l) => accountFor(
                learner: l,
                invoices: invoices,
                payments: payments,
                fees: fees,
                asAt: asAt,
              ))
          .where((a) => a.isInArrears)
          .toList()
        ..sort((a, b) => b.balanceCents.compareTo(a.balanceCents));

  /// The statement as CSV, for the parent's download.
  static String statementCsv({
    required FeeAccount account,
    String schoolName = '',
  }) {
    String cell(String v) => '"${v.replaceAll('"', '""')}"';
    String money(int cents) => (cents / 100).toStringAsFixed(2);
    String date(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final rows = <String>[
      if (schoolName.isNotEmpty) cell(schoolName),
      cell('Fee statement — ${account.learnerName}'),
      cell('Grade: ${account.grade}'),
      '',
      ['Date', 'Description', 'Reference', 'Charge', 'Payment', 'Balance']
          .map(cell)
          .join(','),
      for (final l in account.lines)
        [
          date(l.date),
          l.description,
          l.reference,
          l.isDebit ? money(l.amountCents) : '',
          l.isDebit ? '' : money(l.amountCents),
          money(l.balanceCents),
        ].map(cell).join(','),
      '',
      [cell('Total charged'), cell(money(account.billedCents))].join(','),
      [cell('Total paid'), cell(money(account.paidCents))].join(','),
      [cell('Balance due'), cell(money(account.balanceCents))].join(','),
      if (account.pendingCents > 0)
        [cell('Awaiting approval'), cell(money(account.pendingCents))].join(','),
    ];
    return rows.join('\n');
  }
}
