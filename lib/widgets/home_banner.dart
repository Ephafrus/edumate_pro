import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/app_user.dart';
import '../models/calendar_event.dart';
import '../models/chat.dart';
import '../router/app_router.dart';
import '../services/firestore_service.dart';
import '../state/auth_controller.dart';

/// The colourful in-app banner shown at the top of every role's home screen:
/// a gradient hero with a time-of-day greeting, the user's latest
/// **messages**, and up to **3 upcoming events** (each section disappears
/// when there is nothing to show).
class HomeBanner extends StatelessWidget {
  const HomeBanner({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final user = context.watch<AuthController>().appUser;
    if (user == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: scheme.heroGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                child: Text(
                  user.firstName.isEmpty ? '👋' : user.firstName[0],
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_greeting()}, ${user.firstName.isEmpty ? 'there' : user.firstName}!',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${user.role.label} · ${DateFormat('EEEE, d MMMM').format(DateTime.now())}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _MessagesStrip(user: user, db: db),
          _EventsStrip(user: user, db: db),
        ],
      ),
    );
  }
}

/// Latest active conversations with a last-message preview (up to 3);
/// hidden entirely when there are none.
class _MessagesStrip extends StatelessWidget {
  const _MessagesStrip({required this.user, required this.db});
  final AppUser user;
  final FirestoreService db;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatThread>>(
      stream: db.watchChatsForUser(user.uid),
      builder: (context, snap) {
        final threads = (snap.data ?? [])
            .where((t) => t.isActive && t.lastMessage.isNotEmpty)
            .take(3)
            .toList();
        if (threads.isEmpty) return const SizedBox.shrink();
        return _BannerSection(
          icon: Icons.chat_bubble_outline,
          title: 'Messages',
          onSeeAll: () => context.go(Routes.chats),
          children: threads
              .map((t) => _BannerRow(
                    leading: Text(
                      t.titleFor(user.uid).isEmpty
                          ? '?'
                          : t.titleFor(user.uid)[0],
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                    title: t.titleFor(user.uid),
                    subtitle:
                        '${t.lastSenderUid == user.uid ? 'You: ' : ''}${t.lastMessage}',
                    onTap: () => context.go(Routes.chatThread(t.id)),
                  ))
              .toList(),
        );
      },
    );
  }
}

/// The next 3 upcoming events relevant to this user; hidden when none.
class _EventsStrip extends StatelessWidget {
  const _EventsStrip({required this.user, required this.db});
  final AppUser user;
  final FirestoreService db;

  Stream<Set<String>> _classIds() {
    if (user.isTeacher) {
      return db
          .watchClassesForTeacher(user.uid)
          .map((cs) => cs.map((c) => c.id).toSet());
    }
    if (user.isParent) {
      return db.watchLearnersForParent(user.uid).map((ls) => ls
          .map((l) => l.classId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet());
    }
    return Stream.value(const <String>{});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Set<String>>(
      stream: _classIds(),
      initialData: const <String>{},
      builder: (context, classSnap) {
        final myClassIds = classSnap.data ?? const <String>{};
        return StreamBuilder<List<CalendarEvent>>(
          stream: db.watchEvents(),
          builder: (context, snap) {
            final today = DateTime.now();
            final startOfToday =
                DateTime(today.year, today.month, today.day);
            final upcoming = (snap.data ?? [])
                .where((e) =>
                    e.visibleTo(user, myClassIds) &&
                    !e.start.isBefore(startOfToday))
                .take(3)
                .toList();
            if (upcoming.isEmpty) return const SizedBox.shrink();
            return _BannerSection(
              icon: Icons.event_outlined,
              title: 'Upcoming events',
              onSeeAll: () => context.go(Routes.calendar),
              children: upcoming
                  .map((e) => _BannerRow(
                        leading: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(DateFormat('d').format(e.start),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1)),
                            Text(DateFormat('MMM').format(e.start),
                                style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.85),
                                    fontSize: 10,
                                    height: 1.1)),
                          ],
                        ),
                        title: e.title,
                        subtitle:
                            '${DateFormat('EEE HH:mm').format(e.start)} · ${e.audienceLabel}',
                        onTap: () => context.go(Routes.calendar),
                      ))
                  .toList(),
            );
          },
        );
      },
    );
  }
}

class _BannerSection extends StatelessWidget {
  const _BannerSection({
    required this.icon,
    required this.title,
    required this.children,
    this.onSeeAll,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
              const Spacer(),
              if (onSeeAll != null)
                InkWell(
                  onTap: onSeeAll,
                  child: Text('See all',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor:
                              Colors.white.withValues(alpha: 0.9))),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _BannerRow extends StatelessWidget {
  const _BannerRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: leading,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: Colors.white.withValues(alpha: 0.8), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
