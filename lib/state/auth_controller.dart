import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/enums.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// Central auth state. Bridges Firebase Phone Auth and the `users/{uid}`
/// record so the router and UI can reason about role and profile completeness.
///
/// Everyone signs in with phone OTP. On first sign-in:
///  * if a staff invite exists for the phone number, the account is created
///    with the invited role (admin/teacher) and the invite is marked claimed;
///  * otherwise the account is created as a parent, who is then presented
///    with "create a profile" before applying for a child.
class AuthController extends ChangeNotifier {
  AuthController({
    required AuthService authService,
    required FirestoreService firestore,
  })  : _auth = authService,
        _db = firestore {
    _sub = _auth.authStateChanges.listen(_onAuthStateChanged);
  }

  final AuthService _auth;
  final FirestoreService _db;
  StreamSubscription<User?>? _sub;

  AppUser? _appUser;
  bool _initialised = false;
  bool _busy = false;
  String? _error;

  AppUser? get appUser => _appUser;
  bool get initialised => _initialised;
  bool get busy => _busy;
  String? get error => _error;

  bool get isAuthenticated => _auth.currentUser != null;
  UserRole? get role => _appUser?.role;

  /// Parents complete a short profile (name + email for notifications) before
  /// they can apply for a child. Staff profiles come from their invite.
  bool get needsProfile =>
      isAuthenticated && _appUser != null && !_appUser!.profileComplete;

  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      _appUser = null;
    } else {
      _appUser = await _ensureUserRecord(user);
    }
    _initialised = true;
    notifyListeners();
  }

  /// Loads the user record, creating it on first sign-in (consuming a staff
  /// invite when one matches the phone number).
  Future<AppUser?> _ensureUserRecord(User user) async {
    final existing = await _db.getUser(user.uid);
    if (existing != null) return existing;

    final phone = user.phoneNumber;
    StaffInvite? invite;
    if (phone != null) {
      try {
        invite = await _db.getStaffInvite(phone);
      } catch (_) {
        invite = null; // unreadable invite must not block sign-in
      }
      if (invite != null && invite.claimed) invite = null;
    }

    final newUser = AppUser(
      uid: user.uid,
      role: invite?.role ?? UserRole.parent,
      phone: phone,
      email: invite?.email,
      firstName: invite?.firstName ?? '',
      lastName: invite?.lastName ?? '',
      // Staff arrive pre-named from the invite; parents fill in a profile.
      profileComplete: invite != null && invite.fullName.isNotEmpty,
    );
    await _db.upsertUser(newUser);
    if (invite != null && phone != null) {
      await _db.markInviteClaimed(phone, user.uid);
    }
    return _db.getUser(user.uid);
  }

  Future<void> refreshAppUser() async {
    final user = _auth.currentUser;
    _appUser = user == null ? null : await _db.getUser(user.uid);
    notifyListeners();
  }

  void _setBusy(bool v) {
    _busy = v;
    if (v) _error = null;
    notifyListeners();
  }

  /// Maps Firebase phone-auth errors to clear, actionable messages. The most
  /// common gotcha in a new project is the SMS region policy: SMS is not sent
  /// until the destination region is allowed in the Firebase Console.
  String _phoneAuthError(FirebaseAuthException e) {
    final msg = (e.message ?? '').toLowerCase();
    if (msg.contains('region') ||
        e.code == 'admin-restricted-operation' ||
        msg.contains('sms unable')) {
      return 'SMS to this region is disabled on the project. A developer must '
          'allow it in Firebase Console → Authentication → Settings → SMS '
          'region policy (and add test numbers for development).';
    }
    switch (e.code) {
      case 'invalid-phone-number':
        return 'That cell phone number looks invalid. Use e.g. 072 123 4567.';
      case 'invalid-verification-code':
        return 'The SMS code is incorrect. Please re-enter it.';
      case 'session-expired':
      case 'code-expired':
        return 'The code has expired — request a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a while and try again.';
      case 'captcha-check-failed':
        return 'reCAPTCHA verification failed. Please try again.';
      case 'quota-exceeded':
        return 'The daily SMS quota has been exceeded. Please try later.';
      case 'billing-not-enabled':
        return 'SMS sending requires the Firebase Blaze (pay-as-you-go) plan.';
      case 'operation-not-allowed':
        return 'Phone sign-in is not enabled (Firebase Console → Authentication '
            '→ Sign-in method → Phone).';
      default:
        return e.message ?? e.code;
    }
  }

  /// Starts phone verification (sign-up and login are the same flow).
  Future<PhoneVerification?> startPhoneVerification(String phone) async {
    _setBusy(true);
    try {
      return await _auth.startPhoneVerification(phone);
    } on FirebaseAuthException catch (e) {
      _error = _phoneAuthError(e);
      return null;
    } finally {
      _setBusy(false);
    }
  }

  /// Confirms the SMS code; `_onAuthStateChanged` then ensures the user
  /// record exists (applying a staff invite if one matches).
  Future<bool> confirmPhoneCode(
      PhoneVerification verification, String code) async {
    _setBusy(true);
    try {
      final cred = await _auth.confirmPhoneCode(verification, code);
      // The auth-state listener races with us; make sure the record exists
      // before reporting success so routing sees the right role.
      final user = cred.user;
      if (user != null) {
        _appUser = await _ensureUserRecord(user);
      }
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _phoneAuthError(e);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Saves the signed-in user's profile (parents: required before applying).
  Future<bool> saveProfile({
    required String firstName,
    required String lastName,
    required String email,
    String address = '',
  }) async {
    final u = _appUser;
    if (u == null) return false;
    _setBusy(true);
    try {
      await _db.updateUser(u.uid, {
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'email': email.trim(),
        'address': address.trim(),
        'profileComplete': true,
      });
      await refreshAppUser();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _appUser = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
