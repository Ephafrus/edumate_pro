import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/academics.dart';
import '../services/firestore_service.dart';
import 'common.dart';

/// A learner's progress report: per-subject averages with a trend, and the
/// individual marks behind them. Shared by the parent's child-progress
/// dashboard and the school's progress reports.
class ProgressReport extends StatelessWidget {
  const ProgressReport({
    super.key,
    required this.learnerId,
    this.showEmptyHint = true,
  });

  final String learnerId;
  final bool showEmptyHint;

  Color _bandColour(double pct) {
    if (pct >= 70) return Colors.green;
    if (pct >= 50) return Colors.blue;
    if (pct >= 40) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return StreamBuilder<List<Mark>>(
      stream: db.watchMarksForLearner(learnerId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final marks = snap.data!;
        if (marks.isEmpty) {
          return showEmptyHint
              ? const EmptyState(
                  'No marks captured yet. Subject results appear here as '
                  'teachers record them.',
                  icon: Icons.insights_outlined)
              : const SizedBox.shrink();
        }

        final subjects = FirestoreService.progressBySubject(marks);
        final overall = subjects.isEmpty
            ? 0.0
            : subjects.map((s) => s.average).reduce((a, b) => a + b) /
                subjects.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor:
                          _bandColour(overall).withValues(alpha: 0.15),
                      child: Text(
                        '${overall.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: _bandColour(overall),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Overall average',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                              '${subjects.length} subject(s) · '
                              '${marks.length} assessment(s) recorded',
                              style:
                                  Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...subjects.map((s) {
              final colour = _bandColour(s.average);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: colour.withValues(alpha: 0.15),
                    child: Text(s.averageLabel,
                        style: TextStyle(
                            color: colour,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                  title: Text(s.subjectName),
                  subtitle: Row(
                    children: [
                      Text('${s.marks.length} assessment(s)'),
                      if (s.trend != 0) ...[
                        const SizedBox(width: 8),
                        Icon(
                          s.trend > 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 16,
                          color: s.trend > 0 ? Colors.green : Colors.red,
                        ),
                        Text(
                          ' ${s.trend > 0 ? '+' : ''}${s.trend.toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  s.trend > 0 ? Colors.green : Colors.red),
                        ),
                      ],
                    ],
                  ),
                  childrenPadding:
                      const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: s.marks
                      .map((m) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(m.assessmentTitle),
                            subtitle: Text([
                              'Term ${m.term}',
                              formatDate(m.date),
                              if (m.capturedByName.isNotEmpty)
                                m.capturedByName,
                            ].join(' · ')),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${m.score.toStringAsFixed(m.score == m.score.roundToDouble() ? 0 : 1)}/${m.outOf}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                Text('${m.percentageLabel} (${m.symbol})',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            _bandColour(m.percentage))),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
