import 'package:finflow/features/settings/presentation/pages/settings_page.dart';
import 'package:finflow/features/sync/domain/sync_status.dart';
import 'package:finflow/features/sync/presentation/providers/sync_providers.dart';
import 'package:finflow/features/sync/presentation/widgets/sync_card.dart';
import 'package:finflow/shared/widgets/section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';
import '../helpers/widget_harness.dart';

/// A [SyncController] that serves a fixed status, so tests can render every
/// state of the Account & sync section without touching the network.
class FakeSyncController extends SyncController {
  FakeSyncController(this._status);

  final SyncStatus _status;

  @override
  SyncStatus build() => _status;
}

void main() {
  late TestHarness harness;

  setUp(() async {
    harness = await TestHarness.create();
    addTearDown(harness.dispose);
  });

  Future<void> pumpSyncCard(WidgetTester tester, SyncStatus status) async {
    await tester.pumpWidget(
      pumpApp(
        harness.db,
        child: const SyncCard(),
        extraOverrides: [
          syncControllerProvider.overrideWith(
            () => FakeSyncController(status),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SyncCard', () {
    testWidgets('signed out shows the sign-in card', (tester) async {
      await pumpSyncCard(
        tester,
        const SyncStatus(enabled: true),
      );

      expect(find.text('Sign in to sync'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.text('Sync now'), findsNothing);
    });

    testWidgets('not configured shows the local-only card', (tester) async {
      await pumpSyncCard(
        tester,
        const SyncStatus(enabled: false),
      );

      expect(find.text('Cloud sync is off'), findsOneWidget);
      expect(find.text('Sign in to sync'), findsNothing);
    });

    testWidgets('signed in shows account, sync controls and devices',
        (tester) async {
      await pumpSyncCard(
        tester,
        SyncStatus(
          enabled: true,
          signedIn: true,
          email: 'me@finflow.dev',
          lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
          devices: const [
            CloudDevice(
              id: 'd1',
              name: 'iPhone',
              platform: 'ios',
              appVersion: '0.2.0',
              current: true,
            ),
            CloudDevice(
              id: 'd2',
              name: 'MacBook',
              platform: 'macos',
              appVersion: '0.2.0',
            ),
          ],
        ),
      );

      expect(find.text('me@finflow.dev'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('iPhone'), findsOneWidget);
      expect(find.text('MacBook'), findsOneWidget);
      expect(find.textContaining('this device'), findsOneWidget);
      expect(
        find.textContaining('Last write wins'),
        findsOneWidget,
      );
      // No revoke action on the current device, one on the other.
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    });
  });

  group('SettingsPage layout', () {
    testWidgets('cloud backup sits under Account & sync when signed in',
        (tester) async {
      await tester.pumpWidget(
        pumpApp(
          harness.db,
          child: const SettingsPage(),
          categories: const [],
          extraOverrides: [
            syncControllerProvider.overrideWith(
              () => FakeSyncController(
                SyncStatus(
                  enabled: true,
                  signedIn: true,
                  email: 'me@finflow.dev',
                  backupSchedule: BackupSchedule.daily,
                  backupPassphraseSet: true,
                  lastBackupAt: DateTime.now(),
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Account & sync'), findsOneWidget);
      // Visible without scrolling ⇒ the section sits near the top, directly
      // under the sync card (not buried below Security / Backup & restore).
      expect(find.text('Cloud backup'), findsOneWidget);
      expect(find.text('Cloud backup (encrypted)'), findsOneWidget);
      expect(find.text('Passphrase saved on this device'), findsOneWidget);

      // The Cloud backup section must come before Appearance in the page's
      // ListView child order (ListView builds below the fold lazily, so
      // compare the widget list rather than on-screen positions).
      final listView = tester.widget<ListView>(find.byType(ListView));
      final children = (listView.childrenDelegate as SliverChildListDelegate)
          .children;
      int? backupIdx;
      int? appearanceIdx;
      for (var i = 0; i < children.length; i++) {
        final widget = children[i];
        if (widget is SectionHeader && widget.title == 'Cloud backup') {
          backupIdx = i;
        }
        if (widget is SectionHeader && widget.title == 'Appearance') {
          appearanceIdx = i;
        }
      }
      expect(backupIdx, isNotNull);
      expect(appearanceIdx, isNotNull);
      expect(backupIdx!, lessThan(appearanceIdx!));
    });

    testWidgets('cloud backup section is hidden when signed out',
        (tester) async {
      await tester.pumpWidget(
        pumpApp(
          harness.db,
          child: const SettingsPage(),
          categories: const [],
          extraOverrides: [
            syncControllerProvider.overrideWith(
              () => FakeSyncController(const SyncStatus(enabled: true)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in to sync'), findsOneWidget);
      expect(find.text('Cloud backup'), findsNothing);
      expect(find.text('Cloud backup (encrypted)'), findsNothing);
    });
  });
}
