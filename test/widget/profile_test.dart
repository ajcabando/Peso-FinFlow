import 'package:drift/native.dart';
import 'package:finflow/app/providers/app_providers.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:finflow/features/settings/presentation/pages/settings_page.dart';
import 'package:finflow/features/sync/domain/sync_status.dart';
import 'package:finflow/features/sync/presentation/providers/sync_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/widget_harness.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      pumpApp(
        db,
        child: const DashboardPage(),
        netWorth: 0,
        accountsWithBalances: const [],
        recentContexts: const [],
        cashFlow: const [],
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      pumpApp(
        db,
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
  }

  group('dashboard greeting', () {
    testWidgets('falls back to the plain greeting without a profile name', (
      tester,
    ) async {
      await pumpDashboard(tester);

      // Greets without a name; the avatar is the gradient placeholder.
      expect(find.textContaining('Good '), findsOneWidget);
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('greets by first name when a profile name is set', (
      tester,
    ) async {
      await db.settingsDao.set(SettingsKeys.profileName, 'Alain M.');
      await pumpDashboard(tester);

      // "Good morning/afternoon/evening, Alain" — the time word varies, so
      // assert on the name and the greeting shape.
      expect(find.textContaining('Good '), findsOneWidget);
      expect(find.textContaining('Alain'), findsOneWidget);
    });

    testWidgets('tapping the avatar opens the profile editor', (tester) async {
      await pumpDashboard(tester);

      await tester.tap(find.byIcon(Icons.person_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);
    });
  });

  group('settings profile card', () {
    testWidgets('shows the name and an edit entry', (tester) async {
      await db.settingsDao.set(SettingsKeys.profileName, 'Alain');
      await pumpSettings(tester);

      expect(find.text('Alain'), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    });

    testWidgets('prompts to set up the profile before a name exists', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text('Your profile'), findsOneWidget);
      expect(
        find.textContaining('Add your name and photo'),
        findsOneWidget,
      );
    });

    testWidgets('editing the name updates the profile and the header', (
      tester,
    ) async {
      await pumpSettings(tester);

      await tester.tap(find.byIcon(Icons.edit_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Edit profile'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Alain');
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();

      // Persisted and reflected in the header card.
      expect(await db.settingsDao.get(SettingsKeys.profileName), 'Alain');
      expect(find.text('Alain'), findsOneWidget);
      expect(find.text('Your profile'), findsNothing);
    });
  });
}

/// A [SyncController] that serves a fixed status so the Settings page renders
/// without touching the network.
class FakeSyncController extends SyncController {
  FakeSyncController(this._status);

  final SyncStatus _status;

  @override
  SyncStatus build() => _status;
}
