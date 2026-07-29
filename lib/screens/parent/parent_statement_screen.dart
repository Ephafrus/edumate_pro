import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/fees.dart';
import '../../models/payment.dart';
import '../../models/school.dart';
import '../../services/download/download_stub.dart'
    if (dart.library.js_interop) '../../services/download/download_web.dart';
import '../../services/fees_service.dart';
import '../../services/firestore_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// What a parent owes, and why.
///
/// The question a parent actually asks is "how much do I owe right now, and
/// what is it made of?" — so the balance and the monthly installment come
/// first, and the statement below shows every charge and payment with the
/// balance after each one. It is the same reducing-balance layout a bank
/// statement uses, because that is the format people already know how to
/// check.
class ParentStatementScreen extends StatelessWidget {
  const ParentStatementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final auth = context.watch<AuthController>();
    final uid = auth.appUser?.uid;

    return AppShell(
      title: 'Fees',
      breadcrumb: 'Home > Fees',
      body: ContentContainer(
        maxWidth: 900,
        child: uid == null
            ? const EmptyState('Sign in to see your fees.')
            : StreamBuilder<List<Learner>>(
                stream: db.watchLearnersForParent(uid),
                builder: (context, learnerSnap) {
                  if (!learnerSnap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final learners = learnerSnap.data!;
                  if (learners.isEmpty) {
                    return const EmptyState(
                        'No children linked to your account yet. Fees appear '
                        'here once a child is enrolled.',
                        icon: Icons.receipt_long_outlined);
                  }
                  return StreamBuilder<List<Invoice>>(
                    stream: db.watchInvoicesForParent(uid),
                    builder: (context, invoiceSnap) {
                      return StreamBuilder<List<PaymentRecord>>(
                        stream: db.watchPaymentsForParent(uid),
                        builder: (context, paySnap) {
                          return StreamBuilder<List<FeeStructure>>(
                            stream: db.watchFeeStructures(),
                            builder: (context, feeSnap) {
                              final invoices =
                                  invoiceSnap.data ?? const <Invoice>[];
                              final payments =
                                  paySnap.data ?? const <PaymentRecord>[];
                              final fees =
                                  feeSnap.data ?? const <FeeStructure>[];
                              return Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  for (final learner in learners) ...[
                                    _LearnerStatement(
                                      account: FeesService.accountFor(
                                        learner: learner,
                                        invoices: invoices,
                                        payments: payments,
                                        fees: fees,
                                      ),
                                      schoolName: auth.activeSchoolName,
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _LearnerStatement extends StatelessWidget {
  const _LearnerStatement({required this.account, required this.schoolName});
  final FeeAccount account;
  final String schoolName;

  Future<void> _download(BuildContext context) async {
    final csv = FeesService.statementCsv(
        account: account, schoolName: schoolName);
    final safeName =
        account.learnerName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    final saved = await downloadText('fee-statement-$safeName.csv', csv);
    if (!context.mounted) return;
    showSnack(
        context,
        saved
            ? 'Statement downloaded.'
            : 'Statement copied to the clipboard — paste it into a '
                'spreadsheet or an email.');
  }

  @override
  Widget build(BuildContext context) {
    final owing = account.balanceCents > 0;

    return SectionCard(
      title: account.learnerName,
      trailing: TextButton.icon(
        onPressed: () => _download(context),
        icon: const Icon(Icons.download_outlined, size: 18),
        label: const Text('Statement'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The two numbers a parent came here for.
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Figure(
                label: 'Balance to date',
                value: account.balanceLabel,
                colour: owing ? Colors.red : Colors.green,
                emphasis: true,
              ),
              _Figure(
                label: 'Monthly installment',
                value: account.monthlyLabel,
                colour: Colors.indigo,
              ),
              _Figure(
                label: 'Paid this year',
                value: account.paidLabel,
                colour: Colors.teal,
              ),
              _Figure(
                label: 'Fees for the year',
                value: account.annualLabel,
                colour: Colors.blueGrey,
              ),
            ],
          ),
          if (account.pendingCents > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top,
                      size: 18, color: Colors.orange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        '${account.pendingLabel} received and waiting for the '
                        'principal to approve it. It comes off your balance '
                        'once approved.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          ],
          if (account.nextDue != null) ...[
            const SizedBox(height: 8),
            Text('Next installment due ${formatDate(account.nextDue)}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const Divider(height: 24),
          Text('Statement',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (account.lines.isEmpty)
            const Text('Nothing charged yet.',
                style: TextStyle(color: Colors.grey))
          else
            _StatementTable(lines: account.lines),
        ],
      ),
    );
  }
}

/// The reducing-balance table. Scrolls sideways on a phone rather than
/// squeezing the columns until the figures are unreadable.
class _StatementTable extends StatelessWidget {
  const _StatementTable({required this.lines});
  final List<LedgerLine> lines;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 560),
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 56,
          columnSpacing: 18,
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Description')),
            DataColumn(label: Text('Charge'), numeric: true),
            DataColumn(label: Text('Paid'), numeric: true),
            DataColumn(label: Text('Balance'), numeric: true),
          ],
          rows: [
            for (final l in lines)
              DataRow(cells: [
                DataCell(Text(formatDate(l.date), style: small)),
                DataCell(ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(l.description,
                      overflow: TextOverflow.ellipsis, style: small),
                )),
                DataCell(Text(l.debitLabel, style: small)),
                DataCell(Text(l.creditLabel,
                    style: small?.copyWith(color: Colors.green))),
                DataCell(Text(l.balanceLabel,
                    style: small?.copyWith(fontWeight: FontWeight.bold))),
              ]),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.colour,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final Color colour;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: emphasis ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey.shade700)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                fontSize: emphasis ? 22 : 18,
                fontWeight: FontWeight.w800,
                color: colour,
              )),
        ],
      ),
    );
  }
}
