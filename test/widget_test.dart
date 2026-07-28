// Smoke tests that don't require a live Firebase backend.
import 'package:flutter_test/flutter_test.dart';
import 'package:edumate_pro/core/id_validation.dart';
import 'package:edumate_pro/models/enums.dart';
import 'package:edumate_pro/services/auth_service.dart';

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
}
