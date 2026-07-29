import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/app_user.dart';
import '../../models/application.dart';
import '../../models/chat.dart';
import '../../models/enums.dart';
import '../../models/fees.dart';
import '../../models/payment.dart';
import '../../models/school.dart';
import '../../router/app_router.dart';
import '../../services/fees_service.dart';
import '../../services/firestore_service.dart';
import '../../services/mail_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/home_banner.dart';

/// School admin home — an **overview dashboard**: the numbers that matter at
/// a glance, what needs attention right now, and shortcuts into the areas
/// behind them. The full toolset lives in the sidebar, so this page stays a
/// summary rather than a menu.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    // Deliver any email queued from web sessions / SMTP hiccups.
    context.read<MailService>().flushOutboxSoon();

    return AppShell(
      title: 'Overview',
      body: ContentContainer(
        maxWidth: 1100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HomeBanner(),
            Text('At a glance',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _StatGrid(db: db),
            const SizedBox(height: 24),
            Text('Needs attention',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _AttentionList(db: db),
            const SizedBox(height: 24),
            Text('Quick actions',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const _QuickActions(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Responsive grid of headline numbers.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.db});
  final FirestoreService db;

  @override
  Widget build(BuildContext context) {
    final columns = context.isMobile ? 2 : (context.isDesktop ? 4 : 3);
    return StreamBuilder<List<Learner>>(
      stream: db.watchLearners(),
      builder: (context, learnerSnap) {
        final learners = learnerSnap.data ?? const <Learner>[];
        final enrolled =
            learners.where((l) => l.status == LearnerStatus.active).length;
        final inSchool = learners.where((l) => l.isInSchool).length;
        return StreamBuilder<List<SchoolClass>>(
          stream: db.watchClasses(),
          builder: (context, classSnap) {
            return StreamBuilder<List<AppUser>>(
              stream: db.watchStaff(),
              builder: (context, staffSnap) {
                final stats = <_Stat>[
                  _Stat('Learners enrolled', '$enrolled',
                      Icons.child_care_outlined, Colors.indigo,
                      route: Routes.adminLearners),
                  _Stat('In school now', '$inSchool',
                      Icons.how_to_reg_outlined, Colors.green,
                      route: Routes.scan),
                  _Stat('Classes', '${classSnap.data?.length ?? 0}',
                      Icons.meeting_room_outlined, Colors.teal,
                      route: Routes.adminClasses),
                  _Stat('Staff', '${staffSnap.data?.length ?? 0}',
                      Icons.badge_outlined, Colors.deepPurple,
                      route: Routes.adminUsers),
                ];
                return CardGrid(
                  columns: columns,
                  // Measured, not guessed: the card's own content comes to
                  // 135px at the default text size (icon chip, 26px number,
                  // label, 14px padding). Anything less and the number is
                  // quietly shrunk to fit instead of being shown at size.
                  rowHeight: 140,
                  children: stats.map((s) => _StatCard(stat: s)).toList(),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon, this.colour,
      {required this.route});
  final String label;
  final String value;
  final IconData icon;
  final Color colour;
  final String route;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.stat});
  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go(stat.route),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: stat.colour.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(stat.icon, size: 18, color: stat.colour),
              ),
              const SizedBox(height: 8),
              // The number is the one thing that must never be cut off, and
              // it is also the largest — let it shrink rather than overflow.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(stat.value,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800)),
                ),
              ),
              Flexible(
                child: Text(stat.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Only the things with outstanding work, so the list is empty on a quiet day.
class _AttentionList extends StatelessWidget {
  const _AttentionList({required this.db});
  final FirestoreService db;

  @override
  Widget build(BuildContext context) {
    // Approving money is the principal's job, so only they are told about a
    // queue they can actually clear.
    final isPrincipal =
        context.watch<AuthController>().role == UserRole.principal;
    return StreamBuilder<List<EnrollmentApplication>>(
      stream: db.watchApplications(),
      builder: (context, appSnap) {
        final open = (appSnap.data ?? [])
            .where((a) =>
                a.status == ApplicationStatus.submitted ||
                a.status == ApplicationStatus.underReview)
            .length;
        return StreamBuilder<List<PaymentRecord>>(
          stream: db.watchPayments(),
          builder: (context, paySnap) {
            final pending = (paySnap.data ?? [])
                .where((p) => p.status == PaymentStatus.pending)
                .length;
            return StreamBuilder<List<ChatThread>>(
              stream: db.watchPendingChatRequests(),
              builder: (context, chatSnap) {
                final requests = chatSnap.data?.length ?? 0;
                return StreamBuilder<List<Learner>>(
                  stream: db.watchLearners(),
                  builder: (context, learnerSnap) {
                  return StreamBuilder<List<Invoice>>(
                    stream: db.watchInvoices(),
                    builder: (context, invoiceSnap) {
                  return StreamBuilder<List<FeeStructure>>(
                    stream: db.watchFeeStructures(),
                    builder: (context, feeSnap) {
                    final unassigned = (learnerSnap.data ?? [])
                        .where((l) =>
                            l.status == LearnerStatus.active &&
                            (l.classId == null || l.classId!.isEmpty))
                        .length;

                    final arrears = FeesService.accountsInArrears(
                      learners: learnerSnap.data ?? const [],
                      invoices: invoiceSnap.data ?? const [],
                      payments: paySnap.data ?? const [],
                      fees: feeSnap.data ?? const [],
                    );
                    final owedCents = arrears.fold<int>(
                        0, (acc, a) => acc + a.balanceCents);

                    final rows = <Widget>[
                      if (arrears.isNotEmpty)
                        DashboardTile(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Learners with fees outstanding',
                          subtitle:
                              'R ${(owedCents / 100).toStringAsFixed(2)} owed '
                              'across ${arrears.length} learner'
                              '${arrears.length == 1 ? '' : 's'}',
                          badge: '${arrears.length}',
                          onTap: () => context.go(Routes.adminFees),
                        ),
                      if (pending > 0 && isPrincipal)
                        DashboardTile(
                          icon: Icons.approval_outlined,
                          title: 'Payments awaiting your approval',
                          subtitle: 'Only a principal can approve payments',
                          badge: '$pending',
                          onTap: () => context.go(Routes.adminPayments),
                        ),
                      if (open > 0)
                        DashboardTile(
                          icon: Icons.assignment_outlined,
                          title: 'Applications to review',
                          subtitle: 'Submitted or under review',
                          badge: '$open',
                          onTap: () => context.go(Routes.adminApplications),
                        ),
                      if (pending > 0)
                        DashboardTile(
                          icon: Icons.receipt_long_outlined,
                          title: 'Payments awaiting approval',
                          subtitle: 'Proof of payment submitted by parents',
                          badge: '$pending',
                          onTap: () => context.go(Routes.adminPayments),
                        ),
                      if (requests > 0)
                        DashboardTile(
                          icon: Icons.mark_chat_unread_outlined,
                          title: 'Parent chat requests',
                          subtitle: 'Waiting for your approval',
                          badge: '$requests',
                          onTap: () => context.go(Routes.adminChatRequests),
                        ),
                      if (unassigned > 0)
                        DashboardTile(
                          icon: Icons.child_care_outlined,
                          title: 'Learners without a class',
                          subtitle: 'Assign them to a register group',
                          badge: '$unassigned',
                          onTap: () => context.go(Routes.adminLearners),
                        ),
                    ];

                    if (rows.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              const Icon(Icons.verified_outlined,
                                  color: Colors.green),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                    'All caught up — nothing is waiting on '
                                    'you right now.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: rows
                          .map((r) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: r))
                          .toList(),
                    );
                    },
                  );
                    },
                  );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// The handful of things an admin starts most often.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    const actions = <(String, IconData, String)>[
      ('Add a learner', Icons.person_add_alt, Routes.adminLearners),
      ('Create a class', Icons.add_business, Routes.adminClasses),
      ('Add staff', Icons.badge_outlined, Routes.adminStaff),
      ('School users', Icons.people_outline, Routes.adminUsers),
      ('Send a broadcast', Icons.campaign_outlined, Routes.adminBroadcasts),
      ('Record a payment', Icons.request_quote_outlined, Routes.adminFees),
      ('Progress reports', Icons.insights_outlined, Routes.adminProgress),
      ('Scan attendance', Icons.qr_code_scanner, Routes.scan),
      ('School calendar', Icons.calendar_month_outlined, Routes.calendar),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions
          .map((a) => ActionChip(
                avatar: Icon(a.$2, size: 18),
                label: Text(a.$1),
                onPressed: () => context.go(a.$3),
              ))
          .toList(),
    );
  }
}
