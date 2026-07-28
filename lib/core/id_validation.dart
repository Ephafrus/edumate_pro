import '../models/enums.dart';

/// Validation for government identity numbers captured on the profile form.
///
/// - **South African ID:** exactly 13 numeric digits, whose first 6 encode the
///   date of birth as `YYMMDD` and must match the captured date of birth.
/// - **Passport:** any non-empty text is accepted.
class IdValidation {
  /// Returns an error message, or null if valid.
  static String? validate(IdType? type, String number, DateTime? dob) {
    if (type == null) return 'Select an ID type';
    final trimmed = number.trim();
    if (trimmed.isEmpty) return 'ID / passport number is required';
    switch (type) {
      case IdType.saId:
        return _validateSaId(trimmed, dob);
      case IdType.passport:
        return null; // any text allowed
    }
  }

  static String? _validateSaId(String id, DateTime? dob) {
    if (!RegExp(r'^\d{13}$').hasMatch(id)) {
      return 'A South African ID must be exactly 13 digits';
    }
    if (dob == null) {
      return 'Date of birth is required for a South African ID';
    }
    final yy = dob.year % 100;
    final expected =
        '${_pad2(yy)}${_pad2(dob.month)}${_pad2(dob.day)}'; // YYMMDD
    if (id.substring(0, 6) != expected) {
      return 'The first 6 digits (YYMMDD) must match the date of birth';
    }
    return null;
  }

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  /// Decodes gender from a South African ID number. Digits 7–10 (`SSSS`) encode
  /// a sequence: 0000–4999 is female, 5000–9999 is male. Returns null if the
  /// number is not 13 digits.
  static Gender? genderFromSaId(String id) {
    final trimmed = id.trim();
    if (!RegExp(r'^\d{13}$').hasMatch(trimmed)) return null;
    final ssss = int.parse(trimmed.substring(6, 10));
    return ssss < 5000 ? Gender.female : Gender.male;
  }
}
