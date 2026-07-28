import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../models/enums.dart';
import '../../router/app_router.dart';
import '../../state/auth_controller.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Create/edit the signed-in user's profile. Every authenticated user is
/// presented with this after first sign-in; for parents it unlocks applying
/// for a child, and the email captured here receives school notifications.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthController>().appUser;
    _firstName = TextEditingController(text: u?.firstName ?? '');
    _lastName = TextEditingController(text: u?.lastName ?? '');
    _email = TextEditingController(text: u?.email ?? '');
    _address = TextEditingController(text: u?.address ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthController>();
    final firstTime = auth.needsProfile;
    final ok = await auth.saveProfile(
      firstName: _firstName.text,
      lastName: _lastName.text,
      email: _email.text,
      address: _address.text,
    );
    if (!mounted) return;
    if (ok) {
      showSnack(context, 'Profile saved');
      if (firstTime) context.go(homeFor(auth.role, false));
    } else {
      showSnack(context, auth.error ?? 'Could not save profile');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final user = auth.appUser;
    final firstTime = auth.needsProfile;
    final isParent = user?.role == UserRole.parent;

    return AppShell(
      title: 'My profile',
      body: ContentContainer(
        maxWidth: 560,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              if (firstTime) ...[
                Text('Create your profile',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  isParent
                      ? 'Tell us who you are so you can apply for your child. '
                          'We send application and payment updates to the '
                          'email address below.'
                      : 'Confirm your details to continue.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
              ],
              SectionCard(
                title: 'Your details',
                child: Column(
                  children: [
                    if (user?.phone != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: InfoLine('Signed in as',
                            '${user!.phone} (${user.role.label})'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _firstName,
                      decoration:
                          const InputDecoration(labelText: 'First name'),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'First name is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _lastName,
                      decoration: const InputDecoration(labelText: 'Surname'),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Surname is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        helperText:
                            'School notifications are emailed to this address',
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
                      controller: _address,
                      decoration: const InputDecoration(
                          labelText: 'Home address (optional)'),
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: auth.busy ? null : _save,
                child: Text(firstTime ? 'Create profile' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
