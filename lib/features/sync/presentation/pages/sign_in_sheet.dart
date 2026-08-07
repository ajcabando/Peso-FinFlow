import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_button.dart';
import '../providers/sync_providers.dart';

/// Opens the sign-in sheet.
Future<void> showSignInSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: const SignInSheet(),
    ),
  );
}

/// Email/password or phone-OTP sign in / sign up.
class SignInSheet extends ConsumerStatefulWidget {
  const SignInSheet({super.key});

  @override
  ConsumerState<SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<SignInSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  bool _createAccount = false;
  bool _otpSent = false;
  bool _busy = false;
  String _mode = 'email'; // 'email' | 'phone'

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(syncControllerProvider.notifier);
    setState(() => _busy = true);
    try {
      if (_mode == 'email') {
        final email = _email.text.trim();
        final password = _password.text;
        if (!_validEmail(email)) {
          throw StateError('Enter a valid email address.');
        }
        if (password.length < 6) {
          throw StateError('Password must be at least 6 characters.');
        }
        if (_createAccount) {
          await controller.signUp(email, password);
        } else {
          await controller.signInWithEmail(email, password);
        }
      } else {
        final phone = _phone.text.trim();
        if (phone.length < 7) {
          throw StateError('Enter your phone number with country code.');
        }
        if (!_otpSent) {
          await controller.sendPhoneOtp(phone);
          setState(() => _otpSent = true);
          messenger.showSnackBar(
            const SnackBar(content: Text('Code sent — check your phone.')),
          );
          return;
        }
        final token = _otp.text.trim();
        if (token.isEmpty) {
          throw StateError('Enter the code you received.');
        }
        await controller.verifyPhoneOtp(phone, token);
      }
      if (mounted) {
        Navigator.of(context).pop();
        context.showSnack('Signed in — syncing your data…');
      }
    } on Exception catch (e) {
      if (mounted) {
        context.showSnack(
          e.toString().replaceFirst('Exception: ', '').replaceFirst(
            'AuthException: ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static bool _validEmail(String value) {
    final at = value.indexOf('@');
    return at > 0 && at < value.length - 1 && !value.contains(' ');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Sign in to sync',
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Your data stays on this device — signing in mirrors it to '
              'your account so it can follow you across devices.',
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'email', label: Text('Email')),
                ButtonSegment(value: 'phone', label: Text('Phone')),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_mode == 'email') ...[
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline, size: 20),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline, size: 20),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ] else ...[
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+63917 000 0000',
                  prefixIcon: Icon(Icons.phone_outlined, size: 20),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _otpSent
                    ? 'Enter the 6-digit code sent to your phone.'
                    : 'We send a one-time code by SMS. Phone sign-in needs '
                          'an SMS provider enabled in Supabase.',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (_otpSent) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _otp,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    prefixIcon: Icon(Icons.sms_outlined, size: 20),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: _mode == 'email'
                  ? (_createAccount ? 'Create account' : 'Sign in')
                  : (_otpSent ? 'Verify & sign in' : 'Send code'),
              icon: _mode == 'email'
                  ? (_createAccount ? Icons.person_add_alt : Icons.login)
                  : (_otpSent ? Icons.verified_user_outlined : Icons.sms_outlined),
              loading: _busy,
              onPressed: _busy ? null : _submit,
            ),
            if (_mode == 'email') ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton(
                  onPressed: () =>
                      setState(() => _createAccount = !_createAccount),
                  child: Text(
                    _createAccount
                        ? 'Have an account? Sign in'
                        : 'New here? Create an account',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
