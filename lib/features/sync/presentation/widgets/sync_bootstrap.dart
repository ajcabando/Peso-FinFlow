import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide TableUpdate;

import '../../../../app/providers/app_providers.dart';
import '../providers/sync_providers.dart';

/// Mounted once at the app root. Owns the sync session's background work:
///
///  * reacts to Supabase auth state changes (sign-in adopts + syncs),
///  * pushes shortly after any local database write (debounced),
///  * syncs when the app returns to the foreground,
///  * re-syncs periodically while signed in.
///
/// With no Supabase credentials compiled in, everything here is a no-op.
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

    final engine = ref.read(syncEngineProvider);
    if (engine == null) return;

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
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        ref.read(syncControllerProvider.notifier).onSessionChanged(session);
      }
    } on Object {
      // Supabase not initialised / no session — signed out state.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncNow();
  }

  void _syncNow() => ref.read(syncControllerProvider.notifier).syncNow();

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
    ref.listen<AsyncValue<Session?>>(authSessionProvider, (previous, next) {
      ref
          .read(syncControllerProvider.notifier)
          .onSessionChanged(next.valueOrNull);
    });
    return widget.child;
  }
}
