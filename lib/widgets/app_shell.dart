import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/app_user.dart';
import '../models/broadcast.dart';
import '../models/enums.dart';
import '../router/app_router.dart';
import '../services/firestore_service.dart';
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
    if (auth.isSuperAdmin && auth.isViewingSchool) {
      // Same tools the school's own admin has, plus a way back.
      return const [
        NavItem('Dashboard', Routes.adminHome),
        NavItem('Search', Routes.search),
        NavItem('Learners', Routes.adminLearners),
        NavItem('Applications', Routes.adminApplications),
        NavItem('Payments', Routes.adminPayments),
        NavItem('Fees', Routes.adminFees),
        NavItem('Platform console', Routes.superHome),
      ];
    }
    if (auth.isSuperAdmin) {
      return const [
        NavItem('Schools', Routes.superHome),
        NavItem('Users', Routes.superUsers),
        NavItem('System log', Routes.superActivity),
        NavItem('Search', Routes.search),
        NavItem('My profile', Routes.profile),
      ];
    }
    if (auth.needsSchool) {
      return const [
        NavItem('Choose a school', Routes.joinSchool),
        NavItem('My profile', Routes.profile),
      ];
    }
    switch (auth.role) {
      case UserRole.parent:
        return const [
          NavItem('Home', Routes.parentHome),
          NavItem('Apply', Routes.apply),
          NavItem('Payments', Routes.parentPayments),
          NavItem('Calendar', Routes.calendar),
          NavItem('Messages', Routes.chats),
          NavItem('My profile', Routes.profile),
        ];
      case UserRole.teacher:
        return const [
          NavItem('My classes', Routes.teacherHome),
          NavItem('Search', Routes.search),
          NavItem('Scan', Routes.scan),
          NavItem('Calendar', Routes.calendar),
          NavItem('Messages', Routes.chats),
          NavItem('My profile', Routes.profile),
        ];
      case UserRole.admin:
      case UserRole.principal:
        // The rest of the admin area (classes, staff, broadcasts, calendar,
        // email settings, chat requests) is reached from dashboard tiles.
        return const [
          NavItem('Dashboard', Routes.adminHome),
          NavItem('Search', Routes.search),
          NavItem('Learners', Routes.adminLearners),
          NavItem('Applications', Routes.adminApplications),
          NavItem('Payments', Routes.adminPayments),
          NavItem('Fees', Routes.adminFees),
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
            auth.isAuthenticated ? auth.homePath : Routes.landing,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: Theme.of(context).colorScheme.heroGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.school,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text('EduMate Pro',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        actions: [
          if (isDesktop && auth.memberships.isNotEmpty)
            const _SchoolSwitcher(),
          if (isDesktop)
            ...items.map((it) => TextButton(
                  onPressed: () => context.go(it.route),
                  child: Text(it.label),
                )),
          if (auth.isAuthenticated && auth.appUser != null)
            _AnnouncementsBell(user: auth.appUser!),
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
          if (auth.isViewingSchool) const _OversightBanner(),
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

/// Persistent reminder that a Super Admin is working inside a school rather
/// than as its staff, with a one-tap way back to the platform console.
class _OversightBanner extends StatelessWidget {
  const _OversightBanner();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final school = auth.viewingSchool;
    if (school == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.visibility,
                size: 18, color: scheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Signed in to ${school.name} as Super Admin — actions here '
                'are recorded in the system log.',
                style: TextStyle(
                    color: scheme.onTertiaryContainer, fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await context.read<AuthController>().exitSchool();
                if (context.mounted) context.go(Routes.superHome);
              },
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Exit school'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the school the user is currently working in. When they belong to
/// more than one — an admin, principal or teacher assigned to several
/// schools — it becomes a menu for switching between them.
class _SchoolSwitcher extends StatelessWidget {
  const _SchoolSwitcher();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final active = auth.activeMembership;
    if (active == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    final label = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.apartment, size: 16, color: scheme.onPrimaryContainer),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              active.schoolName.isEmpty ? 'My school' : active.schoolName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ),
          if (auth.hasMultipleSchools)
            Icon(Icons.arrow_drop_down,
                size: 18, color: scheme.onPrimaryContainer),
        ],
      ),
    );

    if (!auth.hasMultipleSchools) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Tooltip(message: active.role.label, child: label),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: PopupMenuButton<String>(
        tooltip: 'Switch school',
        onSelected: (id) async {
          await context.read<AuthController>().switchSchool(id);
          if (context.mounted) context.go(context.read<AuthController>().homePath);
        },
        itemBuilder: (_) => auth.memberships
            .map((m) => PopupMenuItem<String>(
                  value: m.schoolId,
                  child: Row(
                    children: [
                      Icon(
                        m.schoolId == active.schoolId
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.schoolName.isEmpty
                              ? 'School'
                              : m.schoolName),
                          Text(m.role.label,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ))
            .toList(),
        child: label,
      ),
    );
  }
}

/// In-app broadcast notification bell: lights up with the number of
/// announcements newer than the user's last visit to the feed.
class _AnnouncementsBell extends StatelessWidget {
  const _AnnouncementsBell({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    return StreamBuilder<List<Broadcast>>(
      stream: db.watchBroadcastsForUser(user.uid, limit: 20),
      builder: (context, snap) {
        final seen = user.broadcastsSeenAt ?? DateTime(2000);
        final unread = (snap.data ?? [])
            .where((b) => (b.createdAt ?? DateTime(2000)).isAfter(seen))
            .length;
        final button = IconButton(
          tooltip: 'Announcements',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => context.go(Routes.announcements),
        );
        if (unread == 0) return button;
        return Badge.count(
          count: unread,
          offset: const Offset(-6, 6),
          child: button,
        );
      },
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
              decoration: BoxDecoration(
                gradient: Theme.of(context).colorScheme.heroGradient,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.school, color: Colors.white),
                      SizedBox(width: 8),
                      Text('EduMate Pro',
                          style: TextStyle(
                              fontSize: 20,
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  if (user != null) ...[
                    const SizedBox(height: 8),
                    Text(user.fullName,
                        style: const TextStyle(color: Colors.white)),
                    Text(user.role.label,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
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
