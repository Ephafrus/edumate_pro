// Smoke tests that don't require a live Firebase backend.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:edumate_pro/core/id_validation.dart';
import 'package:edumate_pro/models/attendance.dart';
import 'package:edumate_pro/models/app_user.dart';
import 'package:edumate_pro/models/enums.dart';
import 'package:edumate_pro/models/school.dart';
import 'package:edumate_pro/services/auth_service.dart';
import 'package:edumate_pro/services/firestore_service.dart';

void main() {
  group('SA ID validation', () {
    test('valid when 13 digits and first 6 (YYMMDD) match the DOB', () {
      expect(
        IdValidation.validate(
            IdType.saId, '9307295490082', DateTime(1993, 7, 29)),
        isNull,
      );
    });

    test('invalid when the date part does not match the DOB', () {
      expect(
        IdValidation.validate(
            IdType.saId, '9307295490082', DateTime(1990, 1, 1)),
        isNotNull,
      );
    });

    test('invalid when not exactly 13 digits', () {
      expect(
        IdValidation.validate(
            IdType.saId, '93072954900', DateTime(1993, 7, 29)),
        isNotNull,
      );
    });

    test('passport accepts any non-empty text', () {
      expect(IdValidation.validate(IdType.passport, 'AB123456', null), isNull);
      expect(IdValidation.validate(IdType.passport, '  ', null), isNotNull);
    });

    test('decodes gender from digits 7–10', () {
      expect(IdValidation.genderFromSaId('9307295490082'), Gender.male);
      expect(IdValidation.genderFromSaId('9307294490087'), Gender.female);
      expect(IdValidation.genderFromSaId('12345'), isNull);
    });
  });

  group('Phone normalisation (E.164)', () {
    test('normalises local SA numbers', () {
      expect(AuthService.toE164('072 123 4567'), '+27721234567');
      expect(AuthService.toE164('0721234567'), '+27721234567');
    });

    test('keeps international numbers', () {
      expect(AuthService.toE164('+27721234567'), '+27721234567');
      expect(AuthService.toE164('27721234567'), '+27721234567');
    });
  });

  group('Attendance QR payload', () {
    test('round-trips a learner id', () {
      final data = AttendanceRecord.qrData('abc123');
      expect(AttendanceRecord.learnerIdFromQr(data), 'abc123');
    });

    test('rejects foreign or empty codes', () {
      expect(AttendanceRecord.learnerIdFromQr('https://example.com'), isNull);
      expect(AttendanceRecord.learnerIdFromQr(null), isNull);
      expect(AttendanceRecord.learnerIdFromQr('edumate-learner:'), isNull);
    });
  });

  group('Enum round-trips tolerate unknown values', () {
    test('UserRole defaults to parent', () {
      expect(UserRole.fromString('nonsense'), UserRole.parent);
      expect(UserRole.fromString('admin'), UserRole.admin);
      expect(UserRole.fromString('teacher'), UserRole.teacher);
    });

    test('ApplicationStatus defaults to draft', () {
      expect(ApplicationStatus.fromString(null), ApplicationStatus.draft);
      expect(ApplicationStatus.fromString('underReview'),
          ApplicationStatus.underReview);
    });

    test('PaymentStatus defaults to pending', () {
      expect(PaymentStatus.fromString('x'), PaymentStatus.pending);
      expect(PaymentStatus.fromString('approved'), PaymentStatus.approved);
    });

    test('ChatApproval defaults to requested', () {
      expect(ChatApproval.fromString(null), ChatApproval.requested);
      expect(ChatApproval.fromString('approved'), ChatApproval.approved);
    });
  });

  group('Teacher options', () {
    test('a member carries a uid and no invite id', () {
      final option = TeacherOption.member(const SchoolMembership(
        schoolId: 's1',
        uid: 'u1',
        role: UserRole.teacher,
        firstName: 'Thandi',
        lastName: 'Mokoena',
      ));
      expect(option.uid, 'u1');
      expect(option.inviteId, isNull);
      expect(option.pending, isFalse);
      expect(option.label, contains('Thandi Mokoena'));
    });

    test('an unclaimed invite carries an invite id and no uid', () {
      final option = TeacherOption.invite(const StaffInvite(
        id: 'inv1',
        phone: '+27721234567',
        role: UserRole.teacher,
        schoolId: 's1',
        firstName: 'Sipho',
        lastName: 'Dlamini',
      ));
      expect(option.uid, isNull);
      expect(option.inviteId, 'inv1');
      expect(option.pending, isTrue);
      expect(option.label, contains('awaiting first sign-in'));
    });

    test('an invite with no name falls back to the phone number', () {
      final option = TeacherOption.invite(const StaffInvite(
        id: 'inv2',
        phone: '+27721234567',
        role: UserRole.teacher,
        schoolId: 's1',
      ));
      expect(option.name, '+27721234567');
    });
  });

  group('combineLatest2', () {
    test('waits for both sources, then emits on either', () async {
      final a = StreamController<int>();
      final b = StreamController<String>();
      final seen = <String>[];
      final sub =
          combineLatest2(a.stream, b.stream, (int x, String y) => '$x$y')
              .listen(seen.add);

      a.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty, reason: 'nothing until both have a value');

      b.add('a');
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['1a']);

      a.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['1a', '2a']);

      await sub.cancel();
      await a.close();
      await b.close();
    });
  });
}
