import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/attendance.dart';
import '../services/firestore_service.dart';
import 'common.dart';

/// A learner's QR card: the scannable code staff use at the gate, the child's
/// live in/out status, and their recent scan history. Shown to parents from
/// their dashboard and to admin from learner management (for printing).
class LearnerQrDialog extends StatelessWidget {
  const LearnerQrDialog({
    super.key,
    required this.learnerId,
    required this.learnerName,
  });

  final String learnerId;
  final String learnerName;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AlertDialog(
      title: Text(learnerName),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: QrImageView(
                  data: AttendanceRecord.qrData(learnerId),
                  size: 200,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'School staff scan this code at drop-off and pick-up. '
                'You will be emailed each time.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Recent activity',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 4),
              StreamBuilder<List<AttendanceRecord>>(
                stream: db.watchAttendanceForLearner(learnerId, limit: 8),
                builder: (context, snap) {
                  final events = snap.data ?? [];
                  if (events.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No scans yet',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return Column(
                    children: events
                        .map((e) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                e.type.name == 'checkIn'
                                    ? Icons.login
                                    : Icons.logout,
                                size: 20,
                                color: e.type.name == 'checkIn'
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              title: Text(e.type.stateLabel),
                              subtitle: Text([
                                formatDateTime(e.at),
                                if (e.byName.isNotEmpty)
                                  'scanned by ${e.byName}',
                              ].join(' · ')),
                            ))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
