import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../models/enums.dart';
import '../../models/fees.dart';
import '../../models/payment.dart';
import '../../models/school.dart';
import '../../services/fees_service.dart';
import '../../services/firestore_service.dart';
import '../../services/mail_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Fee management:
///  * **Fees** — configure the fee structures (name, grade, year, amount);
///  * **Outstanding** — learners who have not (fully) paid their fees;
///  * **Record** — capture a payment taken at the office;
///  * **Imports** — bulk upload learner payments from the CSV template;
///    uploads are **staged** and only create payment records once approved.
/// Raises any invoices the school is missing for this year.
///
/// There is no server to run this on the first of the month, so the finance
/// screen does it: whichever manager opens it first in a new month raises
/// that month's invoices. Deterministic ids make it safe to run on every
/// load — a second run writes nothing.
void _ensureInvoices(BuildContext context) {
  final db = context.read<FirestoreService>();
  Future<void>.microtask(() async {
    try {
      await db.ensureInvoicesForYear();
    } catch (_) {
      // Billing catches up on the next open; never block the screen.
    }
  });
}

class AdminFeesScreen extends StatelessWidget {
  const AdminFeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    _ensureInvoices(context);
    return AppShell(
      title: 'Fees',
      breadcrumb: 'Dashboard > Fees',
      body: ContentContainer(
        maxWidth: 900,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Fees',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DefaultTabController(
              length: 4,
              child: Column(
                children: [
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: 'Fee structures'),
                      Tab(text: 'Outstanding'),
                      Tab(text: 'Record payment'),
                      Tab(text: 'Bulk imports'),
                    ],
                  ),
                  SizedBox(
                    // Tab content height; each tab scrolls internally.
                    height: 640,
                    child: TabBarView(
                      children: [
                        _StructuresTab(),
                        _OutstandingTab(),
                        _RecordPaymentTab(),
                        _ImportsTab(),
                      ],
                    ),
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

// ---------------------------------------------------------------------------
// Tab 1 — fee structures
// ---------------------------------------------------------------------------

class _StructuresTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => showDialog(
                  context: context, builder: (_) => const _EditFeeDialog()),
              icon: const Icon(Icons.add),
              label: const Text('New fee'),
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<FeeStructure>>(
            stream: db.watchFeeStructures(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final fees = snap.data!;
              if (fees.isEmpty) {
                return const EmptyState(
                    'No fees configured yet — add e.g. "School fees 2026" '
                    'per grade.',
                    icon: Icons.request_quote_outlined);
              }
              return Column(
                children: fees
                    .map((f) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading:
                                const Icon(Icons.request_quote_outlined),
                            title: Text('${f.name} — ${f.amountLabel}'),
                            subtitle: Text([
                              f.grade,
                              if (f.year != null) '${f.year}',
                              if (f.dueDate != null)
                                'due ${formatDate(f.dueDate)}',
                            ].join(' · ')),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 20),
                                  onPressed: () => showDialog(
                                      context: context,
                                      builder: (_) =>
                                          _EditFeeDialog(existing: f)),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20),
                                  onPressed: () async {
                                    final ok = await confirmDialog(
                                      context,
                                      'Delete ${f.name}?',
                                      'Existing payments are kept; the fee '
                                          'just stops counting toward '
                                          'outstanding balances.',
                                      confirmLabel: 'Delete',
                                    );
                                    if (ok) {
                                      await db.deleteFeeStructure(f.id);
                                    }
                                  },
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
    );
  }
}

class _EditFeeDialog extends StatefulWidget {
  const _EditFeeDialog({this.existing});
  final FeeStructure? existing;

  @override
  State<_EditFeeDialog> createState() => _EditFeeDialogState();
}

class _EditFeeDialogState extends State<_EditFeeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _year;
  late String _grade;
  DateTime? _dueDate;
  FeeCycle _cycle = FeeCycle.annual;
  int _installments = 12;
  int _firstMonth = 1;
  int _dueDay = 7;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(
        text: e != null ? (e.amountCents / 100).toStringAsFixed(2) : '');
    _year = TextEditingController(
        text: (e?.year ?? DateTime.now().year).toString());
    _grade = e?.grade ?? kAllGrades;
    _dueDate = e?.dueDate;
    _cycle = e?.cycle ?? FeeCycle.annual;
    _installments = e?.installments ?? 12;
    _firstMonth = e?.firstMonth ?? 1;
    _dueDay = e?.dueDay ?? 7;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<FirestoreService>();
    setState(() => _saving = true);
    try {
      final amountCents =
          (double.parse(_amount.text.replaceAll(',', '.')) * 100).round();
      final data = FeeStructure(
        id: widget.existing?.id ?? '',
        name: _name.text.trim(),
        grade: _grade,
        year: int.tryParse(_year.text),
        amountCents: amountCents,
        cycle: _cycle,
        installments: _installments,
        firstMonth: _firstMonth,
        dueDay: _dueDay,
        dueDate: _dueDate,
      );
      if (widget.existing == null) {
        await db.createFeeStructure(data);
      } else {
        await db.updateFeeStructure(widget.existing!.id, {
          'name': data.name,
          'grade': data.grade,
          'year': data.year,
          'amountCents': data.amountCents,
          'cycle': data.cycle.name,
          'installments': data.installments,
          'firstMonth': data.firstMonth,
          'dueDay': data.dueDay,
          'dueDate': _dueDate,
        });
      }
      // Changing what a grade owes has to reach the learners in it, or the
      // fee is set but nobody is billed for it.
      final raised = await db.ensureInvoicesForYear(year: data.year);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (raised > 0) {
        showSnack(context, 'Saved — $raised invoice(s) raised.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Shows the parent-facing number as the amount is typed — the figure the
  /// office will be asked about is the monthly one, not the annual total.
  String _monthlyHint() {
    final rand = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (rand == null || rand <= 0 || _installments <= 0) {
      return 'Split into monthly installments';
    }
    final parts =
        FeesService.installmentAmounts((rand * 100).round(), _installments);
    final first = (parts.first / 100).toStringAsFixed(2);
    final rest = (parts.last / 100).toStringAsFixed(2);
    return first == rest
        ? '$_installments × R $first per month'
        : 'R $first then ${_installments - 1} × R $rest per month';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New fee' : 'Edit fee'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Name', hintText: 'e.g. School fees 2026'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Name is required'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _grade,
                decoration: const InputDecoration(labelText: 'Grade'),
                items: [kAllGrades, ...RefData.grades]
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => _grade = v ?? _grade),
              ),
              const SizedBox(height: 12),
              SegmentedButton<FeeCycle>(
                segments: const [
                  ButtonSegment(
                      value: FeeCycle.annual, label: Text('Annual tuition')),
                  ButtonSegment(
                      value: FeeCycle.onceOff, label: Text('Once-off')),
                ],
                selected: {_cycle},
                onSelectionChanged: (v) => setState(() => _cycle = v.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                decoration: InputDecoration(
                  labelText: _cycle == FeeCycle.annual
                      ? "Amount for the year (R)"
                      : 'Amount (R)',
                  prefixText: 'R ',
                  helperText: _cycle == FeeCycle.annual
                      ? _monthlyHint()
                      : 'Charged once',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final d = double.tryParse((v ?? '').replaceAll(',', '.'));
                  if (d == null || d <= 0) return 'Enter a valid amount';
                  return null;
                },
              ),
              if (_cycle == FeeCycle.annual) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _installments,
                        decoration:
                            const InputDecoration(labelText: 'Installments'),
                        items: const [1, 4, 10, 11, 12]
                            .map((n) => DropdownMenuItem(
                                value: n, child: Text('$n')))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _installments = v ?? 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _firstMonth,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'First month'),
                        items: const [
                          'January', 'February', 'March', 'April', 'May',
                          'June', 'July', 'August', 'September', 'October',
                          'November', 'December',
                        ]
                            .asMap()
                            .entries
                            .map((e) => DropdownMenuItem(
                                value: e.key + 1,
                                child: Text(e.value,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _firstMonth = v ?? 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _dueDay,
                        decoration:
                            const InputDecoration(labelText: 'Due day'),
                        items: const [1, 5, 7, 15, 25, 28]
                            .map((d) => DropdownMenuItem(
                                value: d, child: Text('$d')))
                            .toList(),
                        onChanged: (v) => setState(() => _dueDay = v ?? 7),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _year,
                decoration: const InputDecoration(labelText: 'Year'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dueDate ?? now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 3),
                  );
                  if (picked != null) setState(() => _dueDate = picked);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Due date (optional)',
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(
                      _dueDate == null ? '—' : formatDate(_dueDate)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2 — outstanding fees
// ---------------------------------------------------------------------------

class _OutstandingTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    return StreamBuilder<List<Learner>>(
      stream: db.watchLearners(),
      builder: (context, learnerSnap) {
        return StreamBuilder<List<FeeStructure>>(
          stream: db.watchFeeStructures(),
          builder: (context, feeSnap) {
            return StreamBuilder<List<PaymentRecord>>(
              stream: db.watchPayments(),
              builder: (context, paySnap) {
                if (!learnerSnap.hasData ||
                    !feeSnap.hasData ||
                    !paySnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final fees = feeSnap.data!;
                if (fees.isEmpty) {
                  return const EmptyState(
                      'Configure fee structures first — outstanding '
                      'balances are measured against them.',
                      icon: Icons.request_quote_outlined);
                }
                final learners = learnerSnap.data!
                    .where((l) => l.status == LearnerStatus.active)
                    .toList();
                final approved = paySnap.data!
                    .where((p) => p.status == PaymentStatus.approved)
                    .toList();

                // Fee-relevant payments per learner: linked to a structure,
                // or general "School fees" purpose payments.
                int paidFor(Learner l) => approved
                    .where((p) =>
                        p.learnerId == l.id &&
                        (p.feeStructureId != null ||
                            p.purpose == 'School fees'))
                    .fold(0, (sum, p) => sum + p.amountCents);
                int requiredFor(Learner l) => fees
                    .where((f) => f.appliesTo(l.grade))
                    .fold(0, (sum, f) => sum + f.amountCents);

                final rows = learners
                    .map((l) => (
                          learner: l,
                          required: requiredFor(l),
                          paid: paidFor(l),
                        ))
                    .where((r) => r.required > r.paid)
                    .toList()
                  ..sort((a, b) => (b.required - b.paid)
                      .compareTo(a.required - a.paid));

                final totalOutstanding = rows.fold<int>(
                    0, (sum, r) => sum + (r.required - r.paid));

                if (rows.isEmpty) {
                  return const EmptyState(
                      'Everyone is up to date — no outstanding fees. 🎉',
                      icon: Icons.verified_outlined);
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          '${rows.length} learner(s) with outstanding fees — '
                          'total R ${(totalOutstanding / 100).toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...rows.map((r) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                  child: Text(r.learner.firstName.isEmpty
                                      ? '?'
                                      : r.learner.firstName[0])),
                              title: Text(r.learner.fullName),
                              subtitle: Text([
                                if (r.learner.grade.isNotEmpty)
                                  r.learner.grade,
                                'Due R ${(r.required / 100).toStringAsFixed(2)}',
                                'Paid R ${(r.paid / 100).toStringAsFixed(2)}',
                              ].join(' · ')),
                              trailing: StatusChip(
                                'R ${((r.required - r.paid) / 100).toStringAsFixed(2)} outstanding',
                                Colors.red,
                              ),
                            ),
                          )),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3 — record a payment at the office
// ---------------------------------------------------------------------------

class _RecordPaymentTab extends StatefulWidget {
  @override
  State<_RecordPaymentTab> createState() => _RecordPaymentTabState();
}

class _RecordPaymentTabState extends State<_RecordPaymentTab> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String? _learnerId;
  String? _feeId;
  String _purpose = 'School fees';
  String? _method = 'Cash deposit';
  DateTime _date = DateTime.now();
  bool _notify = true;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save(
      List<Learner> learners, List<FeeStructure> fees) async {
    if (!_formKey.currentState!.validate()) return;
    final learner =
        learners.where((l) => l.id == _learnerId).firstOrNull;
    if (learner == null) {
      showSnack(context, 'Pick a learner');
      return;
    }
    final db = context.read<FirestoreService>();
    final mail = context.read<MailService>();
    final me = context.read<AuthController>().appUser;

    setState(() => _saving = true);
    try {
      final amountCents =
          (double.parse(_amount.text.replaceAll(',', '.')) * 100).round();
      final record = PaymentRecord(
        id: '',
        parentUid: learner.parentUids.firstOrNull ?? '',
        learnerId: learner.id,
        learnerName: learner.fullName,
        purpose: _purpose,
        method: _method ?? '',
        amountCents: amountCents,
        reference: _reference.text.trim(),
        paymentDate: _date,
        notes: 'Recorded at the office',
        status: PaymentStatus.approved,
        reviewedByName: me?.fullName ?? '',
        reviewedAt: DateTime.now(),
        source: 'admin',
        feeStructureId: _feeId,
      );
      await db.recordAdminPayment(record);

      var mailNote = '';
      if (_notify && learner.parentUids.isNotEmpty) {
        final parent = await db.getUser(learner.parentUids.first);
        if (parent?.email != null && parent!.email!.isNotEmpty) {
          final email = MailService.paymentEmail(
            parentFirstName: parent.firstName,
            purpose: _purpose,
            amountLabel: record.amountLabel,
            learnerName: learner.fullName,
            approved: true,
          );
          final outcome = await mail.send(
              to: parent.email!,
              subject: email.subject,
              text: email.text);
          mailNote = ' — ${outcome.label}';
        }
      }
      if (!mounted) return;
      _amount.clear();
      _reference.clear();
      setState(() {
        _learnerId = null;
        _feeId = null;
      });
      showSnack(context, 'Payment recorded$mailNote.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not record: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: StreamBuilder<List<Learner>>(
        stream: db.watchLearners(),
        builder: (context, learnerSnap) {
          final learners = learnerSnap.data ?? [];
          return StreamBuilder<List<FeeStructure>>(
            stream: db.watchFeeStructures(),
            builder: (context, feeSnap) {
              final fees = feeSnap.data ?? [];
              return Form(
                key: _formKey,
                child: SectionCard(
                  title: 'Record a payment received at the office',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue:
                            learners.any((l) => l.id == _learnerId)
                                ? _learnerId
                                : null,
                        decoration:
                            const InputDecoration(labelText: 'Learner'),
                        items: learners
                            .map((l) => DropdownMenuItem(
                                value: l.id,
                                child: Text(
                                    '${l.fullName}${l.grade.isEmpty ? '' : ' (${l.grade})'}')))
                            .toList(),
                        onChanged: (v) => setState(() => _learnerId = v),
                        validator: (v) =>
                            v == null ? 'Pick a learner' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: fees.any((f) => f.id == _feeId)
                            ? _feeId
                            : null,
                        decoration: const InputDecoration(
                          labelText: 'Fee (optional)',
                          helperText:
                              'Link the payment to a configured fee',
                        ),
                        items: fees
                            .map((f) => DropdownMenuItem(
                                value: f.id,
                                child: Text(
                                    '${f.name} (${f.amountLabel})')))
                            .toList(),
                        onChanged: (id) => setState(() {
                          _feeId = id;
                          final f = fees
                              .where((f) => f.id == id)
                              .firstOrNull;
                          if (f != null && _amount.text.isEmpty) {
                            _amount.text =
                                (f.amountCents / 100).toStringAsFixed(2);
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _purpose,
                        decoration:
                            const InputDecoration(labelText: 'Purpose'),
                        items: RefData.paymentPurposes
                            .map((p) => DropdownMenuItem(
                                value: p, child: Text(p)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _purpose = v ?? _purpose),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _amount,
                        decoration: const InputDecoration(
                            labelText: 'Amount (R)', prefixText: 'R '),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (v) {
                          final d = double.tryParse(
                              (v ?? '').replaceAll(',', '.'));
                          if (d == null || d <= 0) {
                            return 'Enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _method,
                        decoration: const InputDecoration(
                            labelText: 'Payment method'),
                        items: RefData.paymentMethods
                            .map((m) => DropdownMenuItem(
                                value: m, child: Text(m)))
                            .toList(),
                        onChanged: (v) => setState(() => _method = v),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(now.year - 1),
                            lastDate: now,
                          );
                          if (picked != null) {
                            setState(() => _date = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Date paid',
                            suffixIcon:
                                Icon(Icons.calendar_today, size: 18),
                          ),
                          child: Text(formatDate(_date)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _reference,
                        decoration: const InputDecoration(
                            labelText: 'Reference (optional)'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Email the parent a receipt'),
                        value: _notify,
                        onChanged: (v) => setState(() => _notify = v),
                      ),
                      const SizedBox(height: 4),
                      FilledButton.icon(
                        onPressed: _saving
                            ? null
                            : () => _save(learners, fees),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Record payment'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 4 — bulk CSV imports (staged, then approved)
// ---------------------------------------------------------------------------

class _ImportsTab extends StatefulWidget {
  @override
  State<_ImportsTab> createState() => _ImportsTabState();
}

class _ImportsTabState extends State<_ImportsTab> {
  bool _busy = false;

  static const _header = [
    'learnerId',
    'learnerName',
    'grade',
    'className',
    'amountRand',
    'date(yyyy-mm-dd)',
    'method',
    'reference',
    'purpose',
  ];

  Future<void> _downloadTemplate() async {
    final db = context.read<FirestoreService>();
    setState(() => _busy = true);
    try {
      final learners = await db.watchLearners().first;
      final rows = <List<String>>[
        _header,
        ...learners
            .where((l) => l.status == LearnerStatus.active)
            .map((l) => [
                  l.id,
                  l.fullName,
                  l.grade,
                  l.className,
                  '',
                  '',
                  '',
                  '',
                  'School fees',
                ]),
      ];
      final csvText = const ListToCsvConverter().convert(rows);
      await FilePicker.saveFile(
        dialogTitle: 'Save payments template',
        fileName: 'fee-payments-template.csv',
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: utf8.encode(csvText),
      );
      if (mounted) {
        showSnack(context,
            'Template with ${rows.length - 1} learner row(s) saved. Fill '
            'in amountRand for the rows you want to import.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save template: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final db = context.read<FirestoreService>();
    final me = context.read<AuthController>().appUser;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;

    setState(() => _busy = true);
    try {
      final learners = await db.watchLearners().first;
      final byId = {for (final l in learners) l.id: l};
      final content =
          utf8.decode(file.bytes!, allowMalformed: true).replaceAll('\r\n', '\n');
      final table = const CsvToListConverter(
              shouldParseNumbers: false, eol: '\n')
          .convert(content);
      if (table.isEmpty) {
        if (mounted) showSnack(context, 'The file is empty.');
        return;
      }

      // Map columns by header name so column order doesn't matter.
      final header =
          table.first.map((c) => '$c'.trim().toLowerCase()).toList();
      int col(String name) =>
          header.indexWhere((h) => h.startsWith(name.toLowerCase()));
      final idCol = col('learnerid');
      final amountCol = col('amountrand');
      if (idCol < 0 || amountCol < 0) {
        if (mounted) {
          showSnack(context,
              'Could not find the learnerId / amountRand columns — use '
              'the downloaded template.');
        }
        return;
      }
      final nameCol = col('learnername');
      final dateCol = col('date');
      final methodCol = col('method');
      final refCol = col('reference');
      final purposeCol = col('purpose');

      String cell(List row, int i) =>
          (i >= 0 && i < row.length) ? '${row[i]}'.trim() : '';

      final rows = <ImportRow>[];
      for (final raw in table.skip(1)) {
        final amountText = cell(raw, amountCol).replaceAll(',', '.');
        if (amountText.isEmpty) continue; // row left blank — not imported
        final learnerId = cell(raw, idCol);
        final learner = byId[learnerId];
        final amount = double.tryParse(amountText);
        final dateText = cell(raw, dateCol);
        final date =
            dateText.isEmpty ? DateTime.now() : DateTime.tryParse(dateText);
        String? error;
        if (learner == null) {
          error = 'Unknown learnerId';
        } else if (amount == null || amount <= 0) {
          error = 'Invalid amount "$amountText"';
        } else if (date == null) {
          error = 'Invalid date "$dateText" (use yyyy-mm-dd)';
        }
        rows.add(ImportRow(
          learnerId: learnerId,
          learnerName: learner?.fullName ?? cell(raw, nameCol),
          amountCents: ((amount ?? 0) * 100).round(),
          date: date,
          method: cell(raw, methodCol),
          reference: cell(raw, refCol),
          purpose: cell(raw, purposeCol).isEmpty
              ? 'School fees'
              : cell(raw, purposeCol),
          error: error,
        ));
      }
      if (rows.isEmpty) {
        if (mounted) {
          showSnack(context,
              'No rows with an amount found — fill in amountRand first.');
        }
        return;
      }

      await db.createPaymentImport(PaymentImport(
        id: '',
        filename: file.name,
        rows: rows,
        createdByName: me?.fullName ?? '',
      ));
      if (mounted) {
        showSnack(context,
            'Staged ${rows.length} row(s) from ${file.name} — review and '
            'approve below.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not read the CSV: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(PaymentImport imp) async {
    final db = context.read<FirestoreService>();
    final me = context.read<AuthController>().appUser;
    final ok = await confirmDialog(
      context,
      'Approve this import?',
      'This creates ${imp.validCount} approved payment record(s) totalling '
          '${imp.totalLabel}. ${imp.invalidCount} invalid row(s) are '
          'skipped.',
      confirmLabel: 'Approve import',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final learners = await db.watchLearners().first;
      final created = await db.approvePaymentImport(
        imp,
        byName: me?.fullName ?? '',
        learnersById: {for (final l in learners) l.id: l},
      );
      if (mounted) {
        showSnack(context, 'Import approved — $created payment(s) created.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Approval failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _viewRows(PaymentImport imp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(imp.filename),
        content: SizedBox(
          width: 560,
          height: 420,
          child: ListView(
            children: imp.rows
                .map((r) => ListTile(
                      dense: true,
                      leading: Icon(
                        r.valid ? Icons.check_circle : Icons.error,
                        color: r.valid ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      title: Text(
                          '${r.learnerName.isEmpty ? r.learnerId : r.learnerName} — ${r.amountLabel}'),
                      subtitle: Text(r.valid
                          ? [
                              r.purpose,
                              if (r.method.isNotEmpty) r.method,
                              formatDate(r.date),
                              if (r.reference.isNotEmpty) r.reference,
                            ].join(' · ')
                          : r.error!),
                    ))
                .toList(),
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Bulk upload learner payments',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '1. Download the template (one row per learner, with '
                    'their learnerId).\n'
                    '2. Fill in amountRand (and optionally date, method, '
                    'reference, purpose) for the learners who paid — leave '
                    'the rest blank.\n'
                    '3. Upload the file. It is staged first; nothing is '
                    'recorded until you approve it below.',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _downloadTemplate,
                      icon: const Icon(Icons.download),
                      label: const Text('Download template CSV'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _upload,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Upload filled CSV'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<PaymentImport>>(
            stream: db.watchPaymentImports(),
            builder: (context, snap) {
              final imports = snap.data ?? [];
              if (imports.isEmpty) {
                return const EmptyState('No uploads yet.',
                    icon: Icons.upload_file);
              }
              return Column(
                children: imports
                    .map((imp) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(imp.filename,
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.bold)),
                                    ),
                                    StatusChip(
                                      imp.status.label,
                                      switch (imp.status) {
                                        ImportStatus.staged =>
                                          Colors.orange,
                                        ImportStatus.approved =>
                                          Colors.green,
                                        ImportStatus.discarded =>
                                          Colors.blueGrey,
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text([
                                  '${imp.validCount} valid row(s)',
                                  if (imp.invalidCount > 0)
                                    '${imp.invalidCount} invalid',
                                  'total ${imp.totalLabel}',
                                  'by ${imp.createdByName}',
                                  formatDateTime(imp.createdAt),
                                ].join(' · ')),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _viewRows(imp),
                                      icon: const Icon(
                                          Icons.table_rows_outlined,
                                          size: 18),
                                      label: const Text('View rows'),
                                    ),
                                    if (imp.status ==
                                        ImportStatus.staged) ...[
                                      FilledButton.icon(
                                        onPressed: _busy
                                            ? null
                                            : () => _approve(imp),
                                        icon: const Icon(Icons.check,
                                            size: 18),
                                        label: const Text(
                                            'Approve & create payments'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: _busy
                                            ? null
                                            : () async {
                                                final ok =
                                                    await confirmDialog(
                                                  context,
                                                  'Discard this upload?',
                                                  'No payments will be '
                                                      'created from it.',
                                                  confirmLabel: 'Discard',
                                                );
                                                if (ok) {
                                                  await db
                                                      .discardPaymentImport(
                                                          imp.id);
                                                }
                                              },
                                        icon: const Icon(Icons.close,
                                            size: 18),
                                        label: const Text('Discard'),
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
    );
  }
}
