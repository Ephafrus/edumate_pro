import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Firebase Storage uploads. Uses byte uploads (`putData`) so the same code
/// path works on web, Android and iOS — callers read file bytes via
/// file_picker and hand them here.
class StorageService {
  StorageService([FirebaseStorage? storage])
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Uploads a supporting document for an enrollment application
  /// (birth certificate, immunisation card, prior report, …).
  Future<String> uploadApplicationDocument(
    String uid,
    String applicationKey,
    Uint8List bytes, {
    required String filename,
    String? contentType,
  }) {
    final ref =
        _storage.ref('applications/$uid/$applicationKey/$filename');
    return _put(ref, bytes, contentType);
  }

  /// Uploads a parent's proof of payment (receipt / bank confirmation).
  Future<String> uploadProofOfPayment(
    String uid,
    Uint8List bytes, {
    required String filename,
    String? contentType,
  }) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('paymentProofs/$uid/$stamp-$filename');
    return _put(ref, bytes, contentType);
  }

  /// Uploads a homework worksheet set by a teacher.
  Future<String> uploadHomework(
    String schoolId,
    Uint8List bytes, {
    required String filename,
    String? contentType,
  }) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('homework/$schoolId/$stamp-$filename');
    return _put(ref, bytes, contentType);
  }

  /// Uploads a school's logo.
  ///
  /// Stamped rather than fixed-named so a replacement is fetched immediately
  /// — a stable path would keep serving the old badge from the browser and
  /// CDN caches long after it was changed.
  Future<String> uploadSchoolLogo(
    String schoolId,
    Uint8List bytes, {
    required String filename,
    String? contentType,
  }) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('schoolLogos/$schoolId/$stamp-$filename');
    return _put(ref, bytes, contentType);
  }

  /// Uploads a profile photo and returns its download URL.
  Future<String> uploadProfilePhoto(
    String uid,
    Uint8List bytes, {
    String? contentType,
  }) {
    final ref = _storage.ref('profilePhotos/$uid.jpg');
    return _put(ref, bytes, contentType ?? 'image/jpeg');
  }

  Future<String> _put(
      Reference ref, Uint8List bytes, String? contentType) async {
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
    return task.ref.getDownloadURL();
  }
}
