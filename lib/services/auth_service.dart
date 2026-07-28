import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// A handle to an in-progress phone verification. On web it wraps a
/// [ConfirmationResult]; on mobile it carries the `verificationId` returned by
/// `verifyPhoneNumber`. [AuthService.confirmPhoneCode] consumes it.
class PhoneVerification {
  PhoneVerification.web(this.confirmationResult) : verificationId = null;
  PhoneVerification.mobile(this.verificationId) : confirmationResult = null;

  final ConfirmationResult? confirmationResult;
  final String? verificationId;
}

/// All Firebase Auth interactions, isolated from Firestore/UI.
///
/// EduMate Pro uses **phone number + OTP** (Firebase Phone Auth) for every
/// role — admin, teacher and parent alike. The role comes from the
/// `users/{uid}` record (or a staff invite) after sign-in.
class AuthService {
  AuthService([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// Starts phone verification and returns a handle. On mobile this waits for
  /// the `codeSent` callback (or surfaces a failure); on web it triggers the
  /// reCAPTCHA + SMS flow immediately.
  Future<PhoneVerification> startPhoneVerification(String phone) async {
    final e164 = toE164(phone);
    if (kIsWeb) {
      final result = await _auth.signInWithPhoneNumber(e164);
      return PhoneVerification.web(result);
    }

    final completer = Completer<PhoneVerification>();
    await _auth.verifyPhoneNumber(
      phoneNumber: e164,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Android may auto-retrieve the SMS code; sign in directly.
        if (!completer.isCompleted) {
          await _auth.signInWithCredential(credential);
          completer.complete(PhoneVerification.mobile(null));
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!completer.isCompleted) {
          completer.complete(PhoneVerification.mobile(verificationId));
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return completer.future;
  }

  /// Completes phone sign-in with the SMS code the user entered.
  Future<UserCredential> confirmPhoneCode(
      PhoneVerification verification, String smsCode) {
    if (verification.confirmationResult != null) {
      return verification.confirmationResult!.confirm(smsCode);
    }
    final credential = PhoneAuthProvider.credential(
      verificationId: verification.verificationId!,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<void> signOut() => _auth.signOut();

  /// Normalises a South African cell number to E.164 (+27...). Leaves already
  /// international numbers untouched. Also used to key staff invites so an
  /// admin-entered number matches the number Firebase reports at sign-in.
  static String toE164(String raw) {
    var s = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (s.startsWith('+')) return s;
    if (s.startsWith('0')) return '+27${s.substring(1)}';
    if (s.startsWith('27')) return '+$s';
    return '+27$s';
  }
}
