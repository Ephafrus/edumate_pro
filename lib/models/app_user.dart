import 'package:cloud_firestore/cloud_firestore.dart';

import 'enums.dart';

/// The account record stored at `users/{uid}`. Everyone signs in with phone
/// OTP; [role] (admin / teacher / parent) decides navigation and permissions.
/// Staff (admin/teacher) accounts are provisioned by an admin via a staff
/// invite keyed on the phone number; anyone else becomes a parent on first
/// sign-in and completes a short profile before applying for a child.
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
    this.broadcastsSeenAt,
    this.createdAt,
  });

  final String uid;
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

  /// When the user last opened Announcements — newer broadcasts light up
  /// the in-app notification bell.
  final DateTime? broadcastsSeenAt;
  final DateTime? createdAt;

  bool get isAdmin => role == UserRole.admin;
  bool get isTeacher => role == UserRole.teacher;
  bool get isParent => role == UserRole.parent;

  /// Admins and teachers are "staff" for chat purposes.
  bool get isStaff => isAdmin || isTeacher;

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
        broadcastsSeenAt: broadcastsSeenAt,
        createdAt: createdAt,
      );
}

/// A staff provisioning record at `staffInvites/{phoneE164}`, created by an
/// admin when adding a teacher (or another admin). When that phone number
/// first signs in, the account is created with the invited role.
class StaffInvite {
  const StaffInvite({
    required this.phone,
    required this.role,
    this.firstName = '',
    this.lastName = '',
    this.email,
    this.claimedByUid,
    this.createdAt,
  });

  /// E.164 phone number — also the document id.
  final String phone;
  final UserRole role;
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
      phone: (m['phone'] ?? doc.id) as String,
      role: UserRole.fromString(m['role'] as String?),
      firstName: (m['firstName'] ?? '') as String,
      lastName: (m['lastName'] ?? '') as String,
      email: m['email'] as String?,
      claimedByUid: m['claimedByUid'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
