import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/school.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// Central auth state. Bridges Firebase Phone Auth, the global `users/{uid}`
/// record and the user's **school memberships**, so the router and UI can
/// reason about which school they are in, their role there, and profile
/// completeness.
///
/// Everyone signs in with phone OTP. On every sign-in the controller claims
/// any outstanding staff invites for that phone number — which is how a
/// Super Admin's school assignment, or a school admin's teacher invite,
/// turns into a membership. A person assigned to several schools ends up
/// with several memberships and can switch between them from the app bar.
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
  List<SchoolMembership> _memberships = const [];
  bool _initialised = false;
  bool _busy = false;
  String? _error;

  AppUser? get appUser => _appUser;
  bool get initialised => _initialised;
  bool get busy => _busy;
  String? get error => _error;

  bool get isAuthenticated => _auth.currentUser != null;

  /// Every school this user belongs to (admin, principal, teacher or
  /// parent) — the school switcher lists these.
  List<SchoolMembership> get memberships => _memberships;
  bool get hasMultipleSchools => _memberships.length > 1;

  /// Platform-level Super Admin: sets schools up and assigns their admins.
  bool get isSuperAdmin => _appUser?.superAdmin ?? false;

  /// The membership for the school currently being worked in.
  SchoolMembership? get activeMembership {
    if (_memberships.isEmpty) return null;
    final id = _appUser?.activeSchoolId;
    for (final m in _memberships) {
      if (m.schoolId == id) return m;
    }
    return _memberships.first;
  }

  String? get activeSchoolId => activeMembership?.schoolId;
  String get activeSchoolName => activeMembership?.schoolName ?? '';

  /// Role **at the active school** — drives navigation and permissions.
  UserRole? get role => activeMembership?.role;

  /// A signed-in user who belongs to no school yet: parents pick one to
  /// apply to; staff wait for their school to invite them. Super Admins
  /// work above schools, so this never applies to them.
  bool get needsSchool =>
      isAuthenticated && _appUser != null && !isSuperAdmin && _memberships.isEmpty;

  /// Parents complete a short profile (name + email for notifications) before
  /// they can apply for a child. Staff profiles come from their invite.
  bool get needsProfile =>
      isAuthenticated && _appUser != null && !_appUser!.profileComplete;

  /// Where this user belongs right now: profile → school → their role's
  /// home (or the Super Admin console).
  String get homePath {
    if (!isAuthenticated) return '/login';
    if (needsProfile) return '/profile';
    if (isSuperAdmin) return '/super';
    if (needsSchool) return '/join';
    switch (role) {
      case UserRole.parent:
        return '/parent';
      case UserRole.teacher:
        return '/teacher';
      case UserRole.admin:
      case UserRole.principal:
        return '/admin';
      case null:
        return '/join';
    }
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      _appUser = null;
      _memberships = const [];
      _db.activeSchoolId = null;
    } else {
      _appUser = await _ensureUserRecord(user);
      await _claimInvites(user);
      await _loadMemberships(user.uid);
    }
    _initialised = true;
    notifyListeners();
  }

  /// Loads the global user record, creating it on first sign-in. The role
  /// stored here is only a cache of the active school's role — membership is
  /// the source of truth.
  Future<AppUser?> _ensureUserRecord(User user) async {
    final existing = await _db.getUser(user.uid);
    if (existing != null) return existing;

    final newUser = AppUser(
      uid: user.uid,
      role: UserRole.parent,
      phone: user.phoneNumber,
    );
    await _db.upsertUser(newUser);
    return _db.getUser(user.uid);
  }

  /// Turns any outstanding staff invites for this phone number into school
  /// memberships. Runs on every sign-in, so somebody already using the app
  /// picks up a **new** school the moment they are assigned to it.
  Future<void> _claimInvites(User user) async {
    final phone = user.phoneNumber;
    if (phone == null) return;
    try {
      final invites = await _db.getStaffInvitesForPhone(phone);
      if (invites.isEmpty) return;
      final profile = _appUser;
      for (final invite in invites) {
        await _db.setMembership(SchoolMembership(
          schoolId: invite.schoolId,
          schoolName: invite.schoolName,
          uid: user.uid,
          role: invite.role,
          firstName: profile?.firstName.isNotEmpty == true
              ? profile!.firstName
              : invite.firstName,
          lastName: profile?.lastName.isNotEmpty == true
              ? profile!.lastName
              : invite.lastName,
          phone: phone,
          email: profile?.email ?? invite.email,
        ));
        await _db.markInviteClaimed(invite.id, user.uid);
      }
      // Staff arrive pre-named from their invite; parents fill in a profile.
      final named = invites.firstWhere((i) => i.fullName.isNotEmpty,
          orElse: () => invites.first);
      if (profile != null && !profile.profileComplete && named.fullName.isNotEmpty) {
        await _db.updateUser(user.uid, {
          'firstName': named.firstName,
          'lastName': named.lastName,
          if (named.email != null) 'email': named.email,
          'profileComplete': true,
        });
        _appUser = await _db.getUser(user.uid);
      }
    } catch (_) {
      // An unreadable/denied invite must never block sign-in.
    }
  }

  /// Loads every school this user belongs to and points the database at the
  /// active one.
  Future<void> _loadMemberships(String uid) async {
    try {
      _memberships = await _db.getMembershipsForUser(uid);
    } catch (_) {
      _memberships = const [];
    }
    final active = activeMembership;
    _db.activeSchoolId = active?.schoolId;
    // Persist the resolved school so the next session opens where they left.
    if (active != null && _appUser?.activeSchoolId != active.schoolId) {
      await _db.updateUser(uid, {'activeSchoolId': active.schoolId});
      _appUser = _appUser?.copyWith(activeSchoolId: active.schoolId);
    }
  }

  /// Switches to another school this user belongs to.
  Future<void> switchSchool(String schoolId) async {
    final uid = _appUser?.uid;
    if (uid == null) return;
    if (!_memberships.any((m) => m.schoolId == schoolId)) return;
    await _db.updateUser(uid, {'activeSchoolId': schoolId});
    _appUser = _appUser?.copyWith(activeSchoolId: schoolId);
    _db.activeSchoolId = schoolId;
    notifyListeners();
  }

  /// A parent joins a school so they can apply for a child there. Parents
  /// self-serve; staff are assigned by a Super Admin or school admin.
  Future<bool> joinSchoolAsParent(School school) async {
    final u = _appUser;
    if (u == null) return false;
    _setBusy(true);
    try {
      await _db.setMembership(SchoolMembership(
        schoolId: school.id,
        schoolName: school.name,
        uid: u.uid,
        role: UserRole.parent,
        firstName: u.firstName,
        lastName: u.lastName,
        phone: u.phone,
        email: u.email,
      ));
      await _loadMemberships(u.uid);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> refreshAppUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      _appUser = null;
      _memberships = const [];
      _db.activeSchoolId = null;
    } else {
      _appUser = await _db.getUser(user.uid);
      await _loadMemberships(user.uid);
    }
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

  /// Confirms the SMS code, then resolves the account: create the user
  /// record if new, claim any school invites, and load memberships.
  Future<bool> confirmPhoneCode(
      PhoneVerification verification, String code) async {
    _setBusy(true);
    try {
      final cred = await _auth.confirmPhoneCode(verification, code);
      // The auth-state listener races with us; resolve everything here so
      // routing already sees the right school and role.
      final user = cred.user;
      if (user != null) {
        _appUser = await _ensureUserRecord(user);
        await _claimInvites(user);
        await _loadMemberships(user.uid);
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
      // Keep each school's directory entry in step with the profile.
      for (final m in _memberships) {
        await _db.setMembership(SchoolMembership(
          schoolId: m.schoolId,
          schoolName: m.schoolName,
          uid: u.uid,
          role: m.role,
          firstName: firstName.trim(),
          lastName: lastName.trim(),
          phone: u.phone,
          email: email.trim(),
          active: m.active,
        ));
      }
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
