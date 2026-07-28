import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/enums.dart';

final DateFormat kDateFmt = DateFormat('d MMM yyyy');
final DateFormat kDateTimeFmt = DateFormat('d MMM yyyy, HH:mm');

String formatDate(DateTime? d) => d == null ? '—' : kDateFmt.format(d);
String formatDateTime(DateTime? d) => d == null ? '—' : kDateTimeFmt.format(d);

/// A titled white card that groups a section of a form or list.
class SectionCard extends StatelessWidget {
  const SectionCard(
      {super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Small labelled read-only key/value used in cards and dashboards.
class InfoLine extends StatelessWidget {
  const InfoLine(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

/// Consistent loading / empty state for stream lists.
class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

/// Coloured status pill for application / payment / chat states.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, this.color, {super.key});

  StatusChip.application(ApplicationStatus s, {super.key})
      : label = s.label,
        color = switch (s) {
          ApplicationStatus.draft => Colors.blueGrey,
          ApplicationStatus.submitted => Colors.blue,
          ApplicationStatus.underReview => Colors.orange,
          ApplicationStatus.accepted => Colors.teal,
          ApplicationStatus.enrolled => Colors.green,
          ApplicationStatus.rejected => Colors.red,
        };

  StatusChip.payment(PaymentStatus s, {super.key})
      : label = s.label,
        color = switch (s) {
          PaymentStatus.pending => Colors.orange,
          PaymentStatus.approved => Colors.green,
          PaymentStatus.rejected => Colors.red,
        };

  StatusChip.chat(ChatApproval s, {super.key})
      : label = s.label,
        color = switch (s) {
          ChatApproval.requested => Colors.orange,
          ChatApproval.approved => Colors.green,
          ChatApproval.declined => Colors.red,
        };

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Yes/No confirmation dialog; resolves true when confirmed.
Future<bool> confirmDialog(BuildContext context, String title, String message,
    {String confirmLabel = 'Confirm'}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel)),
      ],
    ),
  );
  return res ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Big tappable stat/action tile used on the dashboards.
class DashboardTile extends StatelessWidget {
  const DashboardTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primary.withValues(alpha: 0.1),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey)),
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(badge!,
                      style: TextStyle(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.bold)),
                ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
