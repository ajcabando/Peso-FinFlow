import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/update_checker.dart';
import '../../domain/update_info.dart';

/// Where the manual update check currently stands.
enum UpdateCheckState {
  /// No check has run yet in this session.
  idle,

  /// The latest release is being fetched.
  checking,

  /// The installed build is the newest release.
  upToDate,

  /// A newer release exists — see [UpdateStatus.latest].
  updateAvailable,

  /// The check failed — see [UpdateStatus.error].
  error,
}

/// Snapshot of the update check, exposed to the Settings About card.
class UpdateStatus {
  const UpdateStatus({
    this.state = UpdateCheckState.idle,
    this.currentVersion,
    this.latest,
    this.error,
  });

  final UpdateCheckState state;

  /// The installed app version (from package_info, e.g. `0.2.0`), once read.
  final String? currentVersion;

  /// The newest release when [state] is [UpdateCheckState.updateAvailable].
  final UpdateInfo? latest;

  /// A user-facing message when [state] is [UpdateCheckState.error].
  final String? error;

  UpdateStatus copyWith({
    UpdateCheckState? state,
    String? currentVersion,
    UpdateInfo? latest,
    String? error,
  }) => UpdateStatus(
    state: state ?? this.state,
    currentVersion: currentVersion ?? this.currentVersion,
    latest: latest ?? this.latest,
    error: error ?? this.error,
  );
}

/// The [UpdateChecker] used by the controller. Override in tests to avoid
/// real network calls.
final updateCheckerProvider = Provider<UpdateChecker>(
  (ref) => UpdateChecker(),
);

/// The update-check state for Settings → About.
final updateControllerProvider = NotifierProvider<UpdateController, UpdateStatus>(
  UpdateController.new,
);

class UpdateController extends Notifier<UpdateStatus> {
  /// Sentinel for "we could not read the installed version". The check is
  /// gated on this so users are never told a release is newer than an unknown
  /// version.
  static const String kUnknownVersion = '0.0.0';

  @override
  UpdateStatus build() {
    _loadCurrentVersion();
    return const UpdateStatus();
  }

  Future<void> _loadCurrentVersion() async {
    final version = await _readInstalledVersion();
    state = state.copyWith(currentVersion: version);
  }

  /// Reads the installed version from package_info, falling back to
  /// [kUnknownVersion] when the plugin is unavailable (tests, edge platforms).
  Future<String> _readInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) return info.version;
    } on Exception {
      // Fall through to the fallback.
    }
    return kUnknownVersion;
  }

  /// Runs the check against the GitHub releases feed and returns the
  /// resulting [UpdateStatus] (also stored as [state]).
  ///
  /// Fresh [UpdateStatus] instances are built for every transition (never
  /// copyWith) so a stale `latest`/`error` from a previous check can't linger.
  Future<UpdateStatus> checkForUpdates() async {
    state = const UpdateStatus(state: UpdateCheckState.checking);
    try {
      final current = state.currentVersion ?? await _readInstalledVersion();
      if (current.isEmpty || current == kUnknownVersion) {
        state = UpdateStatus(
          state: UpdateCheckState.error,
          currentVersion: current,
          error: "Couldn't determine the installed version.",
        );
        return state;
      }
      final latest = await ref
          .read(updateCheckerProvider)
          .check(currentVersion: current);
      state = latest == null
          ? UpdateStatus(
              state: UpdateCheckState.upToDate,
              currentVersion: current,
            )
          : UpdateStatus(
              state: UpdateCheckState.updateAvailable,
              currentVersion: current,
              latest: latest,
            );
    } on UpdateCheckException catch (error) {
      state = UpdateStatus(state: UpdateCheckState.error, error: error.message);
    } on Exception {
      state = const UpdateStatus(
        state: UpdateCheckState.error,
        error: "Couldn't check for updates.",
      );
    }
    return state;
  }
}
