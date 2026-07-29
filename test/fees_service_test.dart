// The accounting rules. These are the calculations a parent will check with
// a calculator and a school will be held to, so they are tested in cents and
// at the awkward numbers rather than the round ones.
import 'package:flutter_test/flutter_test.dart';

import 'package:edumate_pro/models/enums.dart';
import 'package:edumate_pro/models/fees.dart';
import 'package:edumate_pro/models/payment.dart';
import 'package:edumate_pro/models/school.dart';
import 'package:edumate_pro/services/fees_service.dart';

Learner learner({String grade = 'Grade 4'}) => Learner(
      id: 'l1',
      firstName: 'Thandi',
      lastName: 'Mokoena',
      grade: grade,
      status: LearnerStatus.active,
      parentUids: const ['p1'],
    );

FeeStructure annualFee({
  int cents = 1200000, // R12 000
  int installments = 12,
  int firstMonth = 1,
  String grade = 'Grade 4',
  int? year = 2026,
}) =>
    FeeStructure(
      id: 'f1',
      name: 'School fees 2026',
      grade: grade,
      year: year,
      amountCents: cents,
      installments: installments,
      firstMonth: firstMonth,
      dueDay: 7,
    );

PaymentRecord payment({
  required int cents,
  required DateTime on,
  PaymentStatus status = PaymentStatus.approved,
  String purpose = 'School fees',
}) =>
    PaymentRecord(
      id: 'pay-${on.millisecondsSinceEpoch}-$cents',
      parentUid: 'p1',
      learnerId: 'l1',
      amountCents: cents,
      paymentDate: on,
      status: status,
      purpose: purpose,
    );

