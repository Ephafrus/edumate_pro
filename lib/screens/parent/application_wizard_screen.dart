import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/id_validation.dart';
import '../../core/responsive.dart';
import '../../models/enums.dart';
import '../../router/app_router.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../../widgets/upload_button.dart';

/// Step-by-step enrollment application wizard:
/// 1. Learner details → 2. Parent/guardian → 3. Medical & emergency →
/// 4. Supporting documents → 5. Review & submit.
///
/// Progress is saved as a draft after every step, so a parent can leave and
/// resume later (`/parent/apply?id=...`). Submitting moves the application to
/// [ApplicationStatus.submitted] and starts the tracking timeline.
class ApplicationWizardScreen extends StatefulWidget {
  const ApplicationWizardScreen({super.key, this.applicationId});

  /// When set, resumes an existing draft.
  final String? applicationId;

  @override
  State<ApplicationWizardScreen> createState() =>
      _ApplicationWizardScreenState();
}

class _ApplicationWizardScreenState extends State<ApplicationWizardScreen> {
  final _stepKeys = List.generate(3, (_) => GlobalKey<FormState>());

  int _step = 0;
  bool _loading = true;
  bool _saving = false;
  String? _appId;

  // Step 1 — learner
  final _learnerFirst = TextEditingController();
  final _learnerLast = TextEditingController();
  final _learnerIdNumber = TextEditingController();
  final _previousSchool = TextEditingController();
  IdType? _idType = IdType.saId;
  DateTime? _dob;
  Gender? _gender;
  String? _grade;
  String? _language;

  // Step 2 — guardian
  final _guardFirst = TextEditingController();
  final _guardLast = TextEditingController();
  final _guardPhone = TextEditingController();
  final _guardEmail = TextEditingController();
  final _guardAddress = TextEditingController();
  String? _relationship;
  String? _province;

  // Step 3 — medical & emergency
  final _medical = TextEditingController();
  final _doctorName = TextEditingController();
  final _doctorPhone = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _notes = TextEditingController();

  // Step 4 — documents: label → download URL
  static const _documentSlots = <String>[
    'Birth certificate / ID',
    'Immunisation card',
    'Latest report card',
    'Proof of residence',
    "Guardian's ID",
  ];
  final Map<String, String> _documents = {};
  String? _uploadingSlot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final user = auth.appUser;

    // Prefill guardian details from the parent's profile.
    _guardFirst.text = user?.firstName ?? '';
    _guardLast.text = user?.lastName ?? '';
    _guardEmail.text = user?.email ?? '';
    _guardPhone.text = user?.phone ?? '';
    _guardAddress.text = user?.address ?? '';

