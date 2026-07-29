import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/mail_settings.dart';
import '../../services/firestore_service.dart';
import '../../services/mail_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// School email (SMTP) setup. The admin captures the school's SMTP details
/// here; all notification email — application updates, payment reviews,
/// attendance scans and broadcasts — is then sent directly from the app
/// using these settings (no server needed).
class AdminEmailSettingsScreen extends StatefulWidget {
  const AdminEmailSettingsScreen({super.key});

  @override
  State<AdminEmailSettingsScreen> createState() =>
      _AdminEmailSettingsScreenState();
}

class _AdminEmailSettingsScreenState extends State<AdminEmailSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '587');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _fromName = TextEditingController();
  final _fromAddress = TextEditingController();
  final _relayUrl = TextEditingController();
  final _relayToken = TextEditingController();
  MailTransport _transport = MailTransport.smtp;
  String? _testResult;
  bool _testOk = false;
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await context
        .read<FirestoreService>()
        .getMailSettings(refresh: true);
    if (s != null) {
      _host.text = s.host;
      _port.text = '${s.port}';
      _username.text = s.username;
      _password.text = s.password;
      _fromName.text = s.fromName;
      _fromAddress.text = s.fromAddress;
      _relayUrl.text = s.relayUrl;
      _relayToken.text = s.relayToken;
      _transport = s.transport;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_host, _port, _username, _password, _fromName,
        _fromAddress, _relayUrl, _relayToken]) {
      c.dispose();
    }
    super.dispose();
  }

  MailSettings _current() => MailSettings(
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 587,
        username: _username.text.trim(),
        password: _password.text,
        fromName: _fromName.text.trim(),
        fromAddress: _fromAddress.text.trim(),
        transport: _transport,
        relayUrl: _relayUrl.text.trim(),
        relayToken: _relayToken.text.trim(),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<FirestoreService>().setMailSettings(_current());
      if (mounted) showSnack(context, 'Email settings saved');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendTest() async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<FirestoreService>();
    final mailer = context.read<MailService>();
    final me = context.read<AuthController>().appUser;
    final to = me?.email;
    if (to == null || to.isEmpty) {
      showSnack(context, 'Add an email address to your own profile first.');
      return;
    }
    setState(() {
      _saving = true;
      _testResult = null;
    });
    try {
      await db.setMailSettings(_current());
      // verify() reports the provider's own words; send() would swallow
      // them into a generic outcome, which is useless when the whole point
      // is finding out what is wrong.
      final result = await mailer.verify(to);
      if (!mounted) return;
      setState(() {
        _testOk = result.ok;
        _testResult = result.ok
            ? 'Sent to $to. Check the inbox — and the spam folder.'
            : result.message;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final mailer = context.read<MailService>();

    if (_loading) {
      return const AppShell(
          title: 'Email settings',
          body: Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator())));
    }

    return AppShell(
      title: 'Email settings',
      breadcrumb: 'Dashboard > Email settings',
      body: ContentContainer(
        maxWidth: 620,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('School email',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                  'Notifications to parents (applications, payments, '
                  'attendance, invoices and broadcasts) are sent from the '
                  'app using these details.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              SectionCard(
                title: 'How mail leaves the school',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<MailTransport>(
                      segments: const [
                        ButtonSegment(
                            value: MailTransport.smtp,
                            icon: Icon(Icons.dns_outlined),
                            label: Text('SMTP')),
                        ButtonSegment(
                            value: MailTransport.relay,
                            icon: Icon(Icons.http),
                            label: Text('HTTPS relay')),
                      ],
                      selected: {_transport},
                      onSelectionChanged: (v) =>
                          setState(() => _transport = v.first),
                    ),
                    const SizedBox(height: 12),
                    if (_transport == MailTransport.smtp)
                      const _Note(
                        icon: Icons.warning_amber_outlined,
                        colour: Colors.orange,
                        text: 'SMTP cannot be used from this web portal — no '
                            'browser can open a connection to a mail server. '
                            'Messages composed here are queued and sent the '
                            'next time somebody opens the mobile or desktop '
                            'app. To send from the web, use an HTTPS relay.',
                      )
                    else
                      const _Note(
                        icon: Icons.check_circle_outline,
                        colour: Colors.green,
                        text: 'A relay is an HTTPS endpoint your school owns '
                            'that receives a message and sends it. This is '
                            'what lets the web portal send mail directly. A '
                            'Google Apps Script web app sending through the '
                            "school's own Gmail is the cheapest option; see "
                            'docs/email-relay.md for one you can paste in.',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_transport == MailTransport.relay) ...[
                SectionCard(
                  title: 'Relay endpoint',
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _relayUrl,
                        decoration: const InputDecoration(
                          labelText: 'Relay URL',
                          hintText: 'https://script.google.com/macros/s/…/exec',
                          helperText:
                              'Must be https and must allow requests from '
                              'this site',
                        ),
                        validator: (v) {
                          if (_transport != MailTransport.relay) return null;
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'The relay URL is required';
                          if (!t.startsWith('https://')) {
                            return 'Must start with https://';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _relayToken,
                        decoration: const InputDecoration(
                          labelText: 'Shared secret (optional)',
                          helperText: 'Sent as a bearer token so the endpoint '
                              'is not open to anyone who finds the URL',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_testResult != null) ...[
                _Note(
                  icon: _testOk
                      ? Icons.mark_email_read_outlined
                      : Icons.error_outline,
                  colour: _testOk ? Colors.green : Colors.red,
                  text: _testResult!,
                ),
                const SizedBox(height: 16),
              ],
              SectionCard(
                title: 'SMTP server',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _host,
                      decoration: const InputDecoration(
                          labelText: 'SMTP host',
                          hintText: 'e.g. smtp.gmail.com'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Host is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _port,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        helperText:
                            '587 = STARTTLS (most common), 465 = SSL',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) =>
                          int.tryParse(v?.trim() ?? '') == null
                              ? 'Enter a port number'
                              : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(
                          labelText: 'Username',
                          hintText: 'usually the email address'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Username is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password / app password',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty)
                          ? 'Password is required'
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Sender',
                child: Column(
                  children: [
                    TextFormField(
                      controller: _fromName,
                      decoration: const InputDecoration(
                          labelText: 'From name',
                          hintText: 'e.g. Sunnyside Primary'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _fromAddress,
                      decoration: const InputDecoration(
                          labelText: 'From email address',
                          hintText: 'e.g. no-reply@school.co.za'),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        final s = v?.trim() ?? '';
                        if (s.isEmpty) return 'From address is required';
                        if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                            .hasMatch(s)) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text('Save settings'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _sendTest,
                      icon: const Icon(Icons.outgoing_mail),
                      label: const Text('Save & send test'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Outbox',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StreamBuilder<int>(
                      stream: db.watchOutboxCount(),
                      builder: (context, snap) {
                        final n = snap.data ?? 0;
                        return Text(n == 0
                            ? 'No unsent messages — all email delivered.'
                            : '$n message(s) waiting to be sent.');
                      },
                    ),
                    const SizedBox(height: 8),
                    if (kIsWeb)
                      Text(
                          'Browsers cannot send SMTP directly, so email '
                          'composed on the web is queued here and delivered '
                          'automatically when any staff member uses the '
                          'Android/iOS/desktop app.',
                          style: Theme.of(context).textTheme.bodySmall)
                    else
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () async {
                                setState(() => _saving = true);
                                final sent = await mailer.flushOutbox();
                                if (context.mounted) {
                                  showSnack(context,
                                      'Outbox: $sent message(s) sent.');
                                }
                                if (mounted) {
                                  setState(() => _saving = false);
                                }
                              },
                        icon: const Icon(Icons.send),
                        label: const Text('Send outbox now'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A short explanatory panel — used where the difference between transports
/// decides whether mail leaves the building at all.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.colour, required this.text});
  final IconData icon;
  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
