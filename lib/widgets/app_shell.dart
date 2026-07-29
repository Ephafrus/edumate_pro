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
import '../models/school.dart';
import 'school_logo.dart';
import '../state/auth_controller.dart';

class NavItem {
  const NavItem(this.label, this.route, this.icon, {this.section = ''});
  final String label;
  final String route;
  final IconData icon;

  /// Optional heading this item sits under in the sidebar.
  final String section;
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
        NavItem('Home', Routes.landing, Icons.home_outlined),
        NavItem('Sign in', Routes.login, Icons.login),
      ];
    }
    if (auth.needsProfile) {
      return const [
        NavItem('My profile', Routes.profile, Icons.person_outline),
      ];
    }
    if (auth.isSuperAdmin && auth.isViewingSchool) {
      // The school's own tools, plus a way back to the platform console.
      return [
        ..._adminNav(),
        const NavItem('Platform console', Routes.superHome,
            Icons.admin_panel_settings,
            section: 'Platform'),
      ];
    }
    if (auth.isSuperAdmin) {
      return const [
        NavItem('Schools', Routes.superHome, Icons.school_outlined,
            section: 'Platform'),
        NavItem('Users', Routes.superUsers, Icons.people_outline,
            section: 'Platform'),
        NavItem('System log', Routes.superActivity, Icons.history,
            section: 'Platform'),
        NavItem('Search', Routes.search, Icons.search, section: 'Platform'),
        NavItem('My profile', Routes.profile, Icons.person_outline,
            section: 'Account'),
      ];
    }
    if (auth.needsSchool) {
      return const [
        NavItem('Choose a school', Routes.joinSchool, Icons.school_outlined),
        NavItem('My profile', Routes.profile, Icons.person_outline),
      ];
    }
    switch (auth.role) {
      case UserRole.parent:
        return const [
          NavItem('Home', Routes.parentHome, Icons.home_outlined),
          NavItem('Apply for a child', Routes.apply, Icons.assignment_add,
              section: 'Enrollment'),
          NavItem('Fees & statement', Routes.parentFees,
              Icons.account_balance_wallet_outlined,
              section: 'Finance'),
          NavItem('Payments', Routes.parentPayments,
              Icons.receipt_long_outlined,
              section: 'Finance'),
          NavItem('Calendar', Routes.calendar, Icons.calendar_month_outlined,
              section: 'School'),
          NavItem('Announcements', Routes.announcements,
              Icons.campaign_outlined,
              section: 'School'),
          NavItem('Messages', Routes.chats, Icons.chat_outlined,
              section: 'School'),
          NavItem('My profile', Routes.profile, Icons.person_outline,
              section: 'Account'),
        ];
      case UserRole.teacher:
        return const [
          NavItem('My classes', Routes.teacherHome, Icons.groups_outlined),
          NavItem('Scan attendance', Routes.scan, Icons.qr_code_scanner,
              section: 'Teaching'),
          NavItem('Search', Routes.search, Icons.search,
              section: 'Teaching'),
          NavItem('Calendar', Routes.calendar, Icons.calendar_month_outlined,
              section: 'School'),
          NavItem('Messages', Routes.chats, Icons.chat_outlined,
              section: 'School'),
          NavItem('My profile', Routes.profile, Icons.person_outline,
              section: 'Account'),
        ];
      case UserRole.admin:
      case UserRole.principal:
        return _adminNav();
      case null:
        return const [];
    }
  }

  /// The full school-admin toolset, grouped for the sidebar.
  List<NavItem> _adminNav() => const [
        NavItem('Overview', Routes.adminHome, Icons.dashboard_outlined),
        NavItem('Search', Routes.search, Icons.search),
        NavItem('Applications', Routes.adminApplications,
            Icons.assignment_outlined,
            section: 'Enrollment'),
        NavItem('Learners', Routes.adminLearners, Icons.child_care_outlined,
            section: 'People'),
        NavItem('Classes', Routes.adminClasses, Icons.meeting_room_outlined,
            section: 'People'),
        NavItem('Staff', Routes.adminStaff, Icons.badge_outlined,
            section: 'People'),
        NavItem('Users', Routes.adminUsers, Icons.people_outline,
            section: 'People'),
        NavItem('Progress reports', Routes.adminProgress,
            Icons.insights_outlined,
            section: 'Academics'),
        NavItem('Scan attendance', Routes.scan, Icons.qr_code_scanner,
            section: 'Academics'),
        NavItem('Payments', Routes.adminPayments,
            Icons.receipt_long_outlined,
            section: 'Finance'),
        NavItem('Fees', Routes.adminFees, Icons.request_quote_outlined,
            section: 'Finance'),
        NavItem('Broadcasts', Routes.adminBroadcasts, Icons.campaign_outlined,
            section: 'Communication'),
        NavItem('Messages', Routes.chats, Icons.chat_outlined,
            section: 'Communication'),
        NavItem('Chat requests', Routes.adminChatRequests,
            Icons.mark_chat_unread_outlined,
            section: 'Communication'),
        NavItem('Calendar', Routes.calendar, Icons.calendar_month_outlined,
            section: 'Communication'),
        NavItem('School settings', Routes.adminSchoolSettings,
            Icons.apartment_outlined,
            section: 'Settings'),
        NavItem('Email settings', Routes.adminEmailSettings,
            Icons.outgoing_mail,
            section: 'Settings'),
        NavItem('My profile', Routes.profile, Icons.person_outline,
            section: 'Account'),
      ];

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
      body: Row(
        children: [
          // Persistent sidebar on wide screens; the drawer covers mobile.
          if (isDesktop && items.length > 2)
            _Sidebar(items: items, auth: auth),
          Expanded(
            child: Column(
              children: [
                if (auth.isViewingSchool) const _OversightBanner(),
                if (breadcrumb != null)
                  Container(
                    width: double.infinity,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Text(breadcrumb!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                Expanded(
                  child:
                      scrollable ? SingleChildScrollView(child: body) : body,
                ),
                const _Footer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the app currently is, for highlighting the navigation.
///
/// Deliberately unable to throw. `GoRouterState.of` resolves only inside a
/// `RouteBase.builder` subtree, and a page can rebuild after go_router has
/// deregistered its state — which happens routinely during the redirects
/// that follow sign-in. When it did, the sidebar threw, an error box
/// replaced the shell, and that box blew the surrounding Row out by tens of
/// thousands of pixels: a highlight detail took down the whole window.
///
/// `GoRouter.of` is no better here — it is documented to throw during
/// redirects — so this uses `maybeOf` and settles for no highlight on the
/// rare frame where the router cannot be reached. Chrome should degrade,
/// never crash.
String currentLocation(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return '';
  return router.routeInformationProvider.value.uri.path;
}

/// Persistent, grouped navigation rail shown on wide viewports — the
/// professional "app chrome" that keeps every tool one click away instead of
/// buried behind a menu.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.auth});
  final List<NavItem> items;
  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = currentLocation(context);
    final user = auth.appUser;

    String? lastSection;
    final children = <Widget>[];
    for (final it in items) {
      if (it.section.isNotEmpty && it.section != lastSection) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 6),
          child: Text(
            it.section.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ));
        lastSection = it.section;
      }
      // Longest-prefix match so detail pages keep their parent highlighted.
      final selected = current == it.route ||
          (it.route != '/' && current.startsWith('${it.route}/'));
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Material(
          color: selected ? scheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.go(it.route),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(it.icon,
                      size: 20,
                      color: selected
                          ? scheme.onSecondaryContainer
                          : scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      it.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? scheme.onSecondaryContainer
                            : scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
    }

    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      user.firstName.isEmpty
                          ? '?'
                          : user.firstName[0].toUpperCase(),
                      style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(
                          auth.isSuperAdmin
                              ? 'Super Admin'
                              : (auth.role?.label ?? ''),
                          style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 8),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: children)),
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
      padding: const EdgeInsets.only(
          left: 6, right: 12, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The school's own badge, kept live so a logo uploaded in School
          // settings appears here without a reload.
          StreamBuilder<School?>(
            stream: context
                .read<FirestoreService>()
                .watchSchool(active.schoolId),
            builder: (context, snap) {
              final school = snap.data;
              return school == null
                  ? Icon(Icons.apartment,
                      size: 16, color: scheme.onPrimaryContainer)
                  : SchoolLogo(school: school, size: 22);
            },
          ),
          const SizedBox(width: 8),
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
                  leading: Icon(it.icon),
                  title: Text(it.label),
                  subtitle:
                      it.section.isEmpty ? null : Text(it.section),
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
