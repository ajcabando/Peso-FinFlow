import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_spacing.dart';

/// A numeric keypad with dot indicators and a submit checkmark.
///
/// Accumulates digits locally and calls [onSubmitted] with the PIN once the
/// checkmark is pressed (enabled at 4+ digits). The parent decides success;
/// bumping [errorKey] clears the entry and plays a shake so the user knows
/// the attempt was wrong.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onSubmitted,
    this.errorKey = 0,
    this.accent,
    this.autofocus = true,
  });

  final ValueChanged<String> onSubmitted;

  /// Any change to this value triggers the error shake + clear.
  final int errorKey;

  final Color? accent;

  /// Focuses the keypad on first build (physical-keyboard support).
  final bool autofocus;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  final TextEditingController _pin = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _shakeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _shake = Tween(
    begin: 0.0,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn));

  int get _length => _pin.text.length;

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant PinPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.errorKey != oldWidget.errorKey) {
      _shakeController.forward(from: 0);
      _pin.clear();
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  void _append(String digit) {
    if (_length >= 8) return;
    _pin.text += digit;
  }

  void _backspace() {
    if (_length == 0) return;
    _pin.text = _pin.text.substring(0, _length - 1);
  }

  void _submit() {
    if (_length < 4) return;
    final value = _pin.text;
    _pin.clear();
    widget.onSubmitted(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accent ?? theme.colorScheme.primary;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        // Physical keyboard support: digits + backspace + enter.
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key.keyLabel.length == 1 &&
              RegExp(r'^\d$').hasMatch(key.keyLabel)) {
            _append(key.keyLabel);
            setState(() {});
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.backspace) {
            _backspace();
            setState(() {});
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.enter) {
            _submit();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dots.
          AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) => Transform.translate(
              offset: Offset(_shake.value * 18, 0),
              child: child,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 8; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _length
                          ? accent
                          : accent.withValues(alpha: 0.18),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          // Keypad rows.
          for (var row = 0; row < 3; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var col = 0; col < 3; col++)
                    _key(context, '${row * 3 + col + 1}', accent),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 72, height: 72),
              _key(context, '0', accent),
              SizedBox(
                width: 72,
                height: 72,
                child: IconButton(
                  tooltip: 'Backspace',
                  onPressed: () => setState(_backspace),
                  icon: const Icon(Icons.backspace_outlined, size: 26),
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SubmitButton(
            accent: accent,
            enabled: _length >= 4,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _key(BuildContext context, String digit, Color accent) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 72,
      height: 72,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _append(digit)),
            customBorder: const CircleBorder(),
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.55,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  digit,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.accent,
    required this.enabled,
    required this.onPressed,
  });

  final Color accent;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Submit PIN',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: enabled
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent, accent.withValues(alpha: 0.75)],
                )
              : null,
          color: enabled
              ? null
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            customBorder: const CircleBorder(),
            child: Icon(
              Icons.check_rounded,
              color: enabled ? Colors.white : Colors.transparent,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}
