import 'package:finflow/features/settings/presentation/pages/settings_page.dart';
import 'package:finflow/features/sync/domain/sync_status.dart';
import 'package:finflow/shared/widgets/app_button.dart';
import 'package:finflow/features/sync/presentation/providers/sync_providers.dart';
import 'package:finflow/features/updates/domain/update_info.dart';
import 'package:finflow/features/updates/presentation/providers/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';
import '../helpers/widget_harness.dart';

/// A [UpdateController] serving a fixed status, so the About card can be
/// exercised in every state without touching package_info or the network.
class FakeUpdateController extends UpdateController {
  FakeUpdateController(this._status);

  final UpdateStatus _status;

  @override
  UpdateStatus build() => _status;

  @override
  Future<UpdateStatus> checkForUpdates() async => _status;
}

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    addTearDown(harness.dispose);
  });

  Future<void> pumpSettings(
    WidgetTester tester,
    UpdateStatus status,
  ) async {
    await tester.pumpWidget(
      pumpApp(
        harness.db,
        child: const SettingsPage(),
        categories: const [],
        extraOverrides: [
          syncControllerProvider.overrideWith(
            () => FakeSyncController(const SyncStatus(enabled: true)),
          ),
          updateControllerProvider.overrideWith(
            () => FakeUpdateController(status),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollToAbout(WidgetTester tester) async {
    // The About card sits at the very bottom of the Settings list; scroll to
    // the stable section header (the button label varies by state).
    await tester.scrollUntilVisible(
      find.text('About'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Settle the scroll physics with fixed pumps instead of pumpAndSettle:
    // in the checking state the button's indeterminate spinner animates
    // forever and would time out a pumpAndSettle.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  testWidgets('About card shows the installed version', (tester) async {
    await pumpSettings(
      tester,
      const UpdateStatus(currentVersion: '0.2.0'),
    );
    await scrollToAbout(tester);

    expect(find.textContaining('Version 0.2.0'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets('shows the checking state and disables the button', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      const UpdateStatus(state: UpdateCheckState.checking, currentVersion: '0.2.0'),
    );
    await scrollToAbout(tester);

    // AppButton swaps its label for a spinner while loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<AppButton>(
      find.ancestor(
        of: find.byType(CircularProgressIndicator),
        matching: find.byType(AppButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('check on the latest build shows the up-to-date snackbar', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      const UpdateStatus(
        state: UpdateCheckState.upToDate,
        currentVersion: '0.2.0',
      ),
    );
    await scrollToAbout(tester);

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.text("You're up to date — v0.2.0"), findsOneWidget);
  });

  testWidgets('a newer release opens the update dialog', (tester) async {
    await pumpSettings(
      tester,
      UpdateStatus(
        state: UpdateCheckState.updateAvailable,
        currentVersion: '0.2.0',
        latest: const UpdateInfo(
          version: '0.3.0',
          url: 'https://github.com/ajcabando/Peso-FinFlow/releases/tag/v0.3.0',
        ),
      ),
    );
    await scrollToAbout(tester);

    // The button itself advertises the new version.
    expect(find.text('Update available — v0.3.0'), findsOneWidget);

    await tester.tap(find.text('Update available — v0.3.0'));
    await tester.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.textContaining('v0.3.0 is ready to install'), findsOneWidget);
    expect(find.text('View release'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    // Closing with "Not now" dismisses the dialog without navigating.
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsNothing);
  });

  testWidgets('a failed check surfaces the error message', (tester) async {
    await pumpSettings(
      tester,
      const UpdateStatus(
        state: UpdateCheckState.error,
        error: 'The update server returned 403.',
      ),
    );
    await scrollToAbout(tester);

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.text('The update server returned 403.'), findsOneWidget);
  });
}

/// A [SyncController] serving a fixed status so the Settings page renders
/// without touching the network.
class FakeSyncController extends SyncController {
  FakeSyncController(this._status);

  final SyncStatus _status;

  @override
  SyncStatus build() => _status;
}
