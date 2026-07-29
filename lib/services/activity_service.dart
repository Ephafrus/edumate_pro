import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/activity_log.dart';
import 'firestore_service.dart';

/// Records what people do in the app to an append-only audit trail that a
/// Super Admin reviews.
///
/// Logging is deliberately **fire-and-forget**: a failed or slow write must
/// never block or break the action the user was performing, so [log] returns
/// immediately and swallows errors. [actor] is kept up to date by
/// `AuthController`, so any screen can log with one line.
class ActivityService {
  ActivityService(this._db);

  final FirestoreService _db;

  /// Who is acting — set on sign-in and whenever the active school changes.
  ActivityActor? actor;

  /// Records an interaction. Safe to call from anywhere, including build
  /// callbacks and `initState`.
  void log(
    ActivityAction action, {
    String target = '',
    String details = '',
    ActivityActor? as,
  }) {
    final who = as ?? actor;
    if (who == null) return; // not signed in yet — nothing to attribute
    final entry = ActivityLog(
      id: '',
      action: action,
      actorUid: who.uid,
      actorName: who.name,
      actorRole: who.role,
      schoolId: who.schoolId,
      schoolName: who.schoolName,
      target: target,
      details: details,
    );
    // Intentionally not awaited — logging must never delay or break the
    // action it describes.
    unawaited(_safeWrite(entry));
  }

  Future<void> _safeWrite(ActivityLog entry) async {
    try {
      await _db.writeActivityLog(entry);
    } catch (e) {
      // Most often the Firestore rules have not been deployed yet. Never
      // rethrow: an audit-trail failure must stay invisible to the user.
      if (kDebugMode) debugPrint('activity log skipped: $e');
    }
  }

  /// Convenience for screen-open tracking.
  void logPage(String pageName) =>
      log(ActivityAction.pageViewed, target: pageName);
}
