import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/activity_log.dart';
import '../../models/school.dart';
import '../../services/activity_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/school_logo.dart';

/// The school's own identity: what it is called, how to reach it, and its
/// badge.
///
/// These are school-wide — the logo saved here is what every member of the
/// school sees in the app bar and the sidebar, and what appears beside the
/// school in the switcher — so it is edited by the school's own admin or
/// principal rather than by the platform.
class AdminSchoolSettingsScreen extends StatefulWidget {
  const AdminSchoolSettingsScreen({super.key});

  @override
  State<AdminSchoolSettingsScreen> createState() =>
      _AdminSchoolSettingsScreenState();
}

class _AdminSchoolSettingsScreenState
    extends State<AdminSchoolSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _motto = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  String? _loadedFor;
  bool _saving = false;
  bool _uploading = false;

  @override
  void dispose() {
    for (final c in [_name, _motto, _address, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills the form the first time the school arrives, and again if the
  /// active school changes — but never on later snapshots, which would wipe
  /// out whatever the admin is in the middle of typing.
  void _seed(School school) {
    if (_loadedFor == school.id) return;
    _loadedFor = school.id;
    _name.text = school.name;
    _motto.text = school.motto;
    _address.text = school.address;
    _phone.text = school.phone;
    _email.text = school.email;
  }

  Future<void> _save(School school) async {
    if (!_formKey.currentState!.validate()) return;
    final db = context.read<FirestoreService>();
    final activity = context.read<ActivityService>();
    setState(() => _saving = true);
    try {
      await db.updateSchool(school.id, {
        'name': _name.text.trim(),
        'motto': _motto.text.trim(),
        'address': _address.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
      });
      activity.log(ActivityAction.schoolUpdated,
          target: _name.text.trim(), details: 'school details');
      if (mounted) showSnack(context, 'School details saved.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickLogo(School school) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file == null || file.bytes == null) return;

    if (!mounted) return;
    final db = context.read<FirestoreService>();
    final storage = context.read<StorageService>();
    final activity = context.read<ActivityService>();

    setState(() => _uploading = true);
    try {
      final url = await storage.uploadSchoolLogo(
        school.id,
        file.bytes!,
        filename: file.name,
        contentType: _contentTypeFor(file.extension),
      );
      await db.updateSchool(school.id, {'logoUrl': url});
      activity.log(ActivityAction.schoolUpdated,
          target: school.name, details: 'logo updated');
      if (mounted) {
        showSnack(context, 'Logo updated — everyone at the school sees it.');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not upload the logo: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeLogo(School school) async {
    final ok = await confirmDialog(
      context,
      'Remove the school logo?',
      "The school's initial is shown instead until a new one is uploaded.",
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    final db = context.read<FirestoreService>();
    try {
      await db.updateSchool(school.id, {'logoUrl': ''});
      if (mounted) showSnack(context, 'Logo removed.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not remove it: $e');
    }
  }

  static String _contentTypeFor(String? extension) {
    switch (extension?.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'svg':
        return 'image/svg+xml';
      default:
        return 'image/jpeg';
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<FirestoreService>();
    final schoolId = context.watch<AuthController>().activeSchoolId ?? '';

    return AppShell(
      title: 'School settings',
      breadcrumb: 'Overview > School settings',
      body: ContentContainer(
        maxWidth: 680,
        child: StreamBuilder<School?>(
          stream: db.watchSchool(schoolId),
          builder: (context, snap) {
            if (!snap.hasData && snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final school = snap.data;
            if (school == null) {
              return const EmptyState(
                  'No school selected. Choose one from the switcher at the '
                  'top first.',
                  icon: Icons.school_outlined);
            }
            _seed(school);

            return Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('School settings',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                      'These apply across the school — everyone signed in '
                      'here sees this name and logo.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'School logo',
                    child: Row(
                      children: [
                        SchoolLogo(school: school, size: 72),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  school.hasLogo
                                      ? 'Shown in the app bar, the sidebar '
                                          'and the school switcher.'
                                      : 'No logo yet — the school’s initial '
                                          'is shown instead.',
                                  style:
                                      Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: _uploading
                                        ? null
                                        : () => _pickLogo(school),
                                    icon: _uploading
                                        ? const SizedBox(
                                            height: 16,
                                            width: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : const Icon(Icons.upload_outlined,
                                            size: 18),
                                    label: Text(school.hasLogo
                                        ? 'Replace logo'
                                        : 'Upload logo'),
                                  ),
                                  if (school.hasLogo)
                                    OutlinedButton.icon(
                                      onPressed: _uploading
                                          ? null
                                          : () => _removeLogo(school),
                                      icon: const Icon(Icons.delete_outline,
                                          size: 18),
                                      label: const Text('Remove'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('PNG or JPG, square works best, under 5 MB.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Details',
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _name,
                          decoration:
                              const InputDecoration(labelText: 'School name'),
                          textCapitalization: TextCapitalization.words,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'The school needs a name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _motto,
                          decoration: const InputDecoration(
                              labelText: 'Motto (optional)'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _address,
                          decoration:
                              const InputDecoration(labelText: 'Address'),
                          minLines: 1,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phone,
                          decoration: const InputDecoration(
                              labelText: 'Telephone number'),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(
                            labelText: 'Office email address',
                            helperText:
                                'Where parents reply — this is separate from '
                                'the address notifications are sent from',
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(school),
                    icon: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save school details'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
