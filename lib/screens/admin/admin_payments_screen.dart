import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/responsive.dart';
import '../../models/enums.dart';
import '../../models/payment.dart';
import '../../models/activity_log.dart';
import '../../services/activity_service.dart';
import '../../services/firestore_service.dart';
import '../../services/mail_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Admin payment review: parents' submitted payment forms + proof of payment,
/// approved or rejected here. The decision emails the parent automatically.
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  PaymentStatus? _filter = PaymentStatus.pending;

  Future<void> _review(PaymentRecord p, PaymentStatus status) async {
    final db = context.read<FirestoreService>();
    final mail = context.read<MailService>();
    final byName = context.read<AuthController>().appUser?.fullName ?? '';

    String note = '';
    if (status == PaymentStatus.rejected) {
      final ctrl = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reason for rejection'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
                hintText: 'e.g. proof unreadable, amount mismatch — shared '
                    'with the parent'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('Reject payment'),
            ),
          ],
        ),
      );
      if (reason == null) return;
      note = reason;
    }

    await db.reviewPayment(p.id, status, note: note, byName: byName);
    if (mounted) {
      context.read<ActivityService>().log(ActivityAction.paymentReviewed,
          target: p.parentName.isEmpty ? p.purpose : p.parentName,
          details: '${status.label} · ${p.amountLabel}');
    }

    // Notify the parent over the school's SMTP.
    var mailNote = '';
    final parent = await db.getUser(p.parentUid);
    if (parent?.email != null && parent!.email!.isNotEmpty) {
      final email = MailService.paymentEmail(
        parentFirstName: parent.firstName,
        purpose: p.purpose,
        amountLabel: p.amountLabel,
        learnerName: p.learnerName,
        approved: status == PaymentStatus.approved,
        reviewNote: note,
      );
      final outcome = await mail.send(
          to: parent.email!, subject: email.subject, text: email.text);
      mailNote = ' — ${outcome.label}';
    }
    if (mounted) {
      showSnack(context, 'Payment ${status.label.toLowerCase()}$mailNote.');
    }
  }

  /// Approving money is the principal's signature. The rules refuse anyone
  /// else, so showing the button to an office admin would only produce a
  /// permission error they cannot act on.
  static bool _canApprove(BuildContext context) {
    final auth = context.read<AuthController>();
    return auth.isSuperAdmin || auth.role == UserRole.principal;
  }

  /// Approves everything currently waiting, in one pass.
  Future<void> _approveAll(List<PaymentRecord> pending) async {
    if (pending.isEmpty) return;
    // Captured before the dialog: after an await the element may be gone.
    final db = context.read<FirestoreService>();
    final byName = context.read<AuthController>().appUser?.fullName ?? '';
    final activity = context.read<ActivityService>();

    final total = pending.fold<int>(0, (acc, p) => acc + p.amountCents);
    final ok = await confirmDialog(
      context,
      'Approve ${pending.length} payment${pending.length == 1 ? '' : 's'}?',
      'R ${(total / 100).toStringAsFixed(2)} in total. Each parent is '
          'notified and the amounts come off their balances.',
      confirmLabel: 'Approve all',
    );
    if (!ok) return;
    setState(() => _bulkRunning = true);
    try {
      final result = await db.approvePayments(
        pending.map((p) => p.id).toList(),
        byName: byName,
        note: 'Approved in bulk by the principal',
      );
      activity.log(ActivityAction.paymentReviewed,
          target: 'Bulk approval',
          details: '${result.approved} approved, ${result.failed} failed');
      if (!mounted) return;
      showSnack(
          context,
          result.failed == 0
              ? '${result.approved} payment(s) approved.'
              : '${result.approved} approved, ${result.failed} could not be '
                  'approved — open them individually to see why.');
    } finally {
      if (mounted) setState(() => _bulkRunning = false);
    }
  }

  bool _bulkRunning = false;

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();

    return AppShell(
      title: 'Payments',
      breadcrumb: 'Dashboard > Payments',
      body: ContentContainer(
        maxWidth: 860,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Payment approvals',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                _canApprove(context)
                    ? 'Approving a payment is your signature — it settles the '
                        'amount against the parent’s balance and notifies '
                        'them. Office staff can record payments but cannot '
                        'approve them.'
                    : 'You can record payments here; the principal approves '
                        'them.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            if (_canApprove(context))
              StreamBuilder<List<PaymentRecord>>(
                stream: db.watchPayments(),
                builder: (context, snap) {
                  final pending = (snap.data ?? const <PaymentRecord>[])
                      .where((p) => p.status == PaymentStatus.pending)
                      .toList();
                  if (pending.isEmpty) return const SizedBox.shrink();
                  final total =
                      pending.fold<int>(0, (acc, p) => acc + p.amountCents);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.approval_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                  '${pending.length} payment'
                                  '${pending.length == 1 ? '' : 's'} waiting '
                                  '— R ${(total / 100).toStringAsFixed(2)}',
                                  style:
                                      Theme.of(context).textTheme.bodyMedium),
                            ),
                            FilledButton.icon(
                              onPressed: _bulkRunning
                                  ? null
                                  : () => _approveAll(pending),
                              icon: _bulkRunning
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.done_all, size: 18),
                              label: const Text('Approve all'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                const SizedBox(width: 8),
                ...PaymentStatus.values.map((s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: _filter == s,
                        onSelected: (_) => setState(() => _filter = s),
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<PaymentRecord>>(
              stream: db.watchPayments(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final payments = snap.data!
                    .where((p) => _filter == null || p.status == _filter)
                    .toList();
                if (payments.isEmpty) {
                  return const EmptyState('No payments in this view.',
                      icon: Icons.receipt_long_outlined);
                }
                return Column(
                  children: payments
                      .map((p) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                            '${p.purpose} — ${p.amountLabel}',
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.bold)),
                                      ),
                                      StatusChip.payment(p.status),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  InfoLine('Parent', p.parentName),
                                  if (p.learnerName.isNotEmpty)
                                    InfoLine('Learner', p.learnerName),
                                  InfoLine('Method', p.method),
                                  if (p.reference.isNotEmpty)
                                    InfoLine('Reference', p.reference),
                                  InfoLine(
                                      'Paid on', formatDate(p.paymentDate)),
                                  InfoLine('Submitted',
                                      formatDate(p.createdAt)),
                                  if (p.notes.isNotEmpty)
                                    InfoLine('Notes', p.notes),
                                  if (p.reviewNote.isNotEmpty)
                                    InfoLine('Review note', p.reviewNote),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (p.proofUrl.isNotEmpty)
                                        OutlinedButton.icon(
                                          onPressed: () => launchUrl(
                                              Uri.parse(p.proofUrl),
                                              mode: LaunchMode
                                                  .externalApplication),
                                          icon: const Icon(Icons.receipt,
                                              size: 18),
                                          label: const Text(
                                              'View proof of payment'),
                                        ),
                                      if (p.status ==
                                          PaymentStatus.pending) ...[
                                        if (_canApprove(context)) ...[
                                          FilledButton.icon(
                                            onPressed: () => _review(
                                                p, PaymentStatus.approved),
                                            icon: const Icon(Icons.check,
                                                size: 18),
                                            label: const Text('Approve'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () => _review(
                                                p, PaymentStatus.rejected),
                                            icon: const Icon(Icons.close,
                                                size: 18),
                                            label: const Text('Reject'),
                                          ),
                                        ] else
                                          const Chip(
                                            avatar: Icon(Icons.lock_outline,
                                                size: 16),
                                            label: Text(
                                                'Waiting for the principal'),
                                          ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
