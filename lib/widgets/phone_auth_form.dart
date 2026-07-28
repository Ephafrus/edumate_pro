import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../state/auth_controller.dart';

/// Two-step phone (OTP) auth used by every role. Uses a country phone picker
/// (works on web, Android and iOS) for the number and a segmented OTP pin
/// input for the SMS code. Calls [onVerified] on success.
class PhoneAuthForm extends StatefulWidget {
  const PhoneAuthForm({super.key, required this.onVerified});
  final VoidCallback onVerified;

  @override
  State<PhoneAuthForm> createState() => _PhoneAuthFormState();
}

class _PhoneAuthFormState extends State<PhoneAuthForm> {
  final _codeCtrl = TextEditingController();
  String _completeNumber = '';
  PhoneVerification? _verification;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_completeNumber.trim().isEmpty) {
      setState(() => _error = 'Enter your cell phone number');
      return;
    }
    setState(() => _error = null);
    final auth = context.read<AuthController>();
    final v = await auth.startPhoneVerification(_completeNumber);
    if (!mounted) return;
    if (v == null) {
      setState(() => _error = auth.error ?? 'Could not send code');
      return;
    }
    setState(() => _verification = v);
  }

  Future<void> _verify() async {
    if (_verification == null) return;
    setState(() => _error = null);
    final auth = context.read<AuthController>();
    final ok =
        await auth.confirmPhoneCode(_verification!, _codeCtrl.text.trim());
    if (!mounted) return;
    if (ok) {
      widget.onVerified();
    } else {
      setState(() => _error = auth.error ?? 'Invalid code');
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthController>().busy;
    final codeSent = _verification != null;

    const pinTextStyle = TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
    final pinTheme = PinTheme(
      width: 48,
      height: 52,
      textStyle: pinTextStyle,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
    final focusedPinTheme = PinTheme(
      width: 48,
      height: 52,
      textStyle: pinTextStyle,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: Theme.of(context).colorScheme.primary, width: 2),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntlPhoneField(
          enabled: !codeSent,
          initialCountryCode: 'ZA',
          decoration: const InputDecoration(
            labelText: 'Cell phone number',
            border: OutlineInputBorder(),
          ),
          onChanged: (phone) => _completeNumber = phone.completeNumber,
        ),
        const SizedBox(height: 12),
        if (codeSent) ...[
          Text('Enter the 6-digit code sent to $_completeNumber',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Center(
            child: Pinput(
              length: 6,
              controller: _codeCtrl,
              defaultPinTheme: pinTheme,
              focusedPinTheme: focusedPinTheme,
              onCompleted: (_) => _verify(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: busy ? null : (codeSent ? _verify : _sendCode),
          child: busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(codeSent ? 'Verify' : 'Send code'),
        ),
        if (codeSent)
          TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                      _verification = null;
                      _codeCtrl.clear();
                    }),
            child: const Text('Use a different number'),
          ),
      ],
    );
  }
}
