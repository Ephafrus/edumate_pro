import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../router/app_router.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';

/// Public landing page: what EduMate Pro is, and a sign-in call to action.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final scheme = Theme.of(context).colorScheme;

    return AppShell(
      title: 'EduMate Pro',
      body: ContentContainer(
        maxWidth: 1000,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text('EduMate Pro',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold, color: scheme.primary)),
            const SizedBox(height: 8),
            Text(
              'One school management platform connecting teachers, parents '
              'and school admin — enrollment applications, class management, '
              'payments and in-app messaging in one place.',
              style:
                  Theme.of(context).textTheme.titleMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go(auth.isAuthenticated
                  ? homeFor(auth.role, auth.needsProfile)
                  : Routes.login),
              icon: const Icon(Icons.login),
              label: Text(auth.isAuthenticated
                  ? 'Go to my dashboard'
                  : 'Sign in with your phone'),
            ),
            const SizedBox(height: 32),
            GridView.count(
              crossAxisCount: context.gridColumns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: context.isMobile ? 2.6 : 1.6,
              children: const [
                _FeatureCard(
                  icon: Icons.assignment_outlined,
                  title: 'Apply online',
                  text: 'Step-by-step enrollment application with document '
                      'uploads and live status tracking.',
                ),
                _FeatureCard(
                  icon: Icons.groups_outlined,
                  title: 'Classes & learners',
                  text: 'Admin manages teachers, learners, class assignment '
                      'and parent linking.',
                ),
                _FeatureCard(
                  icon: Icons.receipt_long_outlined,
                  title: 'Payments',
                  text: 'Parents submit the payment form with proof of '
                      'payment; admin reviews and approves.',
                ),
                _FeatureCard(
                  icon: Icons.chat_outlined,
                  title: 'In-app chat',
                  text: 'Staff chat with each other; parents can request a '
                      'chat with a teacher, approved by admin.',
                ),
                _FeatureCard(
                  icon: Icons.mark_email_read_outlined,
                  title: 'Email updates',
                  text: 'Parents get email notifications as applications and '
                      'payments progress.',
                ),
                _FeatureCard(
                  icon: Icons.phone_iphone,
                  title: 'Phone sign-in',
                  text: 'Everyone signs in securely with a one-time SMS code — '
                      'no passwords to remember.',
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text('Questions? Call ${Support.phone} or email ${Support.email}.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard(
      {required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: scheme.primary, size: 28),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Expanded(
              child: Text(text,
                  overflow: TextOverflow.fade,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}
