import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// The **global** account record stored at `users/{uid}` — one per person,
/// across every school. Everyone signs in with phone OTP.
///
/// Which school(s) they belong to, and as what, lives in their memberships
/// (`schools/{schoolId}/members/{uid}`), not here: a person can be an admin
/// at one school and a teacher at another. [role] is the role at their
/// currently active school, resolved by `AuthController` when the user is
/// loaded (and cached on the document so directory lookups have something
/// sensible to show).
class AppUser {
  const AppUser({
    required this.uid,
    required this.role,
    this.phone,
    this.email,
    this.firstName = '',
    this.lastName = '',
    this.photoUrl,
    this.address = '',
    this.profileComplete = false,
    this.active = true,
    this.superAdmin = false,
    this.activeSchoolId,
    this.broadcastsSeenAt,
    this.createdAt,
  });

  final String uid;

  /// Role at [activeSchoolId] — see the class doc.
  final UserRole role;
  final String? phone;

  /// Email used for SMTP notifications (parents) and shown in staff directory.
  final String? email;
  final String firstName;
  final String lastName;
  final String? photoUrl;
  final String address;

  /// Parents must complete a profile (name + email) before applying.
  final bool profileComplete;

  /// Admin can deactivate an account without deleting it.
  final bool active;

  /// Platform-level Super Admin: sets up schools and assigns the admins /
  /// principals who run them. Set outside the app (Firebase console) for the
  /// first one; Super Admins can then promote others.
  final bool superAdmin;

  /// The school this user is currently working in. They can switch to any
  /// other school they are a member of.
  final String? activeSchoolId;

  /// When the user last opened Announcements — newer broadcasts light up
  /// the in-app notification bell.
  final DateTime? broadcastsSeenAt;
  final DateTime? createdAt;

  bool get isSuperAdmin => superAdmin;
  bool get isAdmin => role == UserRole.admin;
  bool get isPrincipal => role == UserRole.principal;
  bool get isTeacher => role == UserRole.teacher;
  bool get isParent => role == UserRole.parent;

  /// Admins and principals both manage their school.
  bool get isManager => role.isManager;

  /// Managers and teachers are "staff" (chat, scanning, calendar).
  bool get isStaff => role.isStaff;

  String get fullName {
    final n = '$firstName $lastName'.trim();
    return n.isEmpty ? (phone ?? 'User') : n;
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'role': role.name,
        'phone': phone,
        'email': email,
        'firstName': firstName,
        'lastName': lastName,
        'photoUrl': photoUrl,
        'address': address,
        'profileComplete': profileComplete,
        'active': active,
        'superAdmin': superAdmin,
        'activeSchoolId': activeSchoolId,
        'broadcastsSeenAt': broadcastsSeenAt != null
            ? Timestamp.fromDate(broadcastsSeenAt!)
            : null,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return AppUser(
      uid: doc.id,
      role: UserRole.fromString(m['role'] as String?),
      phone: m['phone'] as String?,
      email: m['email'] as String?,
      firstName: (m['firstName'] ?? '') as String,
      lastName: (m['lastName'] ?? '') as String,
      photoUrl: m['photoUrl'] as String?,
      address: (m['address'] ?? '') as String,
      profileComplete: (m['profileComplete'] ?? false) as bool,
      active: (m['active'] ?? true) as bool,
      superAdmin: (m['superAdmin'] ?? false) as bool,
      activeSchoolId: m['activeSchoolId'] as String?,
      broadcastsSeenAt: (m['broadcastsSeenAt'] as Timestamp?)?.toDate(),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  AppUser copyWith({
    UserRole? role,
    String? email,
    String? firstName,
    String? lastName,
    String? photoUrl,
    String? address,
    bool? profileComplete,
    bool? active,
    bool? superAdmin,
    String? activeSchoolId,
  }) =>
      AppUser(
        uid: uid,
        role: role ?? this.role,
        phone: phone,
        email: email ?? this.email,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        photoUrl: photoUrl ?? this.photoUrl,
        address: address ?? this.address,
        profileComplete: profileComplete ?? this.profileComplete,
        active: active ?? this.active,
        superAdmin: superAdmin ?? this.superAdmin,
        activeSchoolId: activeSchoolId ?? this.activeSchoolId,
        broadcastsSeenAt: broadcastsSeenAt,
        createdAt: createdAt,
      );
}

/// A staff provisioning record at `staffInvites/{id}`, created by a Super
/// Admin (assigning a school's admin/principal) or by a school admin
/// (adding a teacher). When that phone number next signs in, the invite
/// becomes a **membership of that school** with the invited role.
///
/// Invites are keyed by phone **and school**, so one person can be invited
/// to several schools and picks up every membership at once.
class StaffInvite {
  const StaffInvite({
    required this.id,
    required this.phone,
    required this.role,
    required this.schoolId,
    this.schoolName = '',
    this.firstName = '',
    this.lastName = '',
    this.email,
    this.claimedByUid,
    this.createdAt,
  });

  final String id;

  /// E.164 phone number the invitee signs in with.
  final String phone;
  final UserRole role;

  /// The school this invite grants access to.
  final String schoolId;
  final String schoolName;
  final String firstName;
  final String lastName;
  final String? email;

  /// Set once the invite has been used, so it is not applied twice.
  final String? claimedByUid;
  final DateTime? createdAt;

  bool get claimed => claimedByUid != null;
  String get fullName => '$firstName $lastName'.trim();

  Map<String, dynamic> toMap() => {
        'phone': phone,
        'role': role.name,
        'schoolId': schoolId,
        'schoolName': schoolName,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'claimedByUid': claimedByUid,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
      };

  factory StaffInvite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const {};
    return StaffInvite(
      id: doc.id,
      phone: (m['phone'] ?? '') as String,
      role: UserRole.fromString(m['role'] as String?),
      schoolId: (m['schoolId'] ?? '') as String,
      schoolName: (m['schoolName'] ?? '') as String,
      firstName: (m['firstName'] ?? '') as String,
      lastName: (m['lastName'] ?? '') as String,
      email: m['email'] as String?,
      claimedByUid: m['claimedByUid'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
