import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/attendance.dart';
import '../../models/enums.dart';
import '../../models/school.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// QR attendance scanner for teachers and all school staff. Scanning a
/// learner's QR shows the child's details, then the staff member marks them
/// **in school (present)** at drop-off or **left school** at pick-up. Each
/// scan is recorded and the linked parents are notified by email.
///
/// A name search sits below the camera as a fallback (e.g. forgotten card or
/// a browser without camera access) — it opens the same details sheet.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handling = false;
  String _search = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final raw = capture.barcodes.isEmpty
        ? null
        : capture.barcodes.first.rawValue;
    final learnerId = AttendanceRecord.learnerIdFromQr(raw);
    if (learnerId == null) return; // not one of our codes — keep scanning

    _handling = true;
    final db = context.read<FirestoreService>();
    await _controller.stop();
    try {
      final learner = await db.getLearner(learnerId);
      if (!mounted) return;
      if (learner == null) {
        showSnack(context, 'Unknown QR code — no matching learner.');
      } else {
        await _showLearnerSheet(learner);
      }
    } finally {
      _handling = false;
      if (mounted) await _controller.start();
    }
  }

  Future<void> _showLearnerSheet(Learner learner) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LearnerSheet(learner: learner),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Scan',
      breadcrumb: 'Attendance > Scan QR',
      body: ContentContainer(
        maxWidth: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Scan a learner QR code',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'Point the camera at the learner\'s QR code. Their details '
                'pop up so you can mark drop-off or leaving — parents are '
                'emailed automatically.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 320,
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => Container(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Camera unavailable (${error.errorCode.name}). '
                      'Use the search below instead.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'No code? Find the learner',
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name…',
                    ),
                    onChanged: (v) =>
                        setState(() => _search = v.trim().toLowerCase()),
                  ),
                  if (_search.isNotEmpty)
                    StreamBuilder<List<Learner>>(
                      stream: db.watchLearners(),
                      builder: (context, snap) {
                        final matches = (snap.data ?? [])
                            .where((l) => l.fullName
                                .toLowerCase()
                                .contains(_search))
                            .take(8)
                            .toList();
                        if (matches.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('No matching learners',
                                style: TextStyle(color: Colors.grey)),
                          );
                        }
                        return Column(
                          children: matches
                              .map((l) => ListTile(
                                    leading: CircleAvatar(
                                        child: Text(l.firstName.isEmpty
                                            ? '?'
                                            : l.firstName[0])),
                                    title: Text(l.fullName),
                                    subtitle: Text([
                                      if (l.grade.isNotEmpty) l.grade,
                                      if (l.className.isNotEmpty)
                                        l.className,
                                    ].join(' · ')),
                                    onTap: () => _showLearnerSheet(l),
                                  ))
                              .toList(),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The scanned child's details + the in/out action buttons.
class _LearnerSheet extends StatefulWidget {
  const _LearnerSheet({required this.learner});
  final Learner learner;

  @override
  State<_LearnerSheet> createState() => _LearnerSheetState();
}

class _LearnerSheetState extends State<_LearnerSheet> {
  bool _saving = false;

  Future<void> _mark(AttendanceType type) async {
    final db = context.read<FirestoreService>();
    final me = context.read<AuthController>().appUser;
    if (me == null) return;
    setState(() => _saving = true);
    try {
      await db.recordAttendance(widget.learner, type, by: me);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(
          context,
          '${widget.learner.fullName} marked as '
          '${type.stateLabel.toLowerCase()} — parents notified.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not record scan: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.learner;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    l.firstName.isEmpty ? '?' : l.firstName[0],
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.fullName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(
                        [
                          if (l.grade.isNotEmpty) l.grade,
                          l.className.isEmpty
                              ? 'No class assigned'
                              : l.className,
                        ].join(' · '),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (l.attendanceStatus != null)
                  StatusChip(
                    l.attendanceStatus!.stateLabel,
                    l.isInSchool ? Colors.green : Colors.orange,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (l.dateOfBirth != null)
              InfoLine('Date of birth', formatDate(l.dateOfBirth)),
            if (l.gender != null) InfoLine('Gender', l.gender!.label),
            InfoLine('Status', l.status.label),
            if (l.lastAttendanceAt != null)
              InfoLine('Last scan',
                  '${l.attendanceStatus?.stateLabel ?? ''} · ${formatDateTime(l.lastAttendanceAt)}'),
            InfoLine('Linked parents', '${l.parentUids.length}'),
            if (l.parentUids.isEmpty)
              Text(
                'No parents linked — nobody will be notified for this scan.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.orange),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  _saving ? null : () => _mark(AttendanceType.checkIn),
              icon: const Icon(Icons.login),
              label: Text(AttendanceType.checkIn.actionLabel),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  _saving ? null : () => _mark(AttendanceType.checkOut),
              icon: const Icon(Icons.logout),
              label: Text(AttendanceType.checkOut.actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
