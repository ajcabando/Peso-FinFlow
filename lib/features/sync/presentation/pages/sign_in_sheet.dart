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

/// Email/password sign in or sign up against the self-hosted backend.
class SignInSheet extends ConsumerStatefulWidget {
  const SignInSheet({super.key});

  @override
  ConsumerState<SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<SignInSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _createAccount = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(syncControllerProvider.notifier);
    setState(() => _busy = true);
    try {
      final email = _email.text.trim();
      final password = _password.text;
      if (!_validEmail(email)) {
        throw StateError('Enter a valid email address.');
      }
      if (password.length < 8) {
        throw StateError('Password must be at least 8 characters.');
      }
      if (_createAccount) {
        await controller.signUp(email, password);
      } else {
        await controller.signInWithEmail(email, password);
      }
      if (mounted) {
        Navigator.of(context).pop();
        context.showSnack('Signed in — syncing your data…');
      }
    } on Exception catch (e) {
      if (mounted) {
        context.showSnack(
          e.toString().replaceFirst('Exception: ', ''),
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
              _createAccount ? 'Create your account' : 'Sign in to sync',
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Your data stays on this device — signing in mirrors it to '
              'your own server so it can follow you across devices.',
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
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
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: _createAccount ? 'Create account' : 'Sign in',
              icon: _createAccount
                  ? Icons.person_add_alt
                  : Icons.login,
              loading: _busy,
              onPressed: _busy ? null : _submit,
            ),
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
        ),
      ),
    );
  }
}
