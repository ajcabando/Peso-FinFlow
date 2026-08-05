import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../providers/security_providers.dart';
import 'pin_pad.dart';

/// Bottom sheet that walks the user through choosing (and confirming) a new
/// 4–8 digit PIN. Used for both first-time setup and changing an existing
/// PIN (the app is already unlocked at that point).
Future<void> showPinSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _PinSetupSheet(),
  );
}

class _PinSetupSheet extends ConsumerStatefulWidget {
  const _PinSetupSheet();

  @override
  ConsumerState<_PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends ConsumerState<_PinSetupSheet> {
  String? _firstPin;
  int _errorKey = 0;
  String? _errorMessage;
  bool _saving = false;

  bool get _confirming => _firstPin != null;

  void _resetAttempt(String message) {
    setState(() {
      _errorKey++;
      _errorMessage = message;
    });
  }

  Future<void> _handlePin(String pin) async {
    if (_confirming) {
      if (pin != _firstPin) {
        _resetAttempt('PINs do not match. Try again.');
        return;
      }
      setState(() {
        _saving = true;
        _errorMessage = null;
      });
      try {
        await ref
            .read(securityControllerProvider.notifier)
            .setPin(pin);
        if (!mounted) return;
        Navigator.of(context).pop();
      } on Exception catch (error) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _errorMessage = error.toString();
        });
      }
      return;
    }

    setState(() {
      _firstPin = pin;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _confirming ? 'Confirm your PIN' : 'Create a PIN',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _confirming
                  ? 'Enter it once more to lock FinFlow'
                  : '4–8 digits. Used to unlock the app.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
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
              key: ValueKey(_confirming ? 'pin-pad-confirm' : 'pin-pad-create'),
              errorKey: _errorKey,
              onSubmitted: _handlePin,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_saving)
              const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
          ],
        ),
      ),
    );
  }
}
