import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../core/sync_session.dart';
import '../../data/supabase_sync_remote.dart';
import '../../data/sync_engine.dart';
import '../../data/sync_remote.dart';
import '../../domain/sync_config.dart';
import '../../domain/sync_status.dart';

/// Cloud-sync configuration (dart-defines; disabled when absent).
final syncConfigProvider = Provider<SyncConfig>(
  (ref) => SyncConfig.fromEnvironment(),
);

/// The Supabase client, or `null` when sync is not configured.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  final config = ref.watch(syncConfigProvider);
  if (!config.enabled) return null;
  return Supabase.instance.client;
});

final syncRemoteProvider = Provider<SyncRemote?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return SupabaseSyncRemote(client: client);
});

final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final remote = ref.watch(syncRemoteProvider);
  if (remote == null) return null;
  return SyncEngine(db: ref.watch(databaseProvider), remote: remote);
});

/// The current auth session: the persisted session first, then live changes.
/// `null` while signed out (or when sync is not configured).
final authSessionProvider = StreamProvider<Session?>((ref) async* {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    yield null;
    return;
  }
  yield client.auth.currentSession;
  yield* client.auth.onAuthStateChange.map((data) => data.session);
});

/// Sync + auth controller for the Settings sync section.
final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class SyncController extends Notifier<SyncStatus> {
  SupabaseClient? get _client => ref.read(supabaseClientProvider);
  SyncEngine? get _engine => ref.read(syncEngineProvider);

  /// The last session id this controller processed — guards against the same
  /// session being delivered twice (cold start: initial-session handler +
  /// the auth stream both emit the persisted session).
  String? _handledSessionUserId;

  @override
  SyncStatus build() => SyncStatus(enabled: ref.watch(syncConfigProvider).enabled);

  /// Called whenever the auth session changes (sign-in, sign-out, restore).
  Future<void> onSessionChanged(Session? session) async {
    if (session == null) {
      _handledSessionUserId = null;
      SyncSession.instance.userId = null;
      state = state.copyWith(
        signedIn: false,
        userId: null,
        email: null,
        syncing: false,
        error: null,
      );
      return;
    }
    final userId = session.user.id;
    if (userId == _handledSessionUserId && state.signedIn) {
      return; // Same session re-delivered — already adopting/syncing.
    }
    _handledSessionUserId = userId;
    final email = session.user.email ?? session.user.phone;
    SyncSession.instance.userId = userId;
    state = state.copyWith(
      signedIn: true,
      userId: userId,
      email: email,
      syncing: true,
      error: null,
    );
    final engine = _engine;
    if (engine == null) {
      state = state.copyWith(syncing: false);
      return;
    }
    try {
      await engine.adoptLocalData(userId);
      await _runSync(engine, userId);
    } on Exception catch (e) {
      state = state.copyWith(syncing: false, error: _message(e));
    }
  }

  /// Manually triggered sync (button, app resume, periodic timer, or a
  /// debounce after a local write).
  Future<void> syncNow() async {
    final engine = _engine;
    final userId = state.userId;
    if (engine == null || userId == null) return;
    if (state.syncing) return;
    state = state.copyWith(syncing: true, clearError: true);
    await _runSync(engine, userId);
  }

  Future<void> _runSync(SyncEngine engine, String userId) async {
    // The engine busy-guards re-entrant calls itself.
    final result = await engine.sync(userId);
    // `SyncEngine.sync` never throws — it returns a result. Surface failures
    // instead of pretending the sync succeeded.
    state = state.copyWith(
      syncing: false,
      lastSyncedAt: result.ok ? DateTime.now() : null,
      error: result.ok ? null : result.error,
    );
  }

  Future<void> signInWithEmail(String email, String password) =>
      _guard(() => _client!.auth.signInWithPassword(email: email, password: password));

  Future<void> signUp(String email, String password) => _guard(
    () => _client!.auth.signUp(email: email, password: password),
  );

  Future<void> sendPhoneOtp(String phone) =>
      _guard(() => _client!.auth.signInWithOtp(phone: phone));

  Future<void> verifyPhoneOtp(String phone, String token) => _guard(
    () => _client!.auth.verifyOTP(
      phone: phone,
      token: token,
      type: OtpType.sms,
    ),
  );

  Future<void> signOut() async {
    final client = _client;
    if (client == null) return;
    await client.auth.signOut();
    // onSessionChanged(null) fires via the auth stream.
  }

  Future<void> _guard(Future<void> Function() action) async {
    final client = _client;
    if (client == null) {
      throw StateError('Cloud sync is not configured for this build.');
    }
    await action();
  }

  static String _message(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
