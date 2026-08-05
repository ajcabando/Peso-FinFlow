import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/biometric_service.dart';
import '../providers/security_providers.dart';
import '../widgets/pin_pad.dart';

/// The full-screen lock shown when a PIN is configured and the app is
/// locked (startup or after backgrounding).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  int _errorKey = 0;
  String? _errorMessage;
  bool _checkingBiometrics = false;

  Future<void> _submit(String pin) async {
    final ok = await ref.read(securityControllerProvider.notifier).verifyPin(pin);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _errorKey++;
        _errorMessage = 'Incorrect PIN. Try again.';
      });
    }
  }

  Future<void> _unlockWithBiometrics() async {
    setState(() => _checkingBiometrics = true);
    final ok = await BiometricService.authenticate();
    if (!mounted) return;
    setState(() => _checkingBiometrics = false);
    if (ok) {
      ref.read(securityControllerProvider.notifier).unlock();
    } else {
      setState(() => _errorMessage = 'Biometric unlock failed or cancelled.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final security = ref.watch(securityControllerProvider);
    final heroGradient =
        theme.extension<FinFlowTheme>()?.heroGradient ??
        const [Color(0xFF9C6BFF), Color(0xFF6D5DF6)];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: heroGradient,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: heroGradient.last.withValues(alpha: 0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Enter your PIN',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'FinFlow is locked',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              PinPad(
                errorKey: _errorKey,
                onSubmitted: _submit,
                accent: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (security.biometricsEnabled) ...[
                TextButton.icon(
                  onPressed: _checkingBiometrics ? null : _unlockWithBiometrics,
                  icon: _checkingBiometrics
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.fingerprint_rounded),
                  label: const Text('Use biometrics'),
                ),
              ] else
                const SizedBox(height: 52),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
