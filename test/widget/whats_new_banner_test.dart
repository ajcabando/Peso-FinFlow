import 'package:drift/native.dart';
import 'package:finflow/app/providers/app_providers.dart';
import 'package:finflow/database/app_database.dart';
import 'package:finflow/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:finflow/features/whatsnew/domain/whats_new_content.dart';
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

  Widget dashboard() => pumpApp(
    db,
    child: const DashboardPage(),
    netWorth: 0,
    recentContexts: const [],
    cashFlow: const [],
  );

  testWidgets('shows the What\'s new banner on the dashboard by default', (
    tester,
  ) async {
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();

    expect(find.text("What's new"), findsOneWidget);
    expect(find.text(kWhatsNewSubtitle), findsOneWidget);
    // All highlight bullets are rendered.
    for (final item in kWhatsNewItems) {
      expect(find.text(item), findsOneWidget);
    }
    expect(find.text('See the full changelog'), findsOneWidget);
  });

  testWidgets('dismiss hides the banner and persists the revision', (
    tester,
  ) async {
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();
    expect(find.text("What's new"), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    expect(find.text("What's new"), findsNothing);
    // The revision is persisted for future launches.
    expect(
      await db.settingsDao.get(SettingsKeys.whatsNewLastSeen),
      kWhatsNewRevision,
    );
  });

  testWidgets('stays hidden on the next launch after dismissing', (
    tester,
  ) async {
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();

    // A fresh ProviderScope simulates the next launch (same device DB).
    await tester.pumpWidget(Container());
    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();

    expect(find.text("What's new"), findsNothing);
  });

  testWidgets('hidden when the revision was already seen', (tester) async {
    await db.settingsDao.set(SettingsKeys.whatsNewLastSeen, kWhatsNewRevision);

    await tester.pumpWidget(dashboard());
    await tester.pumpAndSettle();

    expect(find.text("What's new"), findsNothing);
  });
}
