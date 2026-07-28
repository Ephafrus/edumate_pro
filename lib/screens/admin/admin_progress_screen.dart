import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/academics.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/progress_report.dart';

/// School-wide progress reports: pick a class to see how its learners are
/// doing at a glance, then open any learner for their full subject-by-subject
/// report.
class AdminProgressScreen extends StatefulWidget {
  const AdminProgressScreen({super.key});

  @override
  State<AdminProgressScreen> createState() => _AdminProgressScreenState();
}

class _AdminProgressScreenState extends State<AdminProgressScreen> {
  String? _classId;
  String _search = '';

  Color _band(double pct) {
    if (pct >= 70) return Colors.green;
    if (pct >= 50) return Colors.blue;
    if (pct >= 40) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Progress reports',
      breadcrumb: 'Dashboard > Progress reports',
      body: ContentContainer(
        maxWidth: 860,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Progress reports',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'Averages are calculated from the marks teachers capture per '
                'subject.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            StreamBuilder<List<SchoolClass>>(
              stream: db.watchClasses(),
              builder: (context, snap) {
                final classes = snap.data ?? [];
                return DropdownButtonFormField<String>(
                  initialValue:
                      classes.any((c) => c.id == _classId) ? _classId : null,
                  decoration: const InputDecoration(
                      labelText: 'Class', prefixIcon: Icon(Icons.groups)),
                  items: classes
                      .map((c) => DropdownMenuItem(
                          value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _classId = v),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search learners…',
              ),
              onChanged: (v) =>
                  setState(() => _search = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
            if (_classId == null)
              const EmptyState('Pick a class to see its learners.',
                  icon: Icons.insights_outlined)
            else
              StreamBuilder<List<Learner>>(
                stream: db.watchLearnersInClass(_classId!),
                builder: (context, learnerSnap) {
                  if (!learnerSnap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  final learners = learnerSnap.data!
                      .where((l) =>
                          l.status == LearnerStatus.active &&
                          (_search.isEmpty ||
                              l.fullName.toLowerCase().contains(_search)))
                      .toList();
                  if (learners.isEmpty) {
                    return const EmptyState(
                        'No learners in this class yet.',
                        icon: Icons.child_care_outlined);
                  }
                  return StreamBuilder<List<Mark>>(
                    stream: db.watchMarksForClass(_classId!),
                    builder: (context, markSnap) {
                      final marks = markSnap.data ?? [];
                      final byLearner = <String, List<Mark>>{};
                      for (final m in marks) {
                        byLearner.putIfAbsent(m.learnerId, () => []).add(m);
                      }
                      return Column(
                        children: learners.map((l) {
                          final ms = byLearner[l.id] ?? const <Mark>[];
                          final avg = ms.isEmpty
                              ? 0.0
                              : ms
                                      .map((m) => m.percentage)
                                      .reduce((a, b) => a + b) /
                                  ms.length;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: ms.isEmpty
                                    ? Colors.grey.withValues(alpha: 0.15)
                                    : _band(avg).withValues(alpha: 0.15),
                                child: Text(
                                  ms.isEmpty
                                      ? '—'
                                      : '${avg.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: ms.isEmpty
                                          ? Colors.grey
                                          : _band(avg)),
                                ),
                              ),
                              title: Text(l.fullName),
                              subtitle: Text(ms.isEmpty
                                  ? 'No marks captured yet'
                                  : '${ms.length} assessment(s) · '
                                      '${FirestoreService.progressBySubject(ms).length} subject(s)'),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              children: [
                                ProgressReport(
                                    learnerId: l.id, showEmptyHint: false),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
