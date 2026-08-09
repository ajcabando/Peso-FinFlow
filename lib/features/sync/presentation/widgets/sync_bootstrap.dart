import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../data/auth/token_store.dart';
import '../providers/sync_providers.dart';

/// Mounted once at the app root. Owns the sync session's background work:
///
///  * reacts to auth session changes (sign-in adopts + syncs),
///  * pushes shortly after any local database write (debounced),
///  * syncs when the app returns to the foreground,
///  * re-syncs periodically while signed in.
///
/// With no `FINFLOW_API_URL` define, everything here is a no-op (fully local).
class SyncBootstrap extends ConsumerStatefulWidget {
  const SyncBootstrap({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncBootstrap> createState() => _SyncBootstrapState();
}

class _SyncBootstrapState extends ConsumerState<SyncBootstrap>
    with WidgetsBindingObserver {
  StreamSubscription<Set<TableUpdate>>? _dbSub;
  Timer? _debounce;
  Timer? _periodic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!ref.read(syncConfigProvider).enabled) return;

    _dbSub = ref.read(databaseProvider).tableUpdates().listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), _syncNow);
    });
    _periodic = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _syncNow(),
    );

    // A session may already be persisted from a previous launch.
    _handleInitialSession();
  }

  void _handleInitialSession() {
    final auth = ref.read(authServiceProvider);
    if (auth == null) return;
    auth.currentSession().then((session) {
      if (session != null && session.userId.isNotEmpty) {
        ref.read(syncControllerProvider.notifier).onSessionChanged(session);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncNow();
  }

  void _syncNow() {
    final controller = ref.read(syncControllerProvider.notifier);
    controller.syncNow();
    // Heartbeat for the (daily/weekly/monthly) cloud-backup schedule — the
    // picker sets the cadence, this timer decides *when* it fires.
    controller.maybeRunScheduledBackup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dbSub?.cancel();
    _debounce?.cancel();
    _periodic?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Live auth changes (sign-in/out, token refresh) drive the controller.
    ref.listen<AsyncValue<AuthTokens?>>(authSessionProvider, (previous, next) {
      final session = next.valueOrNull;
      if (session != null && session.userId.isEmpty) return;
      ref.read(syncControllerProvider.notifier).onSessionChanged(session);
    });
    return widget.child;
  }
}
