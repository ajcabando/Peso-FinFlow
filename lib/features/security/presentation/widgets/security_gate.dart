import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/security_providers.dart';
import '../pages/lock_screen.dart';

/// Wraps the whole app. Shows the [LockScreen] while a PIN is configured and
/// the app is locked, and re-locks automatically when the app is backgrounded
/// (when auto-lock is enabled).
class SecurityGate extends ConsumerStatefulWidget {
  const SecurityGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends ConsumerState<SecurityGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final security = ref.read(securityControllerProvider);
    if (state == AppLifecycleState.paused &&
        security.hasPin &&
        security.autoLockEnabled) {
      ref.read(securityControllerProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = ref.watch(securityControllerProvider);
    if (security.hasPin && security.locked) {
      return const LockScreen();
    }
    return widget.child;
  }
}