    final id = widget.applicationId;
    if (id != null) {
      final db = context.read<FirestoreService>();
      final app = await db.watchApplication(id).first;
      if (app != null && app.isDraft && app.parentUid == user?.uid) {
        _appId = app.id;
        _learnerFirst.text = app.learnerFirstName;
        _learnerLast.text = app.learnerLastName;
        _learnerIdNumber.text = app.learnerIdNumber;
        _previousSchool.text = app.previousSchool;
        _idType = app.learnerIdType ?? IdType.saId;
        _dob = app.learnerDob;
        _gender = app.learnerGender;
        _grade =
            app.gradeApplyingFor.isEmpty ? null : app.gradeApplyingFor;
        _language = app.homeLanguage.isEmpty ? null : app.homeLanguage;
        if (app.guardianFirstName.isNotEmpty) {
          _guardFirst.text = app.guardianFirstName;
        }
        if (app.guardianLastName.isNotEmpty) {
          _guardLast.text = app.guardianLastName;
        }
        if (app.guardianPhone.isNotEmpty) _guardPhone.text = app.guardianPhone;
        if (app.guardianEmail.isNotEmpty) _guardEmail.text = app.guardianEmail;
        if (app.guardianAddress.isNotEmpty) {
          _guardAddress.text = app.guardianAddress;
        }
        _relationship = app.guardianRelationship.isEmpty
            ? null
            : app.guardianRelationship;
        _province =
            app.guardianProvince.isEmpty ? null : app.guardianProvince;
        _medical.text = app.medicalConditions;
        _doctorName.text = app.doctorName;
        _doctorPhone.text = app.doctorPhone;
        _emergencyName.text = app.emergencyContactName;
        _emergencyPhone.text = app.emergencyContactPhone;
        _notes.text = app.notes;
        _documents.addAll(app.documents);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [
      _learnerFirst, _learnerLast, _learnerIdNumber, _previousSchool,
      _guardFirst, _guardLast, _guardPhone, _guardEmail, _guardAddress,
      _medical, _doctorName, _doctorPhone, _emergencyName, _emergencyPhone,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _draftData() => {
        'learnerFirstName': _learnerFirst.text.trim(),
        'learnerLastName': _learnerLast.text.trim(),
        'learnerIdType': _idType?.name,
        'learnerIdNumber': _learnerIdNumber.text.trim(),
        // cloud_firestore converts DateTime to Timestamp natively.
        'learnerDob': _dob,
        'learnerGender': _gender?.name,
        'gradeApplyingFor': _grade ?? '',
        'homeLanguage': _language ?? '',
        'previousSchool': _previousSchool.text.trim(),
        'guardianFirstName': _guardFirst.text.trim(),
        'guardianLastName': _guardLast.text.trim(),
        'guardianRelationship': _relationship ?? '',
        'guardianPhone': _guardPhone.text.trim(),
        'guardianEmail': _guardEmail.text.trim(),
        'guardianAddress': _guardAddress.text.trim(),
        'guardianProvince': _province ?? '',
        'medicalConditions': _medical.text.trim(),
        'doctorName': _doctorName.text.trim(),
        'doctorPhone': _doctorPhone.text.trim(),
        'emergencyContactName': _emergencyName.text.trim(),
        'emergencyContactPhone': _emergencyPhone.text.trim(),
        'notes': _notes.text.trim(),
        'documents': _documents,
      };

  /// Creates the draft on first save, then updates it after each step.
  Future<void> _saveDraft() async {
    final db = context.read<FirestoreService>();
    final user = context.read<AuthController>().appUser!;
    final data = _draftData();
    if (_appId == null) {
      _appId = await db.createDraftApplication(user.uid, data);
    } else {
      await db.updateApplication(_appId!, data);
    }
  }

  bool _validateStep(int step) {
    if (step < _stepKeys.length) {
      final form = _stepKeys[step].currentState;
      if (form != null && !form.validate()) return false;
    }
    if (step == 0) {
      if (_dob == null) {
        showSnack(context, "Select the learner's date of birth");
        return false;
      }
      if (_grade == null) {
        showSnack(context, 'Select the grade you are applying for');
        return false;
      }
      final idError =
          IdValidation.validate(_idType, _learnerIdNumber.text, _dob);
      if (idError != null) {
        showSnack(context, idError);
        return false;
      }
    }
    return true;
  }

  Future<void> _next() async {
    if (!_validateStep(_step)) return;
    setState(() => _saving = true);
    try {
      await _saveDraft();
      if (mounted && _step < 4) setState(() => _step += 1);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    final db = context.read<FirestoreService>();
    final user = context.read<AuthController>().appUser!;
    setState(() => _saving = true);
    try {
      await _saveDraft();
      final app = await db.watchApplication(_appId!).first;
      if (app == null) return;
      await db.setApplicationStatus(app, ApplicationStatus.submitted,
          note: 'Application submitted', byName: user.fullName);
      if (!mounted) return;
      showSnack(context, 'Application submitted — you can track it here.');
      context.go(Routes.applicationDetail(_appId!));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not submit: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 6),
      firstDate: DateTime(now.year - 25),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        // SA ID encodes gender — auto-fill when the number is present.
        _gender = IdValidation.genderFromSaId(_learnerIdNumber.text) ?? _gender;
      });
    }
  }

  Future<void> _uploadDocument(String slot, PickedUpload file) async {
    if (_appId == null) {
      // Documents live under the application id; steps 1–3 create it first.
      showSnack(context, 'Complete the earlier steps first');
      return;
    }
    final storage = context.read<StorageService>();
    final db = context.read<FirestoreService>();
    final uid = context.read<AuthController>().appUser!.uid;
    setState(() => _uploadingSlot = slot);
    try {
      final url = await storage.uploadApplicationDocument(
        uid,
        _appId!,
        file.bytes,
        filename: file.filename,
        contentType: file.contentType,
      );
      _documents[slot] = url;
      await db.updateApplication(_appId!, {'documents': _documents});
      if (mounted) showSnack(context, '$slot uploaded');
    } catch (e) {
      if (mounted) showSnack(context, 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploadingSlot = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppShell(
          title: 'Apply',
          body: Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          ));
    }

    return AppShell(
      title: 'Apply',
      breadcrumb: 'Home > Enrollment application',
      body: ContentContainer(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enrollment application',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                'Your progress is saved after every step — you can come back '
                'and finish later.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Stepper(
              currentStep: _step,
              physics: const NeverScrollableScrollPhysics(),
              onStepTapped: (i) {
                // Allow going back freely; going forward uses Continue.
                if (i < _step) setState(() => _step = i);
              },
              controlsBuilder: (context, details) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: [
                    FilledButton(
                      onPressed: _saving
                          ? null
                          : (_step == 4 ? _submit : _next),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : Text(_step == 4
                              ? 'Submit application'
                              : 'Save & continue'),
                    ),
                    const SizedBox(width: 8),
                    if (_step > 0)
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _step -= 1),
                        child: const Text('Back'),
                      ),
                  ],
                ),
              ),
              steps: [
                Step(
                  title: const Text('Learner details'),
                  isActive: _step >= 0,
                  state: _step > 0 ? StepState.complete : StepState.indexed,
                  content: Form(key: _stepKeys[0], child: _learnerStep()),
                ),
                Step(
                  title: const Text('Parent / guardian'),
                  isActive: _step >= 1,
                  state: _step > 1 ? StepState.complete : StepState.indexed,
                  content: Form(key: _stepKeys[1], child: _guardianStep()),
                ),
                Step(
                  title: const Text('Medical & emergency'),
                  isActive: _step >= 2,
                  state: _step > 2 ? StepState.complete : StepState.indexed,
                  content: Form(key: _stepKeys[2], child: _medicalStep()),
                ),
                Step(
                  title: const Text('Supporting documents'),
                  isActive: _step >= 3,
                  state: _step > 3 ? StepState.complete : StepState.indexed,
                  content: _documentsStep(),
                ),
                Step(
                  title: const Text('Review & submit'),
                  isActive: _step >= 4,
                  content: _reviewStep(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _twoUp(Widget a, Widget b) {
    if (context.isMobile) {
      return Column(children: [a, const SizedBox(height: 12), b]);
    }
    return Row(children: [
      Expanded(child: a),
      const SizedBox(width: 12),
      Expanded(child: b),
    ]);
  }

  String? _required(String? v, String label) =>
      (v == null || v.trim().isEmpty) ? '$label is required' : null;

  Widget _learnerStep() {
    return Column(
      children: [
        _twoUp(
          TextFormField(
            controller: _learnerFirst,
            decoration: const InputDecoration(labelText: 'First name'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => _required(v, 'First name'),
          ),
          TextFormField(
            controller: _learnerLast,
            decoration: const InputDecoration(labelText: 'Surname'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => _required(v, 'Surname'),
          ),
        ),
        const SizedBox(height: 12),
        _twoUp(
          DropdownButtonFormField<IdType>(
            initialValue: _idType,
            decoration: const InputDecoration(labelText: 'ID type'),
            items: IdType.values
                .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                .toList(),
            onChanged: (v) => setState(() => _idType = v),
          ),
          TextFormField(
            controller: _learnerIdNumber,
            decoration: InputDecoration(
              labelText: _idType == IdType.passport
                  ? 'Passport number'
                  : 'ID number (13 digits)',
            ),
            onChanged: (v) {
              final g = IdValidation.genderFromSaId(v);
              if (g != null && _idType == IdType.saId) {
                setState(() => _gender = g);
              }
            },
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'ID / passport number is required'
                : null,
          ),
        ),
        const SizedBox(height: 12),
        _twoUp(
          InkWell(
            onTap: _pickDob,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date of birth',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(_dob == null ? 'Select…' : formatDate(_dob)),
            ),
          ),
          DropdownButtonFormField<Gender>(
            initialValue: _gender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: Gender.values
                .map((g) => DropdownMenuItem(value: g, child: Text(g.label)))
                .toList(),
            onChanged: (v) => setState(() => _gender = v),
          ),
        ),
        const SizedBox(height: 12),
        _twoUp(
          DropdownButtonFormField<String>(
            initialValue: _grade,
            decoration:
                const InputDecoration(labelText: 'Grade applying for'),
            items: RefData.grades
                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                .toList(),
            onChanged: (v) => setState(() => _grade = v),
          ),
          DropdownButtonFormField<String>(
            initialValue: _language,
            decoration: const InputDecoration(labelText: 'Home language'),
            items: RefData.languages
                .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                .toList(),
            onChanged: (v) => setState(() => _language = v),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _previousSchool,
          decoration: const InputDecoration(
              labelText: 'Previous school (if any)'),
        ),
      ],
    );
  }

  Widget _guardianStep() {
    return Column(
      children: [
        _twoUp(
          TextFormField(
            controller: _guardFirst,
            decoration: const InputDecoration(labelText: 'First name'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => _required(v, 'First name'),
          ),
          TextFormField(
            controller: _guardLast,
            decoration: const InputDecoration(labelText: 'Surname'),
            textCapitalization: TextCapitalization.words,
            validator: (v) => _required(v, 'Surname'),
          ),
        ),
        const SizedBox(height: 12),
        _twoUp(
          DropdownButtonFormField<String>(
            initialValue: _relationship,
            decoration:
                const InputDecoration(labelText: 'Relationship to learner'),
            items: RefData.guardianRelationships
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) => setState(() => _relationship = v),
            validator: (v) => v == null ? 'Select a relationship' : null,
          ),
          TextFormField(
            controller: _guardPhone,
            decoration: const InputDecoration(labelText: 'Cell phone'),
            keyboardType: TextInputType.phone,
            validator: (v) => _required(v, 'Cell phone'),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _guardEmail,
          decoration: const InputDecoration(
            labelText: 'Email address',
            helperText: 'Application updates are emailed here',
          ),
          keyboardType: TextInputType.emailAddress,
          validator: (v) {
            final s = v?.trim() ?? '';
            if (s.isEmpty) return 'Email is required';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
              return 'Enter a valid email address';
            }
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _guardAddress,
          decoration: const InputDecoration(labelText: 'Home address'),
          minLines: 1,
          maxLines: 3,
          validator: (v) => _required(v, 'Home address'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _province,
          decoration: const InputDecoration(labelText: 'Province'),
          items: RefData.provinces
              .map((p) => DropdownMenuItem(value: p, child: Text(p)))
              .toList(),
          onChanged: (v) => setState(() => _province = v),
        ),
      ],
    );
  }

  Widget _medicalStep() {
    return Column(
      children: [
        TextFormField(
          controller: _medical,
          decoration: const InputDecoration(
            labelText: 'Medical conditions / allergies',
            helperText: 'Leave blank if none',
          ),
          minLines: 2,
          maxLines: 4,
        ),
        const SizedBox(height: 12),
        _twoUp(
          TextFormField(
            controller: _doctorName,
            decoration:
                const InputDecoration(labelText: 'Family doctor (optional)'),
          ),
          TextFormField(
            controller: _doctorPhone,
            decoration:
                const InputDecoration(labelText: 'Doctor phone (optional)'),
            keyboardType: TextInputType.phone,
          ),
        ),
        const SizedBox(height: 12),
        _twoUp(
          TextFormField(
            controller: _emergencyName,
            decoration:
                const InputDecoration(labelText: 'Emergency contact name'),
            validator: (v) => _required(v, 'Emergency contact name'),
          ),
          TextFormField(
            controller: _emergencyPhone,
            decoration:
                const InputDecoration(labelText: 'Emergency contact phone'),
            keyboardType: TextInputType.phone,
            validator: (v) => _required(v, 'Emergency contact phone'),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notes,
          decoration: const InputDecoration(
              labelText: 'Anything else the school should know? (optional)'),
          minLines: 2,
          maxLines: 4,
        ),
      ],
    );
  }

  Widget _documentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            'Upload clear photos or PDFs. The birth certificate / ID is '
            'required; add the others if you have them.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        ..._documentSlots.map((slot) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: UploadButton(
                label: slot,
                busy: _uploadingSlot == slot,
                filename: _documents.containsKey(slot) ? 'Uploaded ✓' : null,
                onPicked: (f) => _uploadDocument(slot, f),
              ),
            )),
      ],
    );
  }

  Widget _reviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          title: 'Learner',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoLine('Name',
                  '${_learnerFirst.text} ${_learnerLast.text}'.trim()),
              InfoLine(_idType?.label ?? 'ID', _learnerIdNumber.text),
              InfoLine('Date of birth', formatDate(_dob)),
              InfoLine('Gender', _gender?.label ?? '—'),
              InfoLine('Grade', _grade ?? '—'),
              InfoLine('Home language', _language ?? '—'),
              if (_previousSchool.text.isNotEmpty)
                InfoLine('Previous school', _previousSchool.text),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Parent / guardian',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoLine('Name',
                  '${_guardFirst.text} ${_guardLast.text}'.trim()),
              InfoLine('Relationship', _relationship ?? '—'),
              InfoLine('Phone', _guardPhone.text),
              InfoLine('Email', _guardEmail.text),
              InfoLine('Address', _guardAddress.text),
              InfoLine('Province', _province ?? '—'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Documents',
          child: _documents.isEmpty
              ? const Text('No documents uploaded',
                  style: TextStyle(color: Colors.grey))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _documents.keys
                      .map((d) => Row(children: [
                            const Icon(Icons.check_circle,
                                size: 16, color: Colors.green),
                            const SizedBox(width: 6),
                            Text(d),
                          ]))
                      .toList(),
                ),
        ),
        const SizedBox(height: 12),
        Text(
            'By submitting you confirm the information above is true and '
            'complete. The school will review your application and email '
            'you as it progresses.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
