import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../models/payment.dart';
import '../../models/school.dart';
import '../../models/activity_log.dart';
import '../../services/activity_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/upload_button.dart';

/// Parent payments: submit the payment form + proof of payment, and track
/// each submission's review status. Admin approval triggers an email.
class ParentPaymentsScreen extends StatelessWidget {
  const ParentPaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final user = context.watch<AuthController>().appUser;
    if (user == null) {
      return const AppShell(title: 'Payments', body: SizedBox());
    }

    return AppShell(
      title: 'Payments',
      breadcrumb: 'Home > Payments',
      body: ContentContainer(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('My payments',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                FilledButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const _NewPaymentDialog(),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Submit payment'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<PaymentRecord>>(
              stream: db.watchPaymentsForParent(user.uid),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final payments = snap.data!;
                if (payments.isEmpty) {
                  return const EmptyState(
                      'No payments submitted yet. Tap "Submit payment" after '
                      'paying the school to upload your proof of payment.',
                      icon: Icons.receipt_long_outlined);
                }
                return Column(
                  children: payments.map((p) => _PaymentCard(p)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard(this.p);
  final PaymentRecord p;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${p.purpose} — ${p.amountLabel}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                StatusChip.payment(p.status),
              ],
            ),
            const SizedBox(height: 8),
            if (p.learnerName.isNotEmpty) InfoLine('Learner', p.learnerName),
            InfoLine('Method', p.method),
            if (p.reference.isNotEmpty) InfoLine('Reference', p.reference),
            InfoLine('Paid on', formatDate(p.paymentDate)),
            InfoLine('Submitted', formatDate(p.createdAt)),
            if (p.reviewNote.isNotEmpty) InfoLine('School note', p.reviewNote),
            if (p.proofUrl.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(p.proofUrl),
                      mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.receipt, size: 18),
                  label: const Text('View proof of payment'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The payment form: learner, purpose, method, amount, date, reference and a
/// required proof-of-payment upload.
class _NewPaymentDialog extends StatefulWidget {
  const _NewPaymentDialog();

  @override
  State<_NewPaymentDialog> createState() => _NewPaymentDialogState();
}

class _NewPaymentDialogState extends State<_NewPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  Learner? _learner;
  String? _purpose;
  String? _method;
  DateTime? _paymentDate;
  PickedUpload? _proof;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_paymentDate == null) {
      showSnack(context, 'Select the date you paid');
      return;
    }
    if (_proof == null) {
      showSnack(context, 'Upload your proof of payment');
      return;
    }
    final db = context.read<FirestoreService>();
    final storage = context.read<StorageService>();
    final user = context.read<AuthController>().appUser!;

    setState(() => _saving = true);
    try {
      final proofUrl = await storage.uploadProofOfPayment(
        user.uid,
        _proof!.bytes,
        filename: _proof!.filename,
        contentType: _proof!.contentType,
      );
      final amountCents =
          (double.parse(_amount.text.replaceAll(',', '.')) * 100).round();
      await db.createPayment(PaymentRecord(
        id: '',
        parentUid: user.uid,
        parentName: user.fullName,
        learnerId: _learner?.id,
        learnerName: _learner?.fullName ?? '',
        purpose: _purpose!,
        method: _method!,
        amountCents: amountCents,
        reference: _reference.text.trim(),
        paymentDate: _paymentDate,
        notes: _notes.text.trim(),
        proofUrl: proofUrl,
        proofFilename: _proof!.filename,
      ));
      if (!mounted) return;
      context.read<ActivityService>().log(ActivityAction.paymentSubmitted,
          target: _learner?.fullName ?? _purpose!,
          details: 'R ${(amountCents / 100).toStringAsFixed(2)}');
      Navigator.of(context).pop();
      showSnack(context,
          'Payment submitted — the school will review and confirm by email.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not submit: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final uid = context.read<AuthController>().appUser!.uid;

    return AlertDialog(
      title: const Text('Submit a payment'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StreamBuilder<List<Learner>>(
                  stream: db.watchLearnersForParent(uid),
                  builder: (context, snap) {
                    final learners = snap.data ?? [];
                    final knownId =
                        learners.any((l) => l.id == _learner?.id);
                    return DropdownButtonFormField<String>(
                      initialValue: knownId ? _learner!.id : null,
                      decoration: const InputDecoration(
                        labelText: 'Learner (optional)',
                        helperText:
                            'Leave blank for a general/application payment',
                      ),
                      items: learners
                          .map((l) => DropdownMenuItem(
                              value: l.id, child: Text(l.fullName)))
                          .toList(),
                      onChanged: (id) => setState(() => _learner =
                          learners.where((l) => l.id == id).firstOrNull),
                    );
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _purpose,
                  decoration:
                      const InputDecoration(labelText: 'Payment for'),
                  items: RefData.paymentPurposes
                      .map((p) =>
                          DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _purpose = v),
                  validator: (v) =>
                      v == null ? 'Select what the payment is for' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration:
                      const InputDecoration(labelText: 'Payment method'),
                  items: RefData.paymentMethods
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setState(() => _method = v),
                  validator: (v) =>
                      v == null ? 'Select how you paid' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(
                      labelText: 'Amount (R)', prefixText: 'R '),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  validator: (v) {
                    final d =
                        double.tryParse((v ?? '').replaceAll(',', '.'));
                    if (d == null || d <= 0) return 'Enter a valid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _paymentDate ?? now,
                      firstDate: DateTime(now.year - 1),
                      lastDate: now,
                    );
                    if (picked != null) {
                      setState(() => _paymentDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date paid',
                      suffixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    child: Text(_paymentDate == null
                        ? 'Select…'
                        : formatDate(_paymentDate)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reference,
                  decoration: const InputDecoration(
                      labelText: 'Bank / EFT reference (optional)'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(
                      labelText: 'Notes (optional)'),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                UploadButton(
                  label: 'Upload proof of payment',
                  filename: _proof?.filename,
                  onPicked: (f) => setState(() => _proof = f),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Submit'),
        ),
      ],
    );
  }
}
