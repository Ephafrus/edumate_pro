import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/activity_log.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// The Super Admin's system log: every recorded interaction across the
/// platform — sign-ins, page opens, enrollment, academics, finance,
/// communication and administration — newest first, filterable.
///
/// The trail is append-only: entries cannot be edited or deleted by anyone.
class SuperActivityScreen extends StatefulWidget {
  const SuperActivityScreen({super.key});

  @override
  State<SuperActivityScreen> createState() => _SuperActivityScreenState();
}

class _SuperActivityScreenState extends State<SuperActivityScreen> {
  ActivityCategory? _category;
  String _query = '';

  IconData _iconFor(ActivityCategory c) {
    switch (c) {
      case ActivityCategory.auth:
        return Icons.login;
      case ActivityCategory.navigation:
        return Icons.open_in_browser;
      case ActivityCategory.enrollment:
        return Icons.assignment_outlined;
      case ActivityCategory.learners:
        return Icons.child_care_outlined;
      case ActivityCategory.academics:
        return Icons.menu_book_outlined;
      case ActivityCategory.attendance:
        return Icons.qr_code_scanner;
      case ActivityCategory.finance:
        return Icons.receipt_long_outlined;
      case ActivityCategory.communication:
        return Icons.campaign_outlined;
      case ActivityCategory.administration:
        return Icons.badge_outlined;
      case ActivityCategory.platform:
        return Icons.admin_panel_settings;
    }
  }

  Color _colourFor(ActivityCategory c) {
    switch (c) {
      case ActivityCategory.auth:
        return Colors.blue;
      case ActivityCategory.navigation:
        return Colors.blueGrey;
      case ActivityCategory.enrollment:
        return Colors.teal;
      case ActivityCategory.learners:
        return Colors.indigo;
      case ActivityCategory.academics:
        return Colors.deepPurple;
      case ActivityCategory.attendance:
        return Colors.green;
      case ActivityCategory.finance:
        return Colors.orange;
      case ActivityCategory.communication:
        return Colors.pink;
      case ActivityCategory.administration:
        return Colors.brown;
      case ActivityCategory.platform:
        return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'System log',
      breadcrumb: 'Super Admin > System log',
      body: ContentContainer(
        maxWidth: 900,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('System log',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'Every interaction recorded across the platform. '
                'Append-only — entries can never be edited or deleted.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search person, school or target…',
              ),
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null),
                    ),
                  ),
                  ...ActivityCategory.values.map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(_iconFor(c), size: 16),
                          label: Text(c.label),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<ActivityLog>>(
              stream: db.watchActivityLogs(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const EmptyState(
                      'Could not load the log. Deploy the latest Firestore '
                      'rules and indexes, then try again.',
                      icon: Icons.error_outline);
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final logs = snap.data!.where((l) {
                  if (_category != null && l.category != _category) {
                    return false;
                  }
                  if (_query.isEmpty) return true;
                  return l.actorName.toLowerCase().contains(_query) ||
                      l.schoolName.toLowerCase().contains(_query) ||
                      l.target.toLowerCase().contains(_query) ||
                      l.action.label.toLowerCase().contains(_query);
                }).toList();

                if (logs.isEmpty) {
                  return const EmptyState(
                      'Nothing logged yet for this filter. Activity appears '
                      'here as people use the app.',
                      icon: Icons.history);
                }

                // Group by calendar day for readability.
                final byDay = <String, List<ActivityLog>>{};
                for (final l in logs) {
                  byDay.putIfAbsent(formatDate(l.at), () => []).add(l);
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${logs.length} entr${logs.length == 1 ? 'y' : 'ies'}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    ...byDay.entries.map((day) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SectionCard(
                            title: day.key,
                            trailing: Text('${day.value.length}',
                                style:
                                    Theme.of(context).textTheme.bodySmall),
                            child: Column(
                              children: day.value.map((l) {
                                final colour = _colourFor(l.category);
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor:
                                        colour.withValues(alpha: 0.15),
                                    child: Icon(_iconFor(l.category),
                                        size: 16, color: colour),
                                  ),
                                  title: Text(l.summary),
                                  subtitle: Text([
                                    if (l.at != null) formatDateTime(l.at),
                                    if (l.actorRole.isNotEmpty) l.actorRole,
                                    if (l.schoolName.isNotEmpty)
                                      l.schoolName,
                                    if (l.details.isNotEmpty) l.details,
                                  ].join(' · ')),
                                );
                              }).toList(),
                            ),
                          ),
                        )),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
