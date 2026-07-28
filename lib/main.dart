import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool firebaseReady = true;
  String? initError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    // Most commonly the placeholder firebase_options.dart — surface a helpful
    // screen instead of a crash. Replace via `flutterfire configure`.
    firebaseReady = false;
    initError = e.toString();
  }

  runApp(EduMateApp(firebaseReady: firebaseReady, initError: initError));
}
