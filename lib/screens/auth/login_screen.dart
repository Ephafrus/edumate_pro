import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../router/app_router.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/phone_auth_form.dart';

/// Single sign-in screen for every role: phone number + SMS one-time code.
/// The role (admin / teacher / parent) is resolved from the account record
/// after verification; brand-new numbers become parent accounts.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Sign in',
      body: ContentContainer(
        maxWidth: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Icon(Icons.school,
                size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('Welcome to EduMate Pro',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Sign in with your cell phone number. New here? The same steps '
              'create your account — you can then set up a profile and apply '
              'for your child.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: PhoneAuthForm(
                  onVerified: () {
                    final auth = context.read<AuthController>();
                    context.go(homeFor(auth.role, auth.needsProfile));
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