void main() {
  group('Splitting an annual fee', () {
    test('divides evenly when it can', () {
      final parts = FeesService.installmentAmounts(1200000, 12);
      expect(parts, everyElement(100000));
      expect(parts.length, 12);
    });

    test('never loses the remainder', () {
      // R12 000.07 over 12 does not divide; the 7c must not vanish.
      final parts = FeesService.installmentAmounts(1200007, 12);
      expect(parts.reduce((a, b) => a + b), 1200007);
      expect(parts.first, 100007 - 100000 + 100000); // remainder on the first
      expect(parts.skip(1), everyElement(100000));
    });

    test('adds up for a range of awkward amounts', () {
      for (final cents in [1, 99, 100001, 1234567, 999999999]) {
        for (final n in [1, 3, 4, 10, 11, 12]) {
          expect(FeesService.installmentAmounts(cents, n).reduce((a, b) => a + b),
              cents,
              reason: '$cents over $n installments');
        }
      }
    });

    test('a single installment is the whole fee', () {
      expect(FeesService.installmentAmounts(555, 1), [555]);
    });

    test('no installments yields no schedule rather than dividing by zero', () {
      expect(FeesService.installmentAmounts(1000, 0), isEmpty);
    });
  });

  group('The invoice schedule', () {
    test('raises one invoice per installment, summing to the annual fee', () {
      final invoices = FeesService.scheduleFor(
          learner: learner(), fee: annualFee(), year: 2026);
      expect(invoices.length, 12);
      expect(invoices.fold<int>(0, (a, i) => a + i.amountCents), 1200000);
      expect(invoices.first.period, '2026-01');
      expect(invoices.last.period, '2026-12');
    });

    test('rolls into the next year when the plan starts late', () {
      final invoices = FeesService.scheduleFor(
          learner: learner(),
          fee: annualFee(firstMonth: 2, installments: 12),
          year: 2026);
      expect(invoices.first.period, '2026-02');
      expect(invoices.last.period, '2027-01');
    });

    test('ids are deterministic, so re-running creates no duplicates', () {
      final first = FeesService.scheduleFor(
          learner: learner(), fee: annualFee(), year: 2026);
      final second = FeesService.scheduleFor(
          learner: learner(), fee: annualFee(), year: 2026);
      expect(first.map((i) => i.id), second.map((i) => i.id));
      expect(first.map((i) => i.id).toSet().length, 12, reason: 'ids unique');
    });

    test('a once-off charge raises exactly one invoice', () {
      final fee = FeeStructure(
        id: 'reg',
        name: 'Registration',
        grade: 'Grade 4',
        year: 2026,
        amountCents: 50000,
        cycle: FeeCycle.onceOff,
        dueDate: DateTime(2026, 3, 15),
      );
      final invoices =
          FeesService.scheduleFor(learner: learner(), fee: fee, year: 2026);
      expect(invoices.length, 1);
      expect(invoices.single.amountCents, 50000);
      expect(invoices.single.period, '2026-03');
    });

    test('only fees for the learner\'s grade apply', () {
      final invoices = FeesService.scheduleForLearner(
        learner: learner(grade: 'Grade 4'),
        fees: [
          annualFee(grade: 'Grade 4'),
          FeeStructure(
              id: 'f2',
              name: 'Grade 7 fees',
              grade: 'Grade 7',
              year: 2026,
              amountCents: 900000),
        ],
        year: 2026,
      );
      expect(invoices.every((i) => i.feeStructureId == 'f1'), isTrue);
    });

    test('a fee for all grades applies to everyone', () {
      final invoices = FeesService.scheduleForLearner(
        learner: learner(grade: 'Grade 9'),
        fees: [annualFee(grade: kAllGrades)],
        year: 2026,
      );
      expect(invoices, isNotEmpty);
    });
  });

  group('The statement', () {
    test('shows a reducing balance', () {
      final invoices = FeesService.scheduleFor(
          learner: learner(), fee: annualFee(), year: 2026);
      final lines = FeesService.statement(
        invoices: invoices,
        payments: [
          payment(cents: 100000, on: DateTime(2026, 1, 10)),
          payment(cents: 100000, on: DateTime(2026, 2, 10)),
        ],
        upTo: DateTime(2026, 3, 31),
      );

      // Jan charge, Jan payment, Feb charge, Feb payment, Mar charge.
      expect(lines.length, 5);
      expect(lines[0].balanceCents, 100000);
      expect(lines[1].balanceCents, 0);
      expect(lines[2].balanceCents, 100000);
      expect(lines[3].balanceCents, 0);
      expect(lines[4].balanceCents, 100000);
    });

    test('ignores invoices not yet raised', () {
      final invoices = FeesService.scheduleFor(
          learner: learner(), fee: annualFee(), year: 2026);
      final lines = FeesService.statement(
          invoices: invoices, payments: const [], upTo: DateTime(2026, 3, 31));
      expect(lines.length, 3, reason: 'only Jan, Feb, Mar are due');
    });

    test('a payment awaiting approval does not reduce the balance', () {
      final lines = FeesService.statement(
        invoices: FeesService.scheduleFor(
            learner: learner(), fee: annualFee(), year: 2026),
        payments: [
          payment(
              cents: 100000,
              on: DateTime(2026, 1, 10),
              status: PaymentStatus.pending),
        ],
        upTo: DateTime(2026, 1, 31),
      );
      expect(lines.length, 1);
      expect(lines.single.balanceCents, 100000);
    });

    test('a rejected payment never appears', () {
      final lines = FeesService.statement(
        invoices: const [],
        payments: [
          payment(
              cents: 100000,
              on: DateTime(2026, 1, 10),
              status: PaymentStatus.rejected),
        ],
        upTo: DateTime(2026, 12, 31),
      );
      expect(lines, isEmpty);
    });

    test('overpayment shows as a credit', () {
      final lines = FeesService.statement(
        invoices: FeesService.scheduleFor(
            learner: learner(), fee: annualFee(), year: 2026),
        payments: [payment(cents: 500000, on: DateTime(2026, 1, 20))],
        upTo: DateTime(2026, 1, 31),
      );
      expect(lines.last.balanceCents, -400000);
    });
  });

  group('The fee account', () {
    final invoices = FeesService.scheduleFor(
        learner: learner(), fee: annualFee(), year: 2026);

    test('balance to date counts only what has been billed', () {
      final account = FeesService.accountFor(
        learner: learner(),
        invoices: invoices,
        payments: const [],
        fees: [annualFee()],
        asAt: DateTime(2026, 3, 31),
      );
      expect(account.billedCents, 300000, reason: 'three months billed');
      expect(account.balanceCents, 300000);
      expect(account.annualCents, 1200000);
      expect(account.yearOutstandingCents, 1200000);
      expect(account.monthlyCents, 100000);
    });

    test('separates approved from awaiting-approval', () {
      final account = FeesService.accountFor(
        learner: learner(),
        invoices: invoices,
        payments: [
          payment(cents: 100000, on: DateTime(2026, 1, 10)),
          payment(
              cents: 100000,
              on: DateTime(2026, 2, 10),
              status: PaymentStatus.pending),
        ],
        fees: [annualFee()],
        asAt: DateTime(2026, 3, 31),
      );
      expect(account.paidCents, 100000);
      expect(account.pendingCents, 100000);
      expect(account.balanceCents, 200000,
          reason: 'the pending payment has not settled anything');
    });

    test('knows when the next installment falls', () {
      final account = FeesService.accountFor(
        learner: learner(),
        invoices: invoices,
        payments: const [],
        fees: [annualFee()],
        asAt: DateTime(2026, 3, 31),
      );
      expect(account.nextDue, DateTime(2026, 4, 7));
    });

    test('a fully paid learner is not in arrears', () {
      final account = FeesService.accountFor(
        learner: learner(),
        invoices: invoices,
        payments: [payment(cents: 300000, on: DateTime(2026, 3, 20))],
        fees: [annualFee()],
        asAt: DateTime(2026, 3, 31),
      );
      expect(account.isInArrears, isFalse);
      expect(account.balanceCents, 0);
    });
  });

  group('Arrears list', () {
    test('lists only learners who owe, worst first', () {
      final a = Learner(
          id: 'a',
          firstName: 'A',
          lastName: 'One',
          grade: 'Grade 4',
          status: LearnerStatus.active);
      final b = Learner(
          id: 'b',
          firstName: 'B',
          lastName: 'Two',
          grade: 'Grade 4',
          status: LearnerStatus.active);
      final gone = Learner(
          id: 'c',
          firstName: 'C',
          lastName: 'Three',
          grade: 'Grade 4',
          status: LearnerStatus.applicant);

      List<Invoice> billFor(String id, int cents) => [
            Invoice(
              id: '${id}__f1__2026-01',
              learnerId: id,
              period: '2026-01',
              amountCents: cents,
              dueDate: DateTime(2026, 1, 7),
            ),
          ];

      final accounts = FeesService.accountsInArrears(
        learners: [a, b, gone],
        invoices: [
          ...billFor('a', 100000),
          ...billFor('b', 250000),
          ...billFor('c', 900000),
        ],
        payments: [
          PaymentRecord(
              id: 'p',
              parentUid: 'p1',
              learnerId: 'b',
              amountCents: 50000,
              paymentDate: DateTime(2026, 1, 20),
              status: PaymentStatus.approved),
        ],
        fees: [annualFee()],
        asAt: DateTime(2026, 1, 31),
      );

      expect(accounts.map((x) => x.learnerId), ['b', 'a'],
          reason: 'B owes 2000, A owes 1000, C is not enrolled');
    });
  });

  group('Statement export', () {
    test('carries the lines and the totals', () {
      final account = FeesService.accountFor(
        learner: learner(),
        invoices: FeesService.scheduleFor(
            learner: learner(), fee: annualFee(), year: 2026),
        payments: [payment(cents: 100000, on: DateTime(2026, 1, 10))],
        fees: [annualFee()],
        asAt: DateTime(2026, 2, 28),
      );
      final csv =
          FeesService.statementCsv(account: account, schoolName: 'Test School');

      expect(csv, contains('Test School'));
      expect(csv, contains('Thandi Mokoena'));
      expect(csv, contains('Balance due'));
      expect(csv, contains('1000.00'));
    });

    test('escapes quotes rather than corrupting the row', () {
      final account = FeesService.accountFor(
        learner: learner(),
        invoices: [
          Invoice(
            id: 'i1',
            learnerId: 'l1',
            period: '2026-01',
            description: 'Trip to the "big" museum',
            amountCents: 5000,
            dueDate: DateTime(2026, 1, 7),
          ),
        ],
        payments: const [],
        fees: const [],
        asAt: DateTime(2026, 1, 31),
      );
      expect(FeesService.statementCsv(account: account),
          contains('Trip to the ""big"" museum'));
    });
  });
}
