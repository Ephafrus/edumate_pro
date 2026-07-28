import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../models/enums.dart';
import '../router/app_router.dart';
import '../state/auth_controller.dart';

class NavItem {
  const NavItem(this.label, this.route);
  final String label;
  final String route;
}

/// Responsive navigation scaffold shared by every screen. On wide viewports
/// the nav links sit inline in the app bar; on mobile they collapse into a
/// drawer. The EduMate Pro brand and footer appear on every page.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.body,
    this.breadcrumb,
    this.scrollable = true,
  });

  final String title;
  final Widget body;
  final String? breadcrumb;

  /// Chat screens manage their own scrolling; set false to fill the viewport.
  final bool scrollable;

  List<NavItem> _navItems(AuthController auth) {
    if (!auth.isAuthenticated) {
      return const [
        NavItem('Home', Routes.landing),
        NavItem('Sign in', Routes.login),
      ];
    }
    if (auth.needsProfile) {
      return const [NavItem('My profile', Routes.profile)];
    }
    switch (auth.role) {
      case UserRole.parent:
        return const [
          NavItem('Home', Routes.parentHome),
          NavItem('Apply', Routes.apply),
          NavItem('Payments', Routes.parentPayments),
          NavItem('Messages', Routes.chats),
          NavItem('My profile', Routes.profile),
        ];
      case UserRole.teacher:
        return const [
          NavItem('My classes', Routes.teacherHome),
          NavItem('Scan', Routes.scan),
          NavItem('Messages', Routes.chats),
          NavItem('My profile', Routes.profile),
        ];
      case UserRole.admin:
        return const [
          NavItem('Dashboard', Routes.adminHome),
          NavItem('Scan', Routes.scan),
          NavItem('Applications', Routes.adminApplications),
          NavItem('Learners', Routes.adminLearners),
          NavItem('Classes', Routes.adminClasses),
          NavItem('Staff', Routes.adminStaff),
          NavItem('Payments', Routes.adminPayments),
          NavItem('Messages', Routes.chats),
        ];
      case null:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final items = _navItems(auth);
    final isDesktop = context.isDesktop;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: () => context.go(
            auth.isAuthenticated
                ? homeFor(auth.role, auth.needsProfile)
                : Routes.landing,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school, size: 24),
              SizedBox(width: 8),
              Text('EduMate Pro',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          if (isDesktop)
            ...items.map((it) => TextButton(
                  onPressed: () => context.go(it.route),
                  child: Text(it.label),
                )),
          IconButton(
            tooltip: 'Appearance',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => context.go(Routes.settings),
          ),
          if (auth.isAuthenticated)
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await context.read<AuthController>().signOut();
                if (context.mounted) context.go(Routes.landing);
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: isDesktop ? null : _NavDrawer(items: items, auth: auth),
      body: Column(
        children: [
          if (breadcrumb != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(breadcrumb!,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          Expanded(
            child: scrollable ? SingleChildScrollView(child: body) : body,
          ),
          const _Footer(),
        ],
      ),
    );
  }
}

class _NavDrawer extends StatelessWidget {
  const _NavDrawer({required this.items, required this.auth});
  final List<NavItem> items;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final user = auth.appUser;
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            DrawerHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.school),
                      SizedBox(width: 8),
                      Text('EduMate Pro',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (user != null) ...[
                    const SizedBox(height: 8),
                    Text(user.fullName,
                        style: Theme.of(context).textTheme.bodyMedium),
                    Text(user.role.label,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey)),
                  ],
                ],
              ),
            ),
            ...items.map((it) => ListTile(
                  title: Text(it.label),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.go(it.route);
                  },
                )),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Text('Connecting teachers, parents & school admin',
                style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            Text('© ${DateTime.now().year} EduMate Pro',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
