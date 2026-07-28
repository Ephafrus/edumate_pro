import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/mail_service.dart';
import 'services/storage_service.dart';
import 'state/auth_controller.dart';
import 'state/theme_controller.dart';

/// Root of the EduMate Pro app. Wires up services + controllers via Provider
/// and builds the themed, router-driven [MaterialApp].
class EduMateApp extends StatelessWidget {
  const EduMateApp({super.key, this.firebaseReady = true, this.initError});

  final bool firebaseReady;
  final String? initError;

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return _ConfigErrorApp(message: initError);
    }
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<FirestoreService>(create: (_) => FirestoreService()),
        Provider<StorageService>(create: (_) => StorageService()),
        Provider<MailService>(
            create: (ctx) => MailService(ctx.read<FirestoreService>())),
        ChangeNotifierProvider<ThemeController>(
            create: (_) => ThemeController()),
        ChangeNotifierProvider<AuthController>(
          create: (ctx) => AuthController(
            authService: ctx.read<AuthService>(),
            firestore: ctx.read<FirestoreService>(),
          ),
        ),
      ],
      child: const _AppView(),
    );
  }
}

class _AppView extends StatefulWidget {
  const _AppView();

  @override
  State<_AppView> createState() => _AppViewState();
}

class _AppViewState extends State<_AppView> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // Created once so navigation state survives theme rebuilds.
    _router = createRouter(context.read<AuthController>());
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final auth = context.watch<AuthController>();

    final lightTheme = AppTheme.build(theme.seed, Brightness.light);
    final darkTheme = AppTheme.build(theme.seed, Brightness.dark);

    // Always build MaterialApp.router — never swap between a plain MaterialApp
    // (imperative Navigator) and MaterialApp.router (Router-based history). On
    // web, swapping the navigation backend corrupts the browser history state
    // and trips an engine assertion (_currentSerialCount == 0). The startup
    // splash is shown via `builder` instead, keeping a single Router alive.
    return MaterialApp.router(
      title: 'EduMate Pro',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: theme.mode,
      routerConfig: _router,
      builder: (context, child) {
        if (!auth.initialised) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // Apply the user's chosen text size app-wide.
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(theme.textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Shown when Firebase could not initialise (e.g. placeholder config). Keeps
/// the app runnable and points the developer at setup docs.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Firebase is not configured',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Run `flutterfire configure` to generate lib/firebase_options.dart '
                  'for your project, then restart the app. See README.md.',
                  textAlign: TextAlign.center,
                ),
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Text(message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
