import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/activity_log.dart';
import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/school.dart';
import '../services/activity_service.dart';
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
    required ActivityService activity,
  })  : _auth = authService,
        _db = firestore,
        _activity = activity {
    _sub = _auth.authStateChanges.listen(_onAuthStateChanged);
  }

  final AuthService _auth;
  final FirestoreService _db;
  final ActivityService _activity;
  StreamSubscription<User?>? _sub;

  /// Live subscription to this user's school memberships, so a school
  /// assigned by a Super Admin (or a teacher invite claimed elsewhere)
  /// appears immediately, without needing to sign out and back in.
  StreamSubscription<List<SchoolMembership>>? _membershipSub;

  AppUser? _appUser;
  List<SchoolMembership> _memberships = const [];

  /// A Super Admin who has signed in to a specific school to run it. They
  /// hold no membership there — this is an explicit, audited oversight mode,
  /// shown with a persistent banner and exited with one tap.
  School? _viewingSchool;
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

  /// The school a Super Admin is currently working inside, if any.
  School? get viewingSchool => _viewingSchool;
  bool get isViewingSchool => isSuperAdmin && _viewingSchool != null;

  /// A Super Admin signs in to a school to see and manage it exactly as its
  /// admin would. Audited on both entry and exit.
  Future<void> enterSchool(School school) async {
    if (!isSuperAdmin) return;
    _viewingSchool = school;
    _db.activeSchoolId = school.id;
    _refreshActor();
    _activity.log(ActivityAction.schoolViewed,
        target: school.name, details: 'Super Admin oversight');
    notifyListeners();
  }

  /// Returns to the platform console.
  Future<void> exitSchool() async {
    final left = _viewingSchool;
    _viewingSchool = null;
    _db.activeSchoolId = activeMembership?.schoolId;
    _refreshActor();
    if (left != null) {
      _activity.log(ActivityAction.schoolViewExited, target: left.name);
    }
    notifyListeners();
  }

  /// The membership for the school currently being worked in.
  SchoolMembership? get activeMembership {
    if (_memberships.isEmpty) return null;
    final id = _appUser?.activeSchoolId;
    for (final m in _memberships) {
      if (m.schoolId == id) return m;
    }
    return _memberships.first;
  }

  String? get activeSchoolId =>
      _viewingSchool?.id ?? activeMembership?.schoolId;
  String get activeSchoolName =>
      _viewingSchool?.name ?? activeMembership?.schoolName ?? '';

  /// Role **at the active school** — drives navigation and permissions. A
  /// Super Admin inside a school acts with admin rights there.
  UserRole? get role =>
      isViewingSchool ? UserRole.admin : activeMembership?.role;

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
    if (isViewingSchool) return '/admin';
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

    // A brand-new deployment has nobody in charge yet. The first person to
    // sign in claims the platform and becomes its Super Admin; everyone
    // after that is a parent unless a Super Admin assigns them an admin /
    // principal role, or a school admin invites them as a teacher.
    final claimed = await _db.claimPlatformBootstrap(user.uid);

    final newUser = AppUser(
      uid: user.uid,
      role: UserRole.parent,
      phone: user.phoneNumber,
      superAdmin: claimed,
    );
    await _db.upsertUser(newUser);
    final created = await _db.getUser(user.uid);
    if (claimed && created != null) {
      _activity.log(
        ActivityAction.platformBootstrapped,
        target: created.phone ?? created.uid,
        details: 'first sign-in became Super Admin',
        as: ActivityActor.forUser(
          uid: created.uid,
          name: created.fullName,
          superAdmin: true,
        ),
      );
    }
    return created;
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
  /// active one, then keeps watching so later changes arrive live.
  Future<void> _loadMemberships(String uid) async {
    try {
      _memberships = await _db.getMembershipsForUser(uid);
    } catch (_) {
      _memberships = const [];
    }
    await _applyActiveSchool(uid);
    _watchMemberships(uid);
  }

  /// Subscribes to membership changes. When a Super Admin assigns this user
  /// to a school, or a school admin promotes them, the app picks it up
  /// straight away and the router moves them out of "choose a school".
  void _watchMemberships(String uid) {
    _membershipSub?.cancel();
    _membershipSub = _db.watchMembershipsForUser(uid).listen((list) async {
      final hadNone = _memberships.isEmpty;
      _memberships = list;
      await _applyActiveSchool(uid);
      if (hadNone && list.isNotEmpty) {
        _refreshActor();
        _activity.log(ActivityAction.memberAssigned,
            target: list.first.schoolName,
            details: 'joined as ${list.first.role.label}');
      }
      notifyListeners();
    }, onError: (_) {});
  }

  /// Points the database at the active school and remembers the choice.
  Future<void> _applyActiveSchool(String uid) async {
    if (isViewingSchool) return; // oversight mode owns the active school
    final active = activeMembership;
    _db.activeSchoolId = active?.schoolId;
    _refreshActor();
    // Persist the resolved school so the next session opens where they left.
    if (active != null && _appUser?.activeSchoolId != active.schoolId) {
      try {
        await _db.updateUser(uid, {'activeSchoolId': active.schoolId});
      } catch (_) {/* non-fatal */}
      _appUser = _appUser?.copyWith(activeSchoolId: active.schoolId);
    }
  }

  /// Keeps the audit trail's "who did this" in step with the session.
  void _refreshActor() {
    final u = _appUser;
    if (u == null) {
      _activity.actor = null;
      return;
    }
    final m = activeMembership;
    _activity.actor = ActivityActor.forUser(
      uid: u.uid,
      name: u.fullName,
      superAdmin: u.superAdmin,
      role: isViewingSchool ? UserRole.admin : m?.role,
      schoolId: _viewingSchool?.id ?? m?.schoolId,
      schoolName: _viewingSchool?.name ?? m?.schoolName ?? '',
    );
  }

  /// Switches to another school this user belongs to.
  Future<void> switchSchool(String schoolId) async {
    final uid = _appUser?.uid;
    if (uid == null) return;
    if (!_memberships.any((m) => m.schoolId == schoolId)) return;
    await _db.updateUser(uid, {'activeSchoolId': schoolId});
    _appUser = _appUser?.copyWith(activeSchoolId: schoolId);
    _db.activeSchoolId = schoolId;
    _refreshActor();
    _activity.log(ActivityAction.schoolSwitched, target: activeSchoolName);
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
      _activity.log(ActivityAction.schoolJoined, target: school.name);
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
        _refreshActor();
        _activity.log(ActivityAction.signedIn,
            target: _appUser?.phone ?? '',
            details: isSuperAdmin
                ? 'Super Admin'
                : (activeMembership == null
                    ? 'no school yet'
                    : '${activeMembership!.role.label} at '
                        '${activeMembership!.schoolName}'));
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
      final wasFirstTime = !(u.profileComplete);
      await refreshAppUser();
      _activity.log(
        wasFirstTime
            ? ActivityAction.profileCreated
            : ActivityAction.profileUpdated,
        target: '${firstName.trim()} ${lastName.trim()}'.trim(),
      );
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    _activity.log(ActivityAction.signedOut);
    await _membershipSub?.cancel();
    _membershipSub = null;
    await _auth.signOut();
    _appUser = null;
    _memberships = const [];
    _viewingSchool = null;
    _db.activeSchoolId = null;
    _activity.actor = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _membershipSub?.cancel();
    super.dispose();
  }
}
